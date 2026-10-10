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

struct SavedWindow: Codable, Identifiable, Equatable {
    struct Identity: Codable, Hashable {
        enum Kind: String, Codable { case document, accessibilityIdentifier }
        var bundleID: String
        var kind: Kind
        var value: String
    }

    struct StorageKey: Hashable {
        var identity: Identity
        var displayUUID: String
        var pixelWidth: Int
        var pixelHeight: Int
    }

    var id: UUID
    var identity: Identity
    var applicationName: String
    var windowName: String
    var displayName: String
    var displayUUID: String
    var pixelWidth: Int
    var pixelHeight: Int
    // AppKit point coordinates relative to the display's lower-left corner.
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var storageKey: StorageKey {
        StorageKey(identity: identity, displayUUID: displayUUID,
                   pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }

    func matches(_ identity: Identity, displayUUID: String, pixelWidth: Int, pixelHeight: Int) -> Bool {
        self.identity == identity && self.displayUUID == displayUUID &&
            self.pixelWidth == pixelWidth && self.pixelHeight == pixelHeight
    }
}

struct AppSettings: Codable {
    struct General: Codable {
        var showMenuBarIcon: Bool
        var activationHotKey: HotKey
        var saveWindowHotKey: HotKey
        var restoreWindowHotKey: HotKey

        init(showMenuBarIcon: Bool, activationHotKey: HotKey, saveWindowHotKey: HotKey,
             restoreWindowHotKey: HotKey) {
            self.showMenuBarIcon = showMenuBarIcon
            self.activationHotKey = activationHotKey
            self.saveWindowHotKey = saveWindowHotKey
            self.restoreWindowHotKey = restoreWindowHotKey
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            showMenuBarIcon = try values.decode(Bool.self, forKey: .showMenuBarIcon)
            activationHotKey = try values.decode(HotKey.self, forKey: .activationHotKey)
            saveWindowHotKey = try values.decodeIfPresent(HotKey.self, forKey: .saveWindowHotKey)
                ?? AppSettings.defaultSaveHotKey
            restoreWindowHotKey = try values.decodeIfPresent(HotKey.self, forKey: .restoreWindowHotKey)
                ?? AppSettings.defaultRestoreHotKey
        }
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
    var savedWindows: [SavedWindow] = []

    static let defaultSaveHotKey = HotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: [.command], displayKey: "S")
    static let defaultRestoreHotKey = HotKey(keyCode: UInt32(kVK_ANSI_L), modifiers: [.command], displayKey: "L")

    init(version: Int = 1, general: General, grid: Grid, presets: [WindowPreset], savedWindows: [SavedWindow] = []) {
        self.version = version
        self.general = general
        self.grid = grid
        self.presets = presets
        self.savedWindows = savedWindows
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        general = try values.decode(General.self, forKey: .general)
        grid = try values.decode(Grid.self, forKey: .grid)
        presets = try values.decode([WindowPreset].self, forKey: .presets)
        savedWindows = try values.decodeIfPresent([SavedWindow].self, forKey: .savedWindows) ?? []
    }

    static let defaults = AppSettings(
        general: General(showMenuBarIcon: true,
                         activationHotKey: HotKey(keyCode: UInt32(kVK_F11), modifiers: [.command], displayKey: "F11"),
                         saveWindowHotKey: defaultSaveHotKey, restoreWindowHotKey: defaultRestoreHotKey),
        grid: Grid(columns: 8, rows: 8),
        presets: [
            WindowPreset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Full", scope: .global,
                         hotKey: HotKey(keyCode: UInt32(kVK_F10), modifiers: [.command], displayKey: "F10"),
                         area: StoredGridArea(x: 0, y: 0, width: 8, height: 8, columns: 8, rows: 8))
        ]
    )

    func validate() throws {
        guard grid.isValid, general.activationHotKey.isGlobalValid else { throw SettingsError.invalid }
        var globalKeys: Set<HotKey> = [general.activationHotKey]
        guard general.saveWindowHotKey.isLocalValid, general.restoreWindowHotKey.isLocalValid else {
            throw SettingsError.invalid
        }
        var localKeys: Set<HotKey> = [general.saveWindowHotKey, general.restoreWindowHotKey]
        guard localKeys.count == 2 else { throw SettingsError.conflict }
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
        var savedKeys: Set<SavedWindow.StorageKey> = []
        var savedIDs: Set<UUID> = []
        for saved in savedWindows {
            guard savedIDs.insert(saved.id).inserted, !saved.identity.bundleID.isEmpty,
                  !saved.identity.value.isEmpty, !saved.displayUUID.isEmpty,
                  saved.pixelWidth > 0, saved.pixelHeight > 0,
                  saved.width > 0, saved.height > 0,
                  [saved.x, saved.y, saved.width, saved.height].allSatisfy(\.isFinite) else {
                throw SettingsError.invalid
            }
            guard savedKeys.insert(saved.storageKey).inserted else { throw SettingsError.invalid }
        }
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
