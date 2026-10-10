import ApplicationServices

enum WindowOperationError: LocalizedError {
    case accessibilityDenied, applicationUnavailable, noWindow, targetGone, minimized, nativeFullScreen
    case positionNotSettable, sizeNotSettable
    case axError(AXError)

    var requiresAlert: Bool {
        switch self {
        case .accessibilityDenied, .axError: true
        default: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied: "Grant Accessibility access in System Settings, then try again."
        case .applicationUnavailable: "The target application is no longer running."
        case .noWindow: "No usable window was found in the target application."
        case .targetGone: "The target window is no longer available."
        case .minimized: "The target window is minimized."
        case .nativeFullScreen: "Leave native fullscreen before resizing this window."
        case .positionNotSettable: "This window cannot be moved."
        case .sizeNotSettable: "This window cannot be resized."
        case .axError(let error): "Accessibility error \(error.rawValue)."
        }
    }
}

enum AXHelpers {
    static func attribute(_ element: AXUIElement, _ name: CFString) throws -> CFTypeRef {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name, &value)
        guard result == .success else { throw WindowOperationError.axError(result) }
        guard let value else { throw WindowOperationError.targetGone }
        return value
    }

    static func optionalAttribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
        try? attribute(element, name)
    }

    static func window(_ element: AXUIElement, _ name: CFString) -> AXUIElement? {
        guard let value = optionalAttribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func bool(_ element: AXUIElement, _ name: CFString) -> Bool {
        (optionalAttribute(element, name) as? Bool) ?? false
    }

    static func point(_ element: AXUIElement) throws -> CGPoint {
        let value = try attribute(element, kAXPositionAttribute as CFString)
        guard CFGetTypeID(value) == AXValueGetTypeID() else { throw WindowOperationError.targetGone }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { throw WindowOperationError.targetGone }
        return point
    }

    static func size(_ element: AXUIElement) throws -> CGSize {
        let value = try attribute(element, kAXSizeAttribute as CFString)
        guard CFGetTypeID(value) == AXValueGetTypeID() else { throw WindowOperationError.targetGone }
        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { throw WindowOperationError.targetGone }
        return size
    }

    static func frame(_ element: AXUIElement) throws -> CGRect {
        CGRect(origin: try point(element), size: try size(element))
    }

    static func settable(_ element: AXUIElement, _ name: CFString) throws -> Bool {
        var result = DarwinBoolean(false)
        let error = AXUIElementIsAttributeSettable(element, name, &result)
        guard error == .success else { throw WindowOperationError.axError(error) }
        return result.boolValue
    }

    static func setSize(_ size: CGSize, on element: AXUIElement) throws {
        var value = size
        guard let axValue = AXValueCreate(.cgSize, &value) else { throw WindowOperationError.targetGone }
        let result = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, axValue)
        guard result == .success else { throw WindowOperationError.axError(result) }
    }

    static func setPosition(_ position: CGPoint, on element: AXUIElement) throws {
        var value = position
        guard let axValue = AXValueCreate(.cgPoint, &value) else { throw WindowOperationError.targetGone }
        let result = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axValue)
        guard result == .success else { throw WindowOperationError.axError(result) }
    }
}
