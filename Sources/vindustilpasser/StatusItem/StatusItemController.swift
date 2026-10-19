import AppKit

@MainActor
final class StatusItemController: NSObject {
    private var item: NSStatusItem?
    let menu = NSMenu()
    var onOpen: (() -> Void)?
    var onSaveWindow: (() -> Void)?
    var onRestoreWindow: (() -> Void)?
    var onRestoreAllWindows: (() -> Void)?
    var onPreset: ((UUID) -> Void)?
    var onSettings: (() -> Void)?
    var onAbout: (() -> Void)?
    var onQuit: (() -> Void)?
    var screen: NSScreen? { item?.button?.window?.screen }
    var window: NSWindow? { item?.button?.window }

    func apply(settings: AppSettings) {
        rebuildMenu(settings: settings)
        if settings.general.showMenuBarIcon, item == nil {
            let newItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            newItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x3", accessibilityDescription: "vindustilpasser")
            newItem.button?.image?.isTemplate = true
            newItem.menu = menu
            item = newItem
        } else if !settings.general.showMenuBarIcon, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    private func rebuildMenu(settings: AppSettings) {
        menu.removeAllItems()
        menu.addItem(menuItem("Activate vindustilpasser", action: #selector(open),
                              hotKey: settings.general.activationHotKey))
        menu.addItem(menuItem("Save window", action: #selector(saveWindow),
                              hotKey: settings.general.saveWindowHotKey))
        menu.addItem(menuItem("Restore window", action: #selector(restoreWindow),
                              hotKey: settings.general.restoreWindowHotKey))
        menu.addItem(menuItem("Restore all windows", action: #selector(restoreAllWindows),
                              hotKey: settings.general.restoreAllWindowsHotKey))
        let presets = NSMenuItem(title: "Presets", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "Presets")
        for preset in settings.presets {
            let item = menuItem(preset.name ?? "Untitled", action: #selector(applyPreset(_:)), hotKey: preset.hotKey)
            item.representedObject = preset.id
            submenu.addItem(item)
        }
        if settings.presets.isEmpty {
            let empty = NSMenuItem(title: "No presets", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }
        presets.submenu = submenu
        menu.addItem(presets)
        let settingsItem = menuItem("Settings…", action: #selector(Self.settings))
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)
        menu.addItem(menuItem("About", action: #selector(about)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit", action: #selector(quit)))
    }

    private func menuItem(_ title: String, action: Selector, hotKey: HotKey? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: hotKey?.menuKeyEquivalent ?? "")
        item.keyEquivalentModifierMask = hotKey?.menuModifierMask ?? []
        item.target = self
        return item
    }

    @objc private func open() { onOpen?() }
    @objc private func saveWindow() { onSaveWindow?() }
    @objc private func restoreWindow() { onRestoreWindow?() }
    @objc private func restoreAllWindows() { onRestoreAllWindows?() }
    @objc private func applyPreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        onPreset?(id)
    }
    @objc private func settings() { onSettings?() }
    @objc private func about() { onAbout?() }
    @objc private func quit() { onQuit?() }
}
