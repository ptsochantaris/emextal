import AVFoundation
import Foundation

nonisolated enum SoundEffect {
    private static let startCaf = Bundle.main.url(forResource: "MicStart", withExtension: "caf")!
    private static let endCaf = Bundle.main.url(forResource: "MicStop", withExtension: "caf")!

    case startListening, endListening

    var audioFile: AVAudioFile {
        switch self {
        case .startListening:
            try! AVAudioFile(forReading: Self.startCaf)

        case .endListening:
            try! AVAudioFile(forReading: Self.endCaf)
        }
    }

    var preferredVolume: Float {
        switch self {
        case .startListening: 0.1
        case .endListening: 0.4
        }
    }
}
