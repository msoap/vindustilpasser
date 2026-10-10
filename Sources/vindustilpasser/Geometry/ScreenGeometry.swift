import AppKit
import ColorSync

enum ScreenGeometry {
    static func primaryScreen(in screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        screens.first { displayID(for: $0) == CGMainDisplayID() } ?? screens.first
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func displayUUID(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID) else { return nil }
        return CFUUIDCreateString(nil, uuid.takeRetainedValue()) as String
    }

    static func appKitRect(fromAX rect: CGRect, primaryFrame: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    static func axRect(fromAppKit rect: CGRect, primaryFrame: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryFrame.maxY - rect.maxY, width: rect.width, height: rect.height)
    }

    static func appKitRect(fromAX rect: CGRect) -> CGRect {
        appKitRect(fromAX: rect, primaryFrame: primaryScreen()?.frame ?? .zero)
    }

    static func axRect(fromAppKit rect: CGRect) -> CGRect {
        axRect(fromAppKit: rect, primaryFrame: primaryScreen()?.frame ?? .zero)
    }

    static func screen(for appKitRect: CGRect, in screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        let frames = screens.map(\.frame)
        let primaryIndex = primaryScreen(in: screens).flatMap { primary in screens.firstIndex(of: primary) } ?? 0
        guard let index = screenIndex(for: appKitRect, in: frames, primaryIndex: primaryIndex) else { return nil }
        return screens[index]
    }

    static func screenIndex(for window: CGRect, in frames: [CGRect], primaryIndex: Int) -> Int? {
        guard !frames.isEmpty else { return nil }
        let areas = frames.map { $0.intersection(window).area }
        if let index = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[index] > 0 { return index }
        let center = CGPoint(x: window.midX, y: window.midY)
        return frames.firstIndex(where: { $0.contains(center) }) ?? (frames.indices.contains(primaryIndex) ? primaryIndex : 0)
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : max(0, width) * max(0, height) }
}
