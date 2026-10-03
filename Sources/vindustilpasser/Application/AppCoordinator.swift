import AppKit
import os

@MainActor
final class AppCoordinator {
    private let settingsStore = SettingsStore()
    private var settings: AppSettings
    private let tracker = ExternalApplicationTracker()
    private lazy var windowManager = WindowManager(tracker: tracker)
    private let panel = GridPanelController()
    private let hotKeys = HotKeyManager()
    private let statusItem = StatusItemController()
    private var preferences: PreferencesWindowController?
    private var commandMonitor: Any?
    private let logger = Logger(subsystem: "com.local.vindustilpasser", category: "app")

    init() {
        settings = settingsStore.load()
        panel.onApply = { [weak self] selection, target in self?.apply(selection: selection, target: target) }
        panel.onPreset = { [weak self] id in self?.applyPreset(id: id) }
        panel.onSettings = { [weak self] in self?.openSettings() }
        panel.onQuit = { [weak self] in self?.quit() }
        hotKeys.onAction = { [weak self] action in
            switch action {
            case .activate: self?.toggleGridPanel()
            case .preset(let id): self?.applyPreset(id: id)
            }
        }
        statusItem.onOpen = { [weak self] in self?.toggleGridPanel() }
        statusItem.onSettings = { [weak self] in self?.openSettings() }
        statusItem.onAbout = { [weak self] in self?.openAbout() }
        statusItem.onQuit = { [weak self] in self?.quit() }
        statusItem.setVisible(settings.general.showMenuBarIcon)
        do { try hotKeys.apply(settings: settings) }
        catch { showError(error) }
        commandMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.handleAppCommand(event) }
            return handled ? nil : event
        }
        logger.info("Started; Accessibility granted: \(AccessibilityPermission.granted)")
    }

    func toggleGridPanel() {
        if panel.isVisible { panel.cancel(); return }
        do { panel.show(target: try windowManager.captureTarget(), settings: settings) }
        catch { showError(error) }
    }

    private func apply(selection: GridSelection, target: WindowTarget) {
        let geometry = GridGeometry(columns: settings.grid.columns, rows: settings.grid.rows)
        let rect = geometry.rect(for: selection, in: target.screen.visibleFrame)
        apply(rect: rect, target: target)
    }

    private func apply(rect: CGRect, target: WindowTarget) {
        do {
            try windowManager.apply(appKitRect: rect, to: target)
            panel.cancel()
        } catch {
            panel.cancel()
            showError(error)
        }
    }

    func applyPreset(id: UUID) {
        guard let preset = settings.presets.first(where: { $0.id == id }) else { return }
        do {
            let target = try panel.target ?? windowManager.captureTarget()
            let geometry = GridGeometry(columns: settings.grid.columns, rows: settings.grid.rows)
            apply(rect: geometry.rect(for: preset.area, in: target.screen.visibleFrame), target: target)
        } catch { showError(error) }
    }

    func openSettings() {
        panel.cancel()
        if preferences == nil {
            preferences = PreferencesWindowController(settings: settings, onChange: { [weak self] updated in
                try self?.updateSettings(updated)
            })
        }
        NSApp.activate(ignoringOtherApps: true)
        if let sheet = preferences?.window?.attachedSheet {
            sheet.makeKeyAndOrderFront(nil)
        } else {
            preferences?.showWindow(nil)
            preferences?.window?.makeKeyAndOrderFront(nil)
        }
    }

    func openAbout() {
        panel.cancel()
        NSApp.activate(ignoringOtherApps: true)
        let repositoryURL = URL(string: "https://github.com/msoap/vindustilpasser")!
        let credits = NSMutableAttributedString(string: "Github\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 12)
        ])
        credits.append(NSAttributedString(string: repositoryURL.absoluteString, attributes: [
            .link: repositoryURL,
            .foregroundColor: NSColor.linkColor,
            .font: NSFont.systemFont(ofSize: 12)
        ]))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        credits.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    func quit() { NSApp.terminate(nil) }

    private func handleAppCommand(_ event: NSEvent) -> Bool {
        guard !panel.isVisible, NSApp.isActive,
              (preferences?.window?.isVisible == true || NSApp.keyWindow != nil),
              event.modifierFlags.contains(.command) else { return false }
        switch Int(event.keyCode) {
        case 43: openSettings(); return true
        case 13 where event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command:
            guard let window = NSApp.keyWindow else { return false }
            window.performClose(nil)
            return true
        case 12: quit(); return true
        default: return false
        }
    }

    private func updateSettings(_ updated: AppSettings) throws {
        try updated.validate()
        try hotKeys.apply(settings: updated)
        do { try settingsStore.save(updated) }
        catch {
            try? hotKeys.apply(settings: settings)
            throw error
        }
        settings = updated
        statusItem.setVisible(updated.general.showMenuBarIcon)
    }

    private func showError(_ error: Error) {
        logger.error("\(error.localizedDescription)")
        let alert = NSAlert()
        alert.messageText = "vindustilpasser"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
