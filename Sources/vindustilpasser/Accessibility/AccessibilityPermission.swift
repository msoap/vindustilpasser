import ApplicationServices

enum AccessibilityPermission {
    static var granted: Bool { AXIsProcessTrusted() }

    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func require() throws {
        guard granted else {
            request()
            throw WindowOperationError.accessibilityDenied
        }
    }
}
