import Testing
import Carbon

struct SettingsTests {
    @Test func defaultsAndRoundTrip() throws {
        let settings = AppSettings.defaults
        #expect(settings.version == 1)
        #expect(settings.grid.columns == 8)
        #expect(settings.presets.count == 1)
        #expect(settings.presets[0].name == "Full")
        #expect(settings.presets[0].scope == .global)
        #expect(settings.presets[0].hotKey == HotKey(keyCode: UInt32(kVK_F10), modifiers: [.command], displayKey: "F10"))
        try settings.validate()
        let data = try JSONEncoder().encode(settings)
        let decoded = try SettingsMigration.decode(data)
        #expect(decoded.presets == settings.presets)
        #expect(decoded.general.activationHotKey == settings.general.activationHotKey)
        #expect(settings.general.restoreAllWindowsHotKey == HotKey(keyCode: UInt32(kVK_ANSI_L),
                                                                 modifiers: [.command, .shift], displayKey: "L"))
        #expect(decoded.general.restoreAllWindowsHotKey == settings.general.restoreAllWindowsHotKey)
    }

    @Test func invalidFilePreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let broken = Data("{ invalid".utf8)
        try broken.write(to: url)
        let loaded = SettingsStore(url: url).load()
        #expect(loaded.grid.columns == 8)
        #expect(try Data(contentsOf: url) == broken)
    }

    @Test func defaultsAreInMemoryUntilSaved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(url: url)
        #expect(store.load().grid.rows == 8)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try store.save(.defaults)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(store.load().presets == AppSettings.defaults.presets)
    }

    @Test func missingOptionalNameAndHotKeyValidation() throws {
        var settings = AppSettings.defaults
        var localPreset = settings.presets[0]
        localPreset.id = UUID()
        localPreset.name = nil
        localPreset.scope = .local
        localPreset.hotKey = nil
        settings.presets.append(localPreset)
        let decoded = try SettingsMigration.decode(JSONEncoder().encode(settings))
        #expect(decoded.presets[1].name == nil)
        #expect(decoded.presets[1].hotKey == nil)
        #expect(!HotKey(keyCode: UInt32(kVK_ANSI_A), modifiers: [], displayKey: "A").isGlobalValid)
        #expect(HotKey(keyCode: UInt32(kVK_ANSI_A), modifiers: [], displayKey: "A").isLocalValid)
        #expect(HotKeyModifiers(flags: [.command, .shift]).carbon == UInt32(cmdKey | shiftKey))
        settings.presets[0].hotKey = settings.general.activationHotKey
        #expect(throws: SettingsError.self) { try settings.validate() }
    }

    @Test func physicalKeyIdentityIgnoresDisplayLabel() {
        let english = HotKey(keyCode: UInt32(kVK_ANSI_W), modifiers: [], displayKey: "W")
        let ukrainian = HotKey(keyCode: UInt32(kVK_ANSI_W), modifiers: [], displayKey: "Ц")
        #expect(english == ukrainian)
        #expect(Set([english, ukrainian]).count == 1)
        #expect(HotKey(keyCode: UInt32(kVK_F11), modifiers: [], displayKey: "F11").isGlobalValid)
    }

    @Test func modifiedArrowLocalShortcuts() throws {
        let left = HotKey(keyCode: UInt32(kVK_LeftArrow), modifiers: [.command], displayKey: "←")
        let right = HotKey(keyCode: UInt32(kVK_RightArrow), modifiers: [.command], displayKey: "→")
        #expect(left.isLocalValid)
        #expect(right.isLocalValid)
        for modifiers: HotKeyModifiers in [[.option], [.control], [.command, .shift], [.option, .shift]] {
            #expect(HotKey(keyCode: left.keyCode, modifiers: modifiers, displayKey: "←").isLocalValid)
        }
        for modifiers: HotKeyModifiers in [[], [.shift]] {
            #expect(!HotKey(keyCode: left.keyCode, modifiers: modifiers, displayKey: "←").isLocalValid)
        }
        var settings = AppSettings.defaults
        let area = settings.presets[0].area
        settings.presets.append(WindowPreset(id: UUID(), name: nil, scope: .local, hotKey: left, area: area))
        settings.presets.append(WindowPreset(id: UUID(), name: nil, scope: .local, hotKey: right, area: area))
        try settings.validate()
        settings.presets[2].hotKey = left
        #expect(throws: SettingsError.self) { try settings.validate() }
    }

    @Test func oldSettingsKeepPresetsWhenDefaultSaveShortcutConflicts() throws {
        var settings = AppSettings.defaults
        settings.presets.append(WindowPreset(id: UUID(), name: "Save slot", scope: .local,
                                             hotKey: AppSettings.defaultSaveHotKey,
                                             area: settings.presets[0].area))
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        var general = try #require(object["general"] as? [String: Any])
        general.removeValue(forKey: "saveWindowHotKey")
        general.removeValue(forKey: "restoreWindowHotKey")
        object["general"] = general
        object.removeValue(forKey: "savedWindows")
        let migrated = try SettingsMigration.decode(JSONSerialization.data(withJSONObject: object))
        #expect(migrated.presets.count == 2)
        #expect(migrated.savedWindows.isEmpty)
        #expect(migrated.general.saveWindowHotKey != AppSettings.defaultSaveHotKey)
        #expect(migrated.general.restoreWindowHotKey == AppSettings.defaultRestoreHotKey)
    }

    @Test func savedWindowsRoundTripAndMatchOnlyTheirDisplayResolution() throws {
        var settings = AppSettings.defaults
        let identity = SavedWindow.Identity(bundleID: "com.example.Editor", kind: .document,
                                            value: "file:///tmp/example.txt")
        let saved = SavedWindow(id: UUID(), identity: identity, applicationName: "Editor",
                                windowName: "example.txt", displayName: "Studio Display",
                                displayUUID: "monitor-one",
                                pixelWidth: 3840, pixelHeight: 2160,
                                x: 31.5, y: 42.25, width: 900.5, height: 600.75)
        settings.savedWindows = [saved]
        let decoded = try SettingsMigration.decode(JSONEncoder().encode(settings))
        #expect(decoded.savedWindows == [saved])
        #expect(saved.matches(identity, displayUUID: "monitor-one", pixelWidth: 3840, pixelHeight: 2160))
        #expect(!saved.matches(identity, displayUUID: "monitor-two", pixelWidth: 3840, pixelHeight: 2160))
        #expect(!saved.matches(identity, displayUUID: "monitor-one", pixelWidth: 2560, pixelHeight: 1440))
        settings.savedWindows.append(saved)
        #expect(throws: SettingsError.self) { try settings.validate() }
    }

    @Test func applicationWindowFallbackPersistsAndUsesWindowType() throws {
        var settings = AppSettings.defaults
        let mainWindow = SavedWindow.Identity(bundleID: "com.example.Chat", kind: .applicationWindow,
                                              value: "AXStandardWindow")
        let dialog = SavedWindow.Identity(bundleID: "com.example.Chat", kind: .applicationWindow,
                                          value: "AXDialog")
        let saved = SavedWindow(id: UUID(), identity: mainWindow, applicationName: "Chat",
                                windowName: "Chat", displayName: "Display", displayUUID: "monitor-one",
                                pixelWidth: 1920, pixelHeight: 1080,
                                x: 10, y: 20, width: 900, height: 600)
        settings.savedWindows = [saved]
        let decoded = try SettingsMigration.decode(JSONEncoder().encode(settings))
        #expect(decoded.savedWindows == [saved])
        #expect(!saved.matches(dialog, displayUUID: "monitor-one", pixelWidth: 1920, pixelHeight: 1080))

        var another = saved
        another.id = UUID()
        another.identity = dialog
        settings.savedWindows.append(another)
        try settings.validate()
        settings.savedWindows[1].identity = mainWindow
        #expect(throws: SettingsError.self) { try settings.validate() }
    }

    @Test func restoreAllShortcutCanBeEditedAndPersisted() throws {
        var settings = AppSettings.defaults
        let custom = HotKey(keyCode: UInt32(kVK_ANSI_R), modifiers: [.command, .option], displayKey: "R")
        settings.general.restoreAllWindowsHotKey = custom
        let decoded = try SettingsMigration.decode(JSONEncoder().encode(settings))
        #expect(decoded.general.restoreAllWindowsHotKey == custom)
        #expect(decoded.general.restoreWindowHotKey == AppSettings.defaultRestoreHotKey)
    }

    @Test func oldSettingsGainRestoreAllWithoutChangingExistingShortcuts() throws {
        let settings = AppSettings.defaults
        let migrated = try withoutRestoreAllShortcut(settings)
        #expect(migrated.general.restoreAllWindowsHotKey == AppSettings.defaultRestoreAllHotKey)
        #expect(migrated.general.saveWindowHotKey == settings.general.saveWindowHotKey)
        #expect(migrated.general.restoreWindowHotKey == settings.general.restoreWindowHotKey)
        #expect(migrated.presets == settings.presets)
    }

    @Test(arguments: [ShortcutScope.local, .global])
    func oldSettingsKeepPresetsUsingRestoreAllDefault(scope: ShortcutScope) throws {
        var settings = AppSettings.defaults
        settings.presets.append(WindowPreset(id: UUID(), name: "Existing shortcut", scope: scope,
                                             hotKey: AppSettings.defaultRestoreAllHotKey, area: settings.presets[0].area))
        let migrated = try withoutRestoreAllShortcut(settings)
        #expect(migrated.presets == settings.presets)
        #expect(migrated.general.restoreAllWindowsHotKey != AppSettings.defaultRestoreAllHotKey)
        try migrated.validate()
    }

    @Test func restoreAllShortcutCannotConflictWithOtherActions() throws {
        var settings = AppSettings.defaults
        for key in [settings.general.saveWindowHotKey, settings.general.restoreWindowHotKey,
                    settings.general.activationHotKey, try #require(settings.presets[0].hotKey)] {
            settings.general.restoreAllWindowsHotKey = key
            #expect(throws: SettingsError.conflict) { try settings.validate() }
        }
        settings.general.restoreAllWindowsHotKey = HotKey(keyCode: UInt32(kVK_Return), modifiers: [], displayKey: "Return")
        #expect(throws: SettingsError.invalid) { try settings.validate() }
    }

    @Test func savedFrameUsesTheMonitorOriginWithoutGridSnapping() {
        let saved = SavedWindow(id: UUID(), identity: .init(bundleID: "com.example.Editor", kind: .document, value: "file:///test"),
                                applicationName: "Editor", windowName: "Test", displayName: "Display", displayUUID: "display",
                                pixelWidth: 1920, pixelHeight: 1080, x: 31.5, y: 42.25, width: 900.5, height: 600.75)
        #expect(saved.frame(on: CGRect(x: -1920, y: 1080, width: 1920, height: 1080))
                == CGRect(x: -1888.5, y: 1122.25, width: 900.5, height: 600.75))
    }

    private func withoutRestoreAllShortcut(_ settings: AppSettings) throws -> AppSettings {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        var general = try #require(object["general"] as? [String: Any])
        general.removeValue(forKey: "restoreAllWindowsHotKey")
        object["general"] = general
        return try SettingsMigration.decode(JSONSerialization.data(withJSONObject: object))
    }
}
