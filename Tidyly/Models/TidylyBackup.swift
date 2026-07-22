import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct TidylyBackup: Codable {
    static let currentVersion = 1

    let formatVersion: Int
    let exportedAt: Date
    let rooms: [Room]
    let tasks: [Task]
    let completions: [Completion]
    let activityEvents: [ActivityEvent]
    let settings: Settings
}

struct TidylyBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let backup: TidylyBackup

    init(backup: TidylyBackup) {
        self.backup = backup
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        backup = try Self.decoder.decode(TidylyBackup.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Self.encoder.encode(backup))
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
