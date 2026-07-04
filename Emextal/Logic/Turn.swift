import Foundation
import HTMLString
import Ink

nonisolated struct Turn: Codable {
    let id: UUID
    let prompt: String
    var text: String
    var image: URL?

    var count: Int {
        prompt.count + text.count
    }

    func renderHtml(parser: MarkdownParser) -> String {
        // Transcription turns carry no prompt; skip the heading so the text renders as body copy.
        let promptText: String? = prompt.isEmpty ? nil : "\n#### \(prompt.addingUnicodeEntities())"
        let imageText: String? = if let image {
            "![Image](\(image))"
        } else {
            nil
        }
        let markdown = [promptText, imageText, text].compactMap(\.self).joined(separator: "\n")
        let source = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        return if source.isEmpty {
            ""
        } else {
            parser.html(from: source)
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
        }
    }

    init(id: UUID = UUID(), prompt: String, text: String, image: ImageClass?) {
        self.id = id
        self.prompt = prompt
        self.text = text

        if let imgData = ImageUtilities.jpegData(from: image) {
            let filename = UUID().uuidString + "-attachment.jpg"
            let path = WebView.temporaryDirectory.appendingPathComponent(filename)
            do {
                try imgData.write(to: path)
                self.image = path
            } catch {
                log("Warning: Error saving image: \(error)")
            }
        }
    }
}
