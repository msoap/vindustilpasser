import AppKit

@MainActor
final class StatusItemController: NSObject {
    private var item: NSStatusItem?
    var onOpen: (() -> Void)?
    var onSettings: (() -> Void)?
    var onAbout: (() -> Void)?
    var onQuit: (() -> Void)?
    var screen: NSScreen? { item?.button?.window?.screen }

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let newItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            newItem.button?.image = NSImage(systemSymbolName: "rectangle.split.3x3", accessibilityDescription: "vindustilpasser")
            newItem.button?.image?.isTemplate = true
            let menu = NSMenu()
            menu.addItem(menuItem("Open vindustilpasser", action: #selector(open)))
            menu.addItem(menuItem("Settings…", action: #selector(settings)))
            menu.addItem(menuItem("About vindustilpasser", action: #selector(about)))
            menu.addItem(.separator())
            menu.addItem(menuItem("Quit", action: #selector(quit)))
            newItem.menu = menu
            item = newItem
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func open() { onOpen?() }
    @objc private func settings() { onSettings?() }
    @objc private func about() { onAbout?() }
    @objc private func quit() { onQuit?() }
}
