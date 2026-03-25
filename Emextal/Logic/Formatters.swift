import Foundation

nonisolated let memoryFormatter = ByteCountFormatStyle(style: .binary, allowedUnits: .all, spellsOutZero: true, includesActualByteCount: false, locale: .autoupdatingCurrent)

nonisolated let byteFormatter = ByteCountFormatStyle(style: .file, allowedUnits: .all, spellsOutZero: false, includesActualByteCount: false, locale: .autoupdatingCurrent)
