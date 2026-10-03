import Carbon
import Foundation

enum ShortcutScope: String, Codable {
    case global
    case local
}

struct WindowPreset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String?
    var scope: ShortcutScope
    var hotKey: HotKey?
    var area: StoredGridArea
}

struct AppSettings: Codable {
    struct General: Codable {
        var showMenuBarIcon: Bool
        var activationHotKey: HotKey
    }

    struct Grid: Codable {
        var columns: Int
        var rows: Int
        var isValid: Bool { (1...32).contains(columns) && (1...32).contains(rows) }
    }

    var version = 1
    var general: General
    var grid: Grid
    var presets: [WindowPreset]

    static let defaults = AppSettings(
        general: General(showMenuBarIcon: true, activationHotKey: HotKey(keyCode: UInt32(kVK_F11), modifiers: [.command], displayKey: "F11")),
        grid: Grid(columns: 8, rows: 8),
        presets: [
            WindowPreset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Full", scope: .global,
                         hotKey: HotKey(keyCode: UInt32(kVK_F10), modifiers: [.command], displayKey: "F10"),
                         area: StoredGridArea(x: 0, y: 0, width: 8, height: 8, columns: 8, rows: 8)),
            WindowPreset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Left Half", scope: .local,
                         hotKey: HotKey(keyCode: UInt32(kVK_ANSI_1), modifiers: [], displayKey: "1"),
                         area: StoredGridArea(x: 0, y: 0, width: 4, height: 8, columns: 8, rows: 8)),
            WindowPreset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "Right Half", scope: .local,
                         hotKey: HotKey(keyCode: UInt32(kVK_ANSI_2), modifiers: [], displayKey: "2"),
                         area: StoredGridArea(x: 4, y: 0, width: 4, height: 8, columns: 8, rows: 8))
        ]
    )

    func validate() throws {
        guard grid.isValid, general.activationHotKey.isGlobalValid else { throw SettingsError.invalid }
        var globalKeys: Set<HotKey> = [general.activationHotKey]
        var localKeys: Set<HotKey> = []
        var presetIDs: Set<UUID> = []
        for preset in presets {
            guard preset.area.isValid, presetIDs.insert(preset.id).inserted else { throw SettingsError.invalid }
            guard let key = preset.hotKey else { continue }
            if preset.scope == .global {
                guard key.isGlobalValid else { throw SettingsError.invalid }
                guard globalKeys.insert(key).inserted else { throw SettingsError.conflict }
            } else {
                guard key.isLocalValid else { throw SettingsError.invalid }
                guard localKeys.insert(key).inserted else { throw SettingsError.conflict }
            }
        }
        guard localKeys.isDisjoint(with: globalKeys) else { throw SettingsError.conflict }
    }
}

enum SettingsError: LocalizedError {
    case invalid
    case conflict
    case unsupportedVersion
    var errorDescription: String? {
        switch self {
        case .invalid: "Invalid grid, preset area, or shortcut."
        case .conflict: "This shortcut is already assigned."
        case .unsupportedVersion: "This settings file uses an unsupported version."
        }
    }
}
