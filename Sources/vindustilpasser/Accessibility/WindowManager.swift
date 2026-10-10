import AppKit
import ApplicationServices
import os

@MainActor
final class WindowManager {
    private let tracker: ExternalApplicationTracker
    private let logger = Logger(subsystem: "com.local.vindustilpasser", category: "window")

    init(tracker: ExternalApplicationTracker) { self.tracker = tracker }

    func identity(for target: WindowTarget) throws -> SavedWindow.Identity {
        guard let bundleID = target.application.bundleIdentifier, !bundleID.isEmpty else {
            throw WindowOperationError.unidentifiedWindow
        }
        guard let identity = windowIdentity(target.axWindow, bundleID: bundleID) else {
            throw WindowOperationError.unidentifiedWindow
        }
        let appElement = AXUIElementCreateApplication(target.pid)
        guard let windows = AXHelpers.optionalAttribute(appElement, kAXWindowsAttribute as CFString) as? [AXUIElement] else {
            throw WindowOperationError.unidentifiedWindow
        }
        let duplicates = windows.filter { window in
            windowIdentity(window, bundleID: bundleID) == identity
        }
        guard duplicates.count == 1, CFEqual(duplicates[0], target.axWindow) else {
            throw WindowOperationError.ambiguousWindow
        }
        return identity
    }

    private func windowIdentity(_ window: AXUIElement, bundleID: String) -> SavedWindow.Identity? {
        if let document = AXHelpers.optionalAttribute(window, kAXDocumentAttribute as CFString) as? String,
           !document.isEmpty {
            return SavedWindow.Identity(bundleID: bundleID, kind: .document, value: document)
        }
        if let identifier = AXHelpers.optionalAttribute(window, kAXIdentifierAttribute as CFString) as? String,
           !identifier.isEmpty {
            return SavedWindow.Identity(bundleID: bundleID, kind: .accessibilityIdentifier, value: identifier)
        }
        return nil
    }

    func captureTarget(application requestedApplication: NSRunningApplication? = nil) throws -> WindowTarget {
        try AccessibilityPermission.require()
        guard let application = requestedApplication ?? tracker.current(), !application.isTerminated,
              application.processIdentifier != getpid() else { throw WindowOperationError.applicationUnavailable }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let window = AXHelpers.window(appElement, kAXFocusedWindowAttribute as CFString)
                ?? AXHelpers.window(appElement, kAXMainWindowAttribute as CFString) else { throw WindowOperationError.noWindow }
        guard (AXHelpers.optionalAttribute(window, kAXRoleAttribute as CFString) as? String) == (kAXWindowRole as String) else {
            throw WindowOperationError.noWindow
        }
        let frame = try AXHelpers.frame(window)
        guard let screen = ScreenGeometry.screen(for: ScreenGeometry.appKitRect(fromAX: frame)) else {
            throw WindowOperationError.noWindow
        }
        logger.debug("Captured window for PID \(application.processIdentifier)")
        return WindowTarget(application: application, axWindow: window, originalAXFrame: frame, screen: screen)
    }

    @discardableResult
    func apply(appKitRect: CGRect, to target: WindowTarget) throws -> CGRect {
        try AccessibilityPermission.require()
        guard !target.application.isTerminated, target.pid != getpid() else { throw WindowOperationError.applicationUnavailable }
        let window = target.axWindow
        _ = try AXHelpers.frame(window)
        if AXHelpers.bool(window, "AXFullScreen" as CFString) { throw WindowOperationError.nativeFullScreen }
        if AXHelpers.bool(window, kAXMinimizedAttribute as CFString) { throw WindowOperationError.minimized }
        guard try AXHelpers.settable(window, kAXPositionAttribute as CFString) else { throw WindowOperationError.positionNotSettable }
        guard try AXHelpers.settable(window, kAXSizeAttribute as CFString) else { throw WindowOperationError.sizeNotSettable }
        let requested = ScreenGeometry.axRect(fromAppKit: appKitRect)
        let actual = try WindowFrameApplication.apply(requested, readFrame: { try AXHelpers.frame(window) },
                                                       setSize: { try AXHelpers.setSize($0, on: window) },
                                                       setPosition: { try AXHelpers.setPosition($0, on: window) })
        logger.debug("Requested \(String(describing: requested)), actual \(String(describing: actual))")
        return ScreenGeometry.appKitRect(fromAX: actual)
    }
}
