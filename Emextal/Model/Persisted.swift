import SwiftUI

enum Persisted {
    @AppStorage("_textOnly") static var textOnly = false
    @AppStorage("_modelParams") static var modelParams: Data?
    @AppStorage("_lastSelectedModelId") static var lastSelectedModelId: String?
}
