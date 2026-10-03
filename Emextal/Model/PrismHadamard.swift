import Foundation
import MLX
import MLXLMCommon
import MLXNN
import MLXVLM

/// Loader for Prism ML's Hadamard MLX packs (`model_type: prism_hadamard_qwen35`), such as Ternary Bonsai.
///
/// These are stock Qwen 3.5 checkpoints whose 2-bit affine weights were folded into a rotated basis. Every
/// packed linear layer expects its input to have gone through a signed, normalised Walsh-Hadamard transform
/// applied in fixed-size blocks, and the packed token embedding yields rows in that rotated basis which must
/// be rotated back. `config.json` lists the affected layers under `modules`, and each one stores its sign
/// vector next to its weights as `<path>.signs`. Everything else — the vision tower, norms, the GDN state
/// parameters — is untouched, so the model is a regular `Qwen35` with those layers swapped out.
///
/// This mirrors the pack's own Python runtime (`runtime/runtime.py` and `runtime/vision_artifact.py`).
nonisolated enum PrismHadamard {
    static let modelType = "prism_hadamard_qwen35"

    enum LoadError: LocalizedError {
        case unsupportedPack(String)

        var errorDescription: String? {
            switch self {
            case let .unsupportedPack(reason): "Unsupported Prism Hadamard pack: \(reason)"
            }
        }
    }

    private struct PackConfiguration: Decodable {
        struct Module: Decodable {
            let path: String
            let block: Int
            let embedding: Bool
            let dtype: String
        }

        struct Quantization: Decodable {
            let bits: Int
            let groupSize: Int
            let mode: String

            enum CodingKeys: String, CodingKey {
                case bits, mode
                case groupSize = "group_size"
            }
        }

        struct Components: Decodable {
            let vision: Bool?
        }

        let schemaVersion: Int
        let baseModelType: String
        let modules: [Module]
        let quantization: Quantization
        let components: Components?

        enum CodingKeys: String, CodingKey {
            case modules, quantization, components
            case schemaVersion = "schema_version"
            case baseModelType = "base_model_type"
        }
    }

    /// Teaches the VLM factory about the pack's model type. Registration replaces any previous entry, so
    /// calling this more than once is harmless.
    static func register() async {
        await VLMTypeRegistry.shared.registerModelType(modelType, creator: createModel)
    }

    private static func createModel(configuration: Data) throws -> any LanguageModel {
        let decoder = JSONDecoder()
        let pack = try decoder.decode(PackConfiguration.self, from: configuration)

        guard (1 ... 2).contains(pack.schemaVersion) else {
            throw LoadError.unsupportedPack("schema version \(pack.schemaVersion)")
        }
        guard pack.baseModelType == "qwen3_5" else {
            throw LoadError.unsupportedPack("base model type \(pack.baseModelType)")
        }
        // The wrapped `Qwen35` always carries a vision tower, so a text-only pack would be missing weights.
        guard pack.components?.vision == true else {
            throw LoadError.unsupportedPack("text-only packs are not supported")
        }
        guard pack.quantization.mode == "affine" else {
            throw LoadError.unsupportedPack("quantization mode \(pack.quantization.mode)")
        }
        let mode = QuantizationMode.affine

        let model = try Qwen35(decoder.decode(Qwen35Configuration.self, from: configuration))
        let bits = pack.quantization.bits
        let groupSize = pack.quantization.groupSize

        // Swap each listed layer for a Hadamard-aware quantized one. These start with placeholder arrays of
        // the right shapes; the regular weight loading fills them in (including `signs`) and, because they
        // are already `Quantized`, leaves them alone when it quantizes everything else.
        let leaves = Dictionary(uniqueKeysWithValues: model.leafModules().flattened())
        let memo = HadamardRotationMemo()
        var replacements = [(String, Module)]()
        for record in pack.modules {
            guard [512, 1024, 2048, 4096].contains(record.block) else {
                throw LoadError.unsupportedPack("block size \(record.block) for \(record.path)")
            }
            guard record.dtype == "float16" else {
                throw LoadError.unsupportedPack("activation dtype \(record.dtype) for \(record.path)")
            }

            // Pack paths are relative to the language model; the VLM nests it under `language_model`.
            let path = "language_model." + record.path
            switch leaves[path] {
            case let linear as Linear where !record.embedding:
                let rows = linear.weight.dim(0)
                let width = linear.weight.dim(1)
                try validate(width: width, block: record.block, groupSize: groupSize, path: path)
                replacements.append((path, HadamardQuantizedLinear(rows: rows, width: width, block: record.block, groupSize: groupSize, bits: bits, mode: mode, memo: memo)))

            case let embedding as Embedding where record.embedding:
                let rows = embedding.weight.dim(0)
                let width = embedding.weight.dim(1)
                try validate(width: width, block: record.block, groupSize: groupSize, path: path)
                replacements.append((path, HadamardQuantizedEmbedding(rows: rows, width: width, block: record.block, groupSize: groupSize, bits: bits, mode: mode)))

            default:
                throw LoadError.unsupportedPack("no matching layer at \(path)")
            }
        }
        model.update(modules: ModuleChildren.unflattened(replacements))
        return model
    }

    private static func validate(width: Int, block: Int, groupSize: Int, path: String) throws {
        guard width % block == 0, width % groupSize == 0 else {
            throw LoadError.unsupportedPack("width \(width) of \(path) does not divide into blocks")
        }
    }

    /// The pack's `fwht`: a sign flip followed by a normalised Walsh-Hadamard transform over each `block`-wide
    /// slice of the last axis, or the reverse for `inverse`. The normalised transform is its own inverse, so
    /// only the order of the sign flip changes. Computed in float32, as the reference runtime does.
    static func rotate(_ x: MLXArray, block: Int, signs: MLXArray, inverse: Bool) -> MLXArray {
        // On the forward path, multiplying by float32 signs promotes to float32 within the same kernel, which
        // saves a separate cast on a path that runs before every packed layer. (`asType` is free when the
        // signs are already float32, which they are in the shipped packs.)
        let signs = signs.asType(.float32)
        let y = inverse ? x.asType(.float32) : x * signs
        let rotated = hadamardTransform(y.reshaped([-1, block]), scale: 1 / Float(block).squareRoot()).reshaped(x.shape)
        return (inverse ? rotated * signs : rotated).asType(x.dtype)
    }
}

