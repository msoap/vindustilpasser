import Foundation
import Carbon

enum SettingsMigration {
    static func decode(_ data: Data) throws -> AppSettings {
        var settings = try JSONDecoder().decode(AppSettings.self, from: data)
        guard settings.version == 1 else { throw SettingsError.unsupportedVersion }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let general = object?["general"] as? [String: Any]
        var used = Set(settings.presets.compactMap(\.hotKey))
        used.insert(settings.general.activationHotKey)
        if general?["saveWindowHotKey"] == nil {
            settings.general.saveWindowHotKey = availableKey(code: UInt32(kVK_ANSI_S), label: "S", used: used)
        }
        used.insert(settings.general.saveWindowHotKey)
        if general?["restoreWindowHotKey"] == nil {
            settings.general.restoreWindowHotKey = availableKey(code: UInt32(kVK_ANSI_L), label: "L", used: used)
        }
        try settings.validate()
        return settings
    }

    private static func availableKey(code: UInt32, label: String, used: Set<HotKey>) -> HotKey {
        let modifiers: [HotKeyModifiers] = [[.command], [.command, .shift], [.command, .option],
                                            [.command, .control], [.command, .option, .shift]]
        return modifiers.map { HotKey(keyCode: code, modifiers: $0, displayKey: label) }
            .first { !used.contains($0) } ?? HotKey(keyCode: code, modifiers: [.command], displayKey: label)
    }
}
