import Foundation

enum SettingsMigration {
    static func decode(_ data: Data) throws -> AppSettings {
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        guard settings.version == 1 else { throw SettingsError.unsupportedVersion }
        try settings.validate()
        return settings
    }
}
