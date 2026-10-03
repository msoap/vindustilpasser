import AppKit

@MainActor
final class ExternalApplicationTracker {
    private(set) var lastExternalPID: pid_t?
    private var observer: NSObjectProtocol?

    init() {
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() {
            lastExternalPID = app.processIdentifier
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != getpid() else { return }
            MainActor.assumeIsolated { self?.lastExternalPID = app.processIdentifier }
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func current() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() { return front }
        guard let pid = lastExternalPID else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }
}
