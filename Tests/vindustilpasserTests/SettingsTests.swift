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
}
