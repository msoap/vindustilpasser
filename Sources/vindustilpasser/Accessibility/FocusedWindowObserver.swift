import ApplicationServices

@MainActor
final class FocusedWindowObserver {
    private let application: AXUIElement
    private let observer: AXObserver
    private var notifications: [CFString] = []
    private let onChange: () -> Void

    init?(pid: pid_t, onChange: @escaping () -> Void) {
        var created: AXObserver?
        let result = AXObserverCreate(pid, { _, _, _, refcon in
            guard let refcon else { return }
            let owner = Unmanaged<FocusedWindowObserver>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { owner.onChange() }
        }, &created)
        guard result == .success, let created else { return nil }

        application = AXUIElementCreateApplication(pid)
        observer = created
        self.onChange = onChange

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        notifications = [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification]
            .map { $0 as CFString }
            .filter { AXObserverAddNotification(created, application, $0, refcon) == .success }
        guard !notifications.isEmpty else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    }

    func stop() {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        for notification in notifications {
            AXObserverRemoveNotification(observer, application, notification)
        }
    }
}
