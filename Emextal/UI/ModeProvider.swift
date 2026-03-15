internal import Foundation
internal import SwiftUI

struct ModeView: View {
    let modeProvider: ViewModel

    var body: some View {
        let mode = modeProvider.mode
        ZStack {
            switch mode {
            case .error:
                EmptyView()

            case .booting, .loading, .shutdown, .startup, .warmup:
                Image(systemName: "hourglass.circle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .symbolEffect(.rotate)
                    .opacity(0.4)

            case .waiting:
                Image(systemName: "circle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)

                Text(modeProvider.micPermission ? "Push to\nSpeak" : "Need Mic\nPermission")
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

            case let .listening(state, _):
                switch state {
                case .talking:
                    Image(systemName: "waveform.circle")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .symbolEffect(.variableColor.iterative)

                case .quiet:
                    Image(systemName: "waveform.circle")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .opacity(0.4)
                }

            case .replying:
                Image(systemName: "waveform.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .symbolEffect(.variableColor)

            case .processingPrompt, .transcribingDone:
                Image(systemName: "ellipsis.circle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .symbolEffect(.variableColor)

            case .transcribing:
                Image(systemName: "circle.dotted.circle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .symbolEffect(.rotate)
            }
        }
        .animation(.easeInOut, value: mode)
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { _ in
                if !modeProvider.buttonPushed {
                    modeProvider.buttonPushed = true
                }
            }
            .onEnded { _ in
                if modeProvider.buttonPushed {
                    modeProvider.buttonPushed = false
                }
            })
        .contentTransition(.opacity)
        .fontWeight(.light)
    }
}
