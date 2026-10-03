import AppKit
import ApplicationServices

final class WindowTarget {
    let pid: pid_t
    let application: NSRunningApplication
    let axWindow: AXUIElement
    let originalAXFrame: CGRect
    let screen: NSScreen

    init(application: NSRunningApplication, axWindow: AXUIElement, originalAXFrame: CGRect, screen: NSScreen) {
        self.pid = application.processIdentifier
        self.application = application
        self.axWindow = axWindow
        self.originalAXFrame = originalAXFrame
        self.screen = screen
    }
}
