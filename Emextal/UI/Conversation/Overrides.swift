import Foundation
import SwiftUI

struct ParamsView: View {
    @Bindable var model: Model

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: - System prompt cells

    private var systemPromptLabel: some View {
        Text("System Prompt")
            .opacity(0.8)
    }

    @ViewBuilder
    private func promptField(fill: Bool) -> some View {
        let base = TextField("System Prompt", text: $model.params.systemPrompt, axis: .vertical)
            .textFieldStyle(.plain)
            .padding([.top, .bottom], 4)
            .padding([.leading, .trailing], 7)

        Group {
            if fill {
                // In the grid the row height is set by the taller context-cache column; let the box
                // fill it, with text anchored to the top.
                base.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                base.fixedSize(horizontal: false, vertical: true)
            }
        }
        .background {
            RoundedRectangle(cornerSize: CGSize(width: 8, height: 8), style: .continuous)
                .stroke(.secondary)
        }
    }

    private var promptCaption: some View {
        Text("Applied when creating, or after resetting, a conversation.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var systemPromptBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            systemPromptLabel
            promptField(fill: false)
            promptCaption
        }
        .multilineTextAlignment(.leading)
    }

    // MARK: - Context-cache cells

    private enum CacheKind: Hashable {
        case unbounded, window
    }

    private let minContextTokens = 4096
    private let contextStep = 1024

    private var defaultWindowTokens: Int {
        min(model.variant.maxContextTokens, 32_768)
    }

    private var currentWindowTokens: Int {
        if case let .window(tokens) = model.params.cacheStrategy { tokens } else { defaultWindowTokens }
    }

    private var cacheKindBinding: Binding<CacheKind> {
        Binding {
            switch model.params.cacheStrategy {
            case .unbounded, .quantized: .unbounded
            case .window: .window
            }
        } set: { newKind in
            switch newKind {
            case .unbounded:
                if case .window = model.params.cacheStrategy { model.params.cacheStrategy = .unbounded }
            case .window:
                if case .window = model.params.cacheStrategy { } else {
                    model.params.cacheStrategy = .window(tokens: defaultWindowTokens)
                }
            }
        }
    }