/// Shares forward rotations between layers that are fed the same activations. q/k/v, gate/up and the GDN
/// `in_proj_qkv`/`in_proj_z` each receive one array instance back to back, and the shipped packs give
/// every layer of a given input width the same sign vector, so without this the same transform is
/// recomputed two or three times over in every decoder layer.
///
/// Only the most recent rotation is kept, so at most one extra activation stays alive (prefill activations
/// can be large). The input is held strongly so its identity can't be recycled by a different array.
///
/// Like the modules that own it this isn't `Sendable`: the model is only ever driven by one caller at a
/// time, which `ModelContainer` enforces.
nonisolated final class HadamardRotationMemo {
    private struct Entry {
        let input: MLXArray
        let block: Int
        let signsKey: Int
        let output: MLXArray
    }

    private var last: Entry?
    /// Distinct sign vectors seen so far, by width. A vector's index here is its key.
    private var knownSigns = [Int: [MLXArray]]()

    /// Interns `signs` by value, so layers whose sign vectors match get the same key. The pack format
    /// stores a vector per layer and doesn't promise they're shared, so this is checked, not assumed.
    func key(for signs: MLXArray) -> Int {
        var known = knownSigns[signs.size, default: []]
        if let index = known.firstIndex(where: { arrayEqual($0, signs).item(Bool.self) }) {
            return index
        }
        known.append(signs)
        knownSigns[signs.size] = known
        return known.count - 1
    }

    func rotate(_ x: MLXArray, block: Int, signs: MLXArray, signsKey: Int) -> MLXArray {
        if let last, last.input === x, last.block == block, last.signsKey == signsKey {
            return last.output
        }
        let output = PrismHadamard.rotate(x, block: block, signs: signs, inverse: false)
        last = Entry(input: x, block: block, signsKey: signsKey, output: output)
        return output
    }
}

/// A quantized linear layer whose weights live in the rotated basis, so its input is rotated to match.
nonisolated final class HadamardQuantizedLinear: QuantizedLinear {
    let block: Int
    let signs: MLXArray
    private let memo: HadamardRotationMemo
    /// Resolved on first use rather than at init, because `signs` is only filled in by weight loading.
    private var signsKey: Int?

    init(rows: Int, width: Int, block: Int, groupSize: Int, bits: Int, mode: QuantizationMode, memo: HadamardRotationMemo) {
        self.block = block
        self.memo = memo
        signs = MLXArray.ones([width], type: Float32.self)
        super.init(
            weight: MLXArray.zeros([rows, width * bits / 32], type: UInt32.self),
            scales: MLXArray.zeros([rows, width / groupSize], type: Float16.self),
            biases: MLXArray.zeros([rows, width / groupSize], type: Float16.self),
            groupSize: groupSize,
            bits: bits,
            mode: mode
        )
    }

    override func callAsFunction(_ x: MLXArray) -> MLXArray {
        let key: Int
        if let signsKey {
            key = signsKey
        } else {
            key = memo.key(for: signs)
            signsKey = key
        }
        return super.callAsFunction(memo.rotate(x, block: block, signs: signs, signsKey: key))
    }
}

/// A quantized embedding whose rows are stored in the rotated basis, so looked-up rows are rotated back.
nonisolated final class HadamardQuantizedEmbedding: QuantizedEmbedding {
    let block: Int
    let signs: MLXArray

    init(rows: Int, width: Int, block: Int, groupSize: Int, bits: Int, mode: QuantizationMode) {
        self.block = block
        signs = MLXArray.ones([width], type: Float32.self)
        super.init(
            weight: MLXArray.zeros([rows, width * bits / 32], type: UInt32.self),
            scales: MLXArray.zeros([rows, width / groupSize], type: Float16.self),
            biases: MLXArray.zeros([rows, width / groupSize], type: Float16.self),
            groupSize: groupSize,
            bits: bits,
            mode: mode
        )
    }

    override func callAsFunction(_ x: MLXArray) -> MLXArray {
        PrismHadamard.rotate(super.callAsFunction(x).asType(.float16), block: block, signs: signs, inverse: true)
    }

    /// Only reached with tied embeddings. Projecting onto rotated rows needs the input rotated forwards.
    override func asLinear(_ x: MLXArray) -> MLXArray {
        super.asLinear(PrismHadamard.rotate(x, block: block, signs: signs, inverse: false))
    }
}
