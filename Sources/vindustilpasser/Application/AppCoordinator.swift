import AppKit
import ApplicationServices
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
    private weak var aboutWindow: NSWindow?
    private var commandMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var focusedWindowObserver: FocusedWindowObserver?
    private var observedApplication: NSRunningApplication?
    private let logger = Logger(subsystem: "com.local.vindustilpasser", category: "app")

    init() {
        settings = settingsStore.load()
        panel.onApply = { [weak self] selection in self?.apply(selection: selection) }
        panel.onPreset = { [weak self] id in self?.applyPreset(id: id) }
        panel.onSaveWindow = { [weak self] in self?.saveWindow() }
        panel.onRestoreWindow = { [weak self] in self?.restoreWindow() }
        panel.onSettings = { [weak self] in self?.openSettings() }
        panel.onQuit = { [weak self] in self?.quit() }
        panel.onCancel = { [weak self] in self?.stopWatchingWindow() }
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
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.processIdentifier != getpid() else { return }
            MainActor.assumeIsolated { self?.activated(application) }
        }
        logger.info("Started; Accessibility granted: \(AccessibilityPermission.granted)")
    }

    func toggleGridPanel() {
        if panel.isVisible { panel.cancel(); return }
        let target: WindowTarget?
        do { target = try windowManager.captureTarget() }
        catch {
            if (error as? WindowOperationError)?.requiresAlert == true {
                showError(error)
                return
            }
            logger.info("Opened panel without a target: \(error.localizedDescription)")
            target = nil
        }
        guard let screen = target?.screen
            ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? statusItem.screen ?? NSScreen.main else { return }
        let application = target?.application ?? tracker.current().flatMap { $0.isTerminated ? nil : $0 }
        panel.ignoredClickWindow = statusItem.window
        panel.show(target: target, application: application, screen: screen, settings: settings,
                   restoreAvailable: target.map { hasSavedFrame(for: $0) } ?? false)
        watchWindow(in: application)
    }

    private func activated(_ application: NSRunningApplication) {
        guard panel.isVisible else { return }
        if observedApplication?.processIdentifier != application.processIdentifier {
            panel.cancel()
            return
        }
        closeIfWindowChanged(in: application)
    }

    private func watchWindow(in application: NSRunningApplication?) {
        stopWatchingWindow()
        guard let application, !application.isTerminated else { return }
        observedApplication = application
        focusedWindowObserver = FocusedWindowObserver(pid: application.processIdentifier) { [weak self, pid = application.processIdentifier] in
            guard let self, self.panel.isVisible, self.observedApplication?.processIdentifier == pid,
                  let application = self.observedApplication else { return }
            self.closeIfWindowChanged(in: application)
        }
        if focusedWindowObserver == nil {
            logger.debug("Focused-window notifications unavailable for PID \(application.processIdentifier)")
        }
    }

    private func stopWatchingWindow() {
        focusedWindowObserver?.stop()
        focusedWindowObserver = nil
        observedApplication = nil
    }

    private func closeIfWindowChanged(in application: NSRunningApplication) {
        guard panel.isVisible else { return }
        let newTarget = try? windowManager.captureTarget(application: application)
        if let current = panel.target, let newTarget,
           current.pid == newTarget.pid, CFEqual(current.axWindow, newTarget.axWindow) {
            return
        }
        if panel.target == nil && newTarget == nil { return }
        panel.cancel()
    }

    private func apply(selection: GridSelection) {
        do {
            let target = try panel.target ?? windowManager.captureTarget()
            let geometry = GridGeometry(columns: settings.grid.columns, rows: settings.grid.rows)
            let rect = geometry.rect(for: selection, in: target.screen.visibleFrame)
            apply(rect: rect, target: target)
        } catch { showError(error) }
    }

    private func apply(rect: CGRect, target: WindowTarget) {
        do {
            try windowManager.apply(appKitRect: rect, to: target)
            panel.cancel()
        } catch {
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

    private func saveWindow() {
        do {
            let target = try currentPanelTarget()
            let identity = try windowManager.identity(for: target)
            let frame = ScreenGeometry.appKitRect(fromAX: try AXHelpers.frame(target.axWindow))
            guard let screen = ScreenGeometry.screen(for: frame),
                  let displayID = ScreenGeometry.displayID(for: screen),
                  let displayUUID = ScreenGeometry.displayUUID(for: displayID) else {
                throw WindowOperationError.noWindow
            }
            let resolution = (CGDisplayPixelsWide(displayID), CGDisplayPixelsHigh(displayID))
            let title = (AXHelpers.optionalAttribute(target.axWindow, kAXTitleAttribute as CFString) as? String)
                .flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled window"
            var updated = settings
            let existing = updated.savedWindows.firstIndex {
                $0.matches(identity, displayUUID: displayUUID, pixelWidth: resolution.0, pixelHeight: resolution.1)
            }
            let saved = SavedWindow(id: existing.map { updated.savedWindows[$0].id } ?? UUID(),
                                    identity: identity,
                                    applicationName: target.application.localizedName ?? identity.bundleID,
                                    windowName: title, displayName: screen.localizedName,
                                    displayUUID: displayUUID,
                                    pixelWidth: resolution.0, pixelHeight: resolution.1,
                                    x: frame.minX - screen.frame.minX, y: frame.minY - screen.frame.minY,
                                    width: frame.width, height: frame.height)
            if let existing { updated.savedWindows[existing] = saved }
            else { updated.savedWindows.append(saved) }
            try updateSettings(updated)
            preferences?.syncSavedWindows(updated.savedWindows)
            panel.setRestoreAvailable(true)
            panel.showError("Saved window position and size.")
        } catch { showError(error) }
    }

    private func hasSavedFrame(for target: WindowTarget) -> Bool {
        guard let identity = try? windowManager.identity(for: target),
              let frame = try? AXHelpers.frame(target.axWindow),
              let screen = ScreenGeometry.screen(for: ScreenGeometry.appKitRect(fromAX: frame)),
              let displayID = ScreenGeometry.displayID(for: screen),
              let displayUUID = ScreenGeometry.displayUUID(for: displayID) else { return false }
        return settings.savedWindows.contains {
            $0.matches(identity, displayUUID: displayUUID,
                       pixelWidth: CGDisplayPixelsWide(displayID), pixelHeight: CGDisplayPixelsHigh(displayID))
        }
    }

    private func restoreWindow() {
        do {
            let target = try currentPanelTarget()
            let identity = try windowManager.identity(for: target)
            let current = ScreenGeometry.appKitRect(fromAX: try AXHelpers.frame(target.axWindow))
            guard let screen = ScreenGeometry.screen(for: current),
                  let displayID = ScreenGeometry.displayID(for: screen),
                  let displayUUID = ScreenGeometry.displayUUID(for: displayID) else {
                throw WindowOperationError.noWindow
            }
            let resolution = (CGDisplayPixelsWide(displayID), CGDisplayPixelsHigh(displayID))
            guard let saved = settings.savedWindows.first(where: {
                $0.matches(identity, displayUUID: displayUUID, pixelWidth: resolution.0, pixelHeight: resolution.1)
            }) else { throw WindowOperationError.noSavedWindow }
            let frame = CGRect(x: screen.frame.minX + saved.x, y: screen.frame.minY + saved.y,
                               width: saved.width, height: saved.height)
            try windowManager.apply(appKitRect: frame, to: target)
            panel.cancel()
        } catch { showError(error) }
    }

    private func currentPanelTarget() throws -> WindowTarget {
        guard let target = panel.target else { throw WindowOperationError.noWindow }
        let current = try windowManager.captureTarget(application: target.application)
        guard current.pid == target.pid, CFEqual(current.axWindow, target.axWindow) else {
            throw WindowOperationError.targetChanged
        }
        return target
    }

    func openSettings() {
        let screen = auxiliaryWindowScreen()
        panel.cancel()
        if preferences == nil {
            preferences = PreferencesWindowController(settings: settings, onChange: { [weak self] updated in
                try self?.updateSettings(updated)
            })
        }
        preferences?.syncSavedWindows(settings.savedWindows)
        if let window = preferences?.window, let screen { place(window, on: screen) }
        if let sheet = preferences?.window?.attachedSheet {
            sheet.makeKeyAndOrderFront(nil)
        } else {
            preferences?.showWindow(nil)
            preferences?.window?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func openAbout() {
        let screen = auxiliaryWindowScreen()
        panel.cancel()
        if let aboutWindow, let screen { place(aboutWindow, on: screen) }
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
        let existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        let previousKeyWindow = NSApp.keyWindow
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        let window = aboutWindow
            ?? NSApp.windows.first(where: { !existingWindows.contains(ObjectIdentifier($0)) })
            ?? (NSApp.keyWindow !== previousKeyWindow ? NSApp.keyWindow : nil)
        if let window {
            aboutWindow = window
            if let screen { place(window, on: screen) }
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func auxiliaryWindowScreen() -> NSScreen? {
        if let screen = panel.target?.screen { return screen }
        if AccessibilityPermission.granted, let screen = try? windowManager.captureTarget().screen { return screen }
        return statusItem.screen ?? NSApp.keyWindow?.screen ?? NSScreen.main
    }

    private func place(_ window: NSWindow, on screen: NSScreen) {
        window.collectionBehavior.insert(.moveToActiveSpace)
        let visible = screen.visibleFrame
        window.setFrameOrigin(CGPoint(x: visible.midX - window.frame.width / 2,
                                    y: visible.midY - window.frame.height / 2))
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
        guard (error as? WindowOperationError)?.requiresAlert == true else {
            panel.showError(error.localizedDescription)
            return
        }
        panel.cancel()
        let alert = NSAlert()
        alert.messageText = "vindustilpasser"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
