import Foundation
import SwiftUI

private extension Binding {
    // thanks to https://stackoverflow.com/questions/65736518/how-do-i-create-a-slider-in-swiftui-for-an-int-type-property

    static func convert<TInt: BinaryInteger & Sendable, TFloat: BinaryFloatingPoint & Sendable>(from intBinding: Binding<TInt>) -> Binding<TFloat> {
        Binding<TFloat>(
            get: { TFloat(intBinding.wrappedValue) },
            set: { intBinding.wrappedValue = TInt($0) }
        )
    }

    static func convert<TFloat: BinaryFloatingPoint & Sendable, TInt: BinaryInteger & Sendable>(from floatBinding: Binding<TFloat>) -> Binding<TInt> {
        Binding<TInt>(
            get: { TInt(floatBinding.wrappedValue) },
            set: { floatBinding.wrappedValue = TFloat($0) }
        )
    }

    static func round<TFloat: BinaryFloatingPoint & Sendable>(from floatBinding: Binding<TFloat>) -> Binding<TFloat> {
        Binding<TFloat>(
            get: { floatBinding.wrappedValue },
            set: { floatBinding.wrappedValue = ($0 * 100.0).rounded() / 100.0 }
        )
    }
}

private struct DescriptorTitle: View {
    let descriptor: Model.Params.Descriptors.Descriptor
    let value: Float

    var body: some View {
        HStack {
            Text(descriptor.title)
                .opacity(0.8)
            if value == descriptor.disabled {
                Text("Disabled")
            } else {
                Text(value, format: .number)
            }
            Spacer()
        }
    }
}

private struct IntRow: View {
    let descriptor: Model.Params.Descriptors.Descriptor
    @Binding var value: Int

    var body: some View {
        VStack {
            DescriptorTitle(descriptor: descriptor, value: Float(value))
            Slider(value: .convert(from: $value), in: descriptor.min ... descriptor.max)
        }
    }
}

private struct FloatRow: View {
    let descriptor: Model.Params.Descriptors.Descriptor
    @Binding var value: Float

    var body: some View {
        VStack {
            DescriptorTitle(descriptor: descriptor, value: value)
            Slider(value: .round(from: $value), in: descriptor.min ... descriptor.max)
        }
    }
}

struct ParamsView: View {
    @Bindable var model: Model

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(spacing: 24) {
            if model.variant.acceptsSystemPrompt {
                VStack(alignment: .leading) {
                    if horizontalSizeClass == .compact {
                        Text("System Prompt")
                            .padding(.top, 3)

                        Text("Applied when creating, or after resetting, a conversation")
                            .foregroundStyle(.secondary)
                            .font(.caption2)
                    } else {
                        HStack(alignment: .bottom) {
                            Text("System Prompt")
                                .padding(.top, 3)

                            Spacer()

                            Text("Applied when creating, or after resetting, a conversation")
                                .foregroundStyle(.secondary)
                                .font(.caption2)
                        }
                    }

                    TextField("System Prompt", text: $model.params.systemPrompt, axis: .vertical)
                        .textFieldStyle(.plain)
                        .padding([.top, .bottom], 4)
                        .padding([.leading, .trailing], 7)
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            RoundedRectangle(cornerSize: CGSize(width: 8, height: 8), style: .continuous)
                                .stroke(.secondary)
                        }
                }
                .multilineTextAlignment(.leading)
            }

            let params = model.params

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

                    if model.params.supportsQuantisation {
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
                if model.variant.supportsThinking {
                    Toggle("Enable reasoning mode", isOn: $model.params.enableThinking)
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
