import Foundation
import os

final class SettingsStore {
    let url: URL
    private let logger = Logger(subsystem: "com.local.vindustilpasser", category: "settings")

    init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/vindustilpasser/settings.json")) {
        self.url = url
    }

    func load() -> AppSettings {
        guard FileManager.default.fileExists(atPath: url.path) else { return .defaults }
        do { return try SettingsMigration.decode(Data(contentsOf: url)) }
        catch {
            logger.error("Cannot load settings: \(error.localizedDescription)")
            return .defaults
        }
    }

    func save(_ settings: AppSettings) throws {
        try settings.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
