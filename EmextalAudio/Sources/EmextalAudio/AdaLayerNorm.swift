import Foundation
import MLX
import MLXNN

/// Adaptive Layer Normalization used by the Vocos backbone.
/// Extracted from the Vocos codec; produces scale/shift from a conditioning embedding.
public class AdaLayerNorm: Module {
    let eps: Float
    let dim: Int
    @ModuleInfo(key: "scale") var scale: Linear
    @ModuleInfo(key: "shift") var shift: Linear

    public init(numEmbeddings: Int, embeddingDim: Int, eps: Float = 1e-6) {
        self.eps = eps
        self.dim = embeddingDim

        self._scale.wrappedValue = Linear(numEmbeddings, embeddingDim)
        self._shift.wrappedValue = Linear(numEmbeddings, embeddingDim)
    }

    public func callAsFunction(_ x: MLXArray, condEmbedding: MLXArray) -> MLXArray {
        let scaleVal = scale(condEmbedding)
        let shiftVal = shift(condEmbedding)

        // Manual layer norm without learnable parameters
        // Compute mean and variance along last axis
        let mean = MLX.mean(x, axis: -1, keepDims: true)
        let variance = MLX.variance(x, axis: -1, keepDims: true)
        let normalized = (x - mean) / MLX.sqrt(variance + eps)

        // Apply adaptive scale and shift: x * scale[:, None, :] + shift[:, None, :]
        let scaleBroadcast = scaleVal.expandedDimensions(axis: 1)
        let shiftBroadcast = shiftVal.expandedDimensions(axis: 1)

        return normalized * scaleBroadcast + shiftBroadcast
    }
}
