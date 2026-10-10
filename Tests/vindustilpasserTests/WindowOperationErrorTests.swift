import ApplicationServices
import Testing

struct WindowOperationErrorTests {
    @Test func onlyAccessibilityErrorsRequireAlerts() {
        #expect(WindowOperationError.accessibilityDenied.requiresAlert)
        #expect(WindowOperationError.axError(.cannotComplete).requiresAlert)
        #expect(!WindowOperationError.noWindow.requiresAlert)
        #expect(!WindowOperationError.targetGone.requiresAlert)
        #expect(!WindowOperationError.sizeNotSettable.requiresAlert)
    }
}
