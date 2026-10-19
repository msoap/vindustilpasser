import AppKit
import Carbon
import Testing

struct StatusItemControllerTests {
    private var settings: AppSettings {
        var settings = AppSettings.defaults
        settings.general.showMenuBarIcon = false
        return settings
    }

    @Test @MainActor func windowActionsAndPresetsAppearBeforeSettings() {
        let controller = StatusItemController()
        controller.apply(settings: settings)

        #expect(controller.menu.items.map(\.title) == [
            "Activate vindustilpasser", "Save window", "Restore window", "Restore all windows",
            "Presets", "Settings…", "About", "", "Quit"
        ])
        #expect(controller.menu.item(withTitle: "Save window")?.keyEquivalent == "s")
        #expect(controller.menu.item(withTitle: "Restore window")?.keyEquivalent == "l")
        #expect(controller.menu.item(withTitle: "Restore all windows")?.keyEquivalentModifierMask == [.command, .shift])
        #expect(controller.menu.item(withTitle: "Settings…")?.keyEquivalent == ",")
    }

    @Test @MainActor func settingsChangesRefreshEveryWindowShortcut() throws {
        let controller = StatusItemController()
        var updated = settings
        controller.apply(settings: updated)
        updated.general.activationHotKey = HotKey(keyCode: UInt32(kVK_F12), modifiers: [.control], displayKey: "F12")
        updated.general.saveWindowHotKey = HotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: [.option], displayKey: "S")
        updated.general.restoreWindowHotKey = HotKey(keyCode: UInt32(kVK_ANSI_R), modifiers: [.command], displayKey: "R")
        updated.general.restoreAllWindowsHotKey = HotKey(keyCode: UInt32(kVK_ANSI_R), modifiers: [.command, .shift], displayKey: "R")
        controller.apply(settings: updated)

        for (title, key) in [
            ("Activate vindustilpasser", updated.general.activationHotKey),
            ("Save window", updated.general.saveWindowHotKey),
            ("Restore window", updated.general.restoreWindowHotKey),
            ("Restore all windows", updated.general.restoreAllWindowsHotKey)
        ] {
            let item = try #require(controller.menu.item(withTitle: title))
            #expect(item.keyEquivalent == key.menuKeyEquivalent)
            #expect(item.keyEquivalentModifierMask == key.menuModifierMask)
        }
    }

    @Test @MainActor func presetsIncludeEveryScopeAndRefreshAfterEdits() throws {
        let controller = StatusItemController()
        var updated = settings
        controller.apply(settings: updated)
        updated.presets[0].name = "Renamed full screen"
        updated.presets[0].hotKey = HotKey(keyCode: UInt32(kVK_F9), modifiers: [.option], displayKey: "F9")
        let local = WindowPreset(id: UUID(), name: "Left", scope: .local,
                                 hotKey: HotKey(keyCode: UInt32(kVK_ANSI_A), modifiers: [], displayKey: "A"),
                                 area: updated.presets[0].area)
        let unassigned = WindowPreset(id: UUID(), name: nil, scope: .global, hotKey: nil,
                                      area: updated.presets[0].area)
        updated.presets += [local, unassigned]
        controller.apply(settings: updated)

        var submenu = try #require(controller.menu.item(withTitle: "Presets")?.submenu)
        #expect(submenu.items.map(\.title) == ["Renamed full screen", "Left", "Untitled"])
        #expect(submenu.items.map { $0.representedObject as? UUID } == updated.presets.map { Optional($0.id) })
        #expect(submenu.items[0].keyEquivalent == updated.presets[0].hotKey?.menuKeyEquivalent)
        #expect(submenu.items[0].keyEquivalentModifierMask == .option)
        #expect(submenu.items[1].keyEquivalent == "a")
        #expect(submenu.items[1].keyEquivalentModifierMask == [])
        #expect(submenu.items[2].keyEquivalent.isEmpty)
        #expect(submenu.items[2].keyEquivalentModifierMask == [])

        updated.presets.removeFirst()
        updated.presets[0].hotKey = nil
        controller.apply(settings: updated)
        submenu = try #require(controller.menu.item(withTitle: "Presets")?.submenu)
        #expect(submenu.items.map(\.title) == ["Left", "Untitled"])
        #expect(submenu.items[0].keyEquivalent.isEmpty)
        #expect(submenu.items[0].keyEquivalentModifierMask == [])

        updated.presets.removeAll()
        controller.apply(settings: updated)
        submenu = try #require(controller.menu.item(withTitle: "Presets")?.submenu)
        #expect(submenu.items.map(\.title) == ["No presets"])
        #expect(!submenu.items[0].isEnabled)

        updated.presets = [local]
        controller.apply(settings: updated)
        submenu = try #require(controller.menu.item(withTitle: "Presets")?.submenu)
        #expect(submenu.items.map(\.title) == ["Left"])
    }

    @Test @MainActor func menuActionsDispatchWithoutCreatingAPanel() throws {
        _ = NSApplication.shared
        let controller = StatusItemController()
        var actions: [String] = []
        controller.onSaveWindow = { actions.append("save") }
        controller.onRestoreWindow = { actions.append("restore") }
        controller.onRestoreAllWindows = { actions.append("restore all") }
        var selectedPresets: [UUID] = []
        controller.onPreset = { selectedPresets.append($0) }
        var updated = settings
        controller.apply(settings: updated)
        for title in ["Save window", "Restore window", "Restore all windows"] {
            controller.menu.performActionForItem(at: controller.menu.indexOfItem(withTitle: title))
        }
        #expect(actions == ["save", "restore", "restore all"])

        let added = WindowPreset(id: UUID(), name: "New preset", scope: .local, hotKey: nil,
                                 area: updated.presets[0].area)
        updated.presets.insert(added, at: 0)
        controller.apply(settings: updated)
        var submenu = try #require(controller.menu.item(withTitle: "Presets")?.submenu)
        submenu.performActionForItem(at: 0)
        submenu.performActionForItem(at: 1)
        #expect(selectedPresets == updated.presets.map(\.id))

        updated.presets.removeFirst()
        controller.apply(settings: updated)
        submenu = try #require(controller.menu.item(withTitle: "Presets")?.submenu)
        submenu.performActionForItem(at: 0)
        #expect(selectedPresets.last == updated.presets[0].id)
    }
}