    private var cacheHeader: some View {
        HStack {
            Text("Context Cache")
                .opacity(0.8)
            Spacer()
            Picker("Context Cache", selection: cacheKindBinding) {
                Text("Unbounded").tag(CacheKind.unbounded)
                Text("Window").tag(CacheKind.window)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var cacheMiddle: some View {
        switch model.params.cacheStrategy {
        case .unbounded, .quantized:
            if model.variant.supportsQuantisation {
                let precision = Binding<Int> {
                    if case let .quantized(bits) = model.params.cacheStrategy { bits } else { 0 }
                } set: { newBits in
                    model.params.cacheStrategy = newBits == 0 ? .unbounded : .quantized(bits: newBits)
                }
                HStack {
                    Text("Precision")
                        .opacity(0.8)
                    Spacer()
                    Picker("Precision", selection: precision) {
                        Text("Full").tag(0)
                        Text("8-bit").tag(8)
                        Text("4-bit").tag(4)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                .transition(.opacity)
            }

        case .window:
            let tokens = currentWindowTokens
            let sliderValue = Binding<Double> {
                Double(tokens)
            } set: { newValue in
                let rounded = Int((newValue / Double(contextStep)).rounded()) * contextStep
                model.params.cacheStrategy = .window(tokens: min(model.variant.maxContextTokens, max(minContextTokens, rounded)))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(tokens, format: .number) tokens")
                Slider(value: sliderValue, in: Double(minContextTokens) ... Double(model.variant.maxContextTokens))
            }
            .transition(.opacity)
        }
    }

    private var cacheCaption: some View {
        let text: String = switch model.params.cacheStrategy {
        case .unbounded: "Keeps the entire conversation at full precision."
        case .quantized: "Keeps all context, compressing the cache to save memory."
        case .window: "Caps memory to the most recent tokens, dropping older context."
        }
        return Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private var cacheBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            cacheHeader
            cacheMiddle
            cacheCaption
        }
    }

    // MARK: - Top section

    @ViewBuilder
    private var topSection: some View {
        if horizontalSizeClass == .compact {
            if model.variant.acceptsSystemPrompt {
                systemPromptBlock
            }
            cacheBlock
        } else if model.variant.acceptsSystemPrompt {
            // A grid keeps the two columns' rows aligned (label↔Context Cache, field↔Precision,
            // caption↔caption) without any per-view inset tuning.
            Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 8) {
                GridRow(alignment: .firstTextBaseline) {
                    systemPromptLabel
                        .frame(maxWidth: .infinity, alignment: .leading)
                    cacheHeader
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow(alignment: .top) {
                    promptField(fill: true)
                    cacheMiddle
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                GridRow(alignment: .firstTextBaseline) {
                    promptCaption
                        .frame(maxWidth: .infinity, alignment: .leading)
                    cacheCaption
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // Pin to the rows' ideal height so the fill-height text field matches the taller column
            // without the grid stretching to soak up any extra height the panel is offered.
            .fixedSize(horizontal: false, vertical: true)
        } else {
            cacheBlock
        }
    }

    var body: some View {
        let params = model.params

        VStack(spacing: 24) {
            topSection

            if horizontalSizeClass == .compact {
                VStack {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            let hasTemp = params.temperature != Model.Params.Descriptors.temperature.disabled
                            FloatRow(descriptor: Model.Params.Descriptors.temperature, value: $model.params.temperature)
                                .opacity(hasTemp ? 1.0 : 0.5)
                        }

                        IntRow(descriptor: Model.Params.Descriptors.topK, value: $model.params.topK)
                            .opacity(params.topK != Int(Model.Params.Descriptors.topK.disabled) ? 1.0 : 0.5)

                        HStack(spacing: 10) {
                            FloatRow(descriptor: Model.Params.Descriptors.topP, value: $model.params.topP)
                                .opacity(params.topP != Model.Params.Descriptors.topP.disabled ? 1.0 : 0.5)

                            FloatRow(descriptor: Model.Params.Descriptors.minP, value: $model.params.minP)
                                .opacity(params.minP != Model.Params.Descriptors.minP.disabled ? 1.0 : 0.5)
                        }
                    }

                    VStack(spacing: 10) {
                        FloatRow(descriptor: Model.Params.Descriptors.repeatPenatly, value: $model.params.repeatPenatly)
                        FloatRow(descriptor: Model.Params.Descriptors.frequencyPenatly, value: $model.params.frequencyPenatly)
                        FloatRow(descriptor: Model.Params.Descriptors.presentPenatly, value: $model.params.presentPenatly)
                    }

                    if model.variant.supportsThinkingSwitch {
                        Toggle("Enable reasoning mode", isOn: $model.params.enableThinking)
                    }
                }

            } else {
                HStack(alignment: .top, spacing: 30) {
                    VStack(spacing: 10) {
                        let hasTemp = params.temperature != Model.Params.Descriptors.temperature.disabled
                        FloatRow(descriptor: Model.Params.Descriptors.temperature, value: $model.params.temperature)
                            .opacity(hasTemp ? 1.0 : 0.5)

                        IntRow(descriptor: Model.Params.Descriptors.topK, value: $model.params.topK)
                            .opacity(params.topK != Int(Model.Params.Descriptors.topK.disabled) ? 1.0 : 0.5)

                        HStack(spacing: 10) {
                            FloatRow(descriptor: Model.Params.Descriptors.topP, value: $model.params.topP)
                                .opacity(params.topP != Model.Params.Descriptors.topP.disabled ? 1.0 : 0.5)

                            FloatRow(descriptor: Model.Params.Descriptors.minP, value: $model.params.minP)
                                .opacity(params.minP != Model.Params.Descriptors.minP.disabled ? 1.0 : 0.5)
                        }
                    }

                    VStack(spacing: 10) {
                        FloatRow(descriptor: Model.Params.Descriptors.repeatPenatly, value: $model.params.repeatPenatly)
                        FloatRow(descriptor: Model.Params.Descriptors.frequencyPenatly, value: $model.params.frequencyPenatly)
                        FloatRow(descriptor: Model.Params.Descriptors.presentPenatly, value: $model.params.presentPenatly)
                    }
                }
            }

            HStack {
                Button("Back") {
                    NotificationCenter.default.post(name: .endModel, object: model)
                }
                Spacer()
                if model.variant.supportsThinkingSwitch {
                    Toggle("Enable reasoning mode", isOn: $model.params.enableThinking)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer()
                }
                Button("Reset to Defaults") {
                    withAnimation {
                        model.resetToDefaults()
                    }
                }
            }
        }
        .font(.callout)
        .padding(16)
        .background(.primary.opacity(0.1))
    }
}
