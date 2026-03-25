import SwiftUI

enum Persisted {
    @AppStorage("_textOnly") static var textOnly = false
    @AppStorage("_floatingMode") static var floatingMode = false
    @AppStorage("_assetSettings") static var selectedAssetId: Model.Variant.ID?
    @AppStorage("_modelParams") static var modelParams: Data?
}
