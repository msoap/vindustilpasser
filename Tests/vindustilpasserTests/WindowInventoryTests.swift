import CoreGraphics
import Foundation
import Testing

struct WindowInventoryTests {
    private let primary = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test func matchesWindowIDsRatherThanIdenticalGeometryOrJustTheirApplication() {
        let info = window(id: 10, frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        let inventory = WindowInventory(windowInfo: [info], screenFrames: [primary], screenIndex: 0, primaryIndex: 0)
        #expect(inventory.contains(10, pid: 100))
        // Another window from the same app on a different Space must not be included.
        #expect(!inventory.contains(11, pid: 100))
        #expect(!inventory.contains(10, pid: 200))
    }

    @Test func excludesHiddenMinimizedTransparentAndOffscreenEntries() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        let info = [window(id: 10, frame: frame), window(id: 11, frame: frame, onScreen: false),
                    window(id: 12, frame: frame, alpha: 0),
                    window(id: 13, frame: CGRect(x: 2000, y: 2000, width: 400, height: 300))]
        let inventory = WindowInventory(windowInfo: info, screenFrames: [primary], screenIndex: 0, primaryIndex: 0)
        #expect(inventory.windowIDsByPID == [100: [10]])
    }

    @Test func usesLargestOverlapForLeftAndStackedMonitors() {
        let screens = [primary, CGRect(x: -1000, y: 0, width: 1000, height: 800),
                       CGRect(x: 0, y: 800, width: 1000, height: 600)]
        let info = [window(id: 10, frame: CGRect(x: 100, y: 100, width: 400, height: 300)),
                    window(id: 11, frame: CGRect(x: -800, y: 100, width: 400, height: 300)),
                    window(id: 12, frame: CGRect(x: 100, y: 900, width: 400, height: 300)),
                    window(id: 13, frame: CGRect(x: -300, y: 100, width: 500, height: 300)),
                    window(id: 14, frame: CGRect(x: 100, y: 600, width: 400, height: 500))]
        #expect(WindowInventory(windowInfo: info, screenFrames: screens, screenIndex: 0, primaryIndex: 0)
            .windowIDsByPID == [100: [10]])
        #expect(WindowInventory(windowInfo: info, screenFrames: screens, screenIndex: 1, primaryIndex: 0)
            .windowIDsByPID == [100: [11, 13]])
        #expect(WindowInventory(windowInfo: info, screenFrames: screens, screenIndex: 2, primaryIndex: 0)
            .windowIDsByPID == [100: [12, 14]])
    }

    @Test func primaryCoordinateOriginDoesNotDependOnScreenOrdering() {
        let screens = [CGRect(x: 0, y: 800, width: 1000, height: 600), primary]
        let info = [window(id: 10, frame: CGRect(x: 100, y: 100, width: 400, height: 300))]
        #expect(WindowInventory(windowInfo: info, screenFrames: screens, screenIndex: 1, primaryIndex: 1)
            .contains(10, pid: 100))
        #expect(WindowInventory(windowInfo: info, screenFrames: screens, screenIndex: 0, primaryIndex: 1)
            .windowIDsByPID.isEmpty)
    }

    @Test func rejectsMalformedEntriesAndMissingDisplays() {
        var missingID = window(id: 10, frame: CGRect(x: 100, y: 100, width: 400, height: 300))
        missingID.removeValue(forKey: kCGWindowNumber as String)
        let info = [missingID, window(id: 0, frame: primary), window(id: 10, frame: .zero),
                    window(id: 11, frame: CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100))]
        #expect(WindowInventory(windowInfo: info, screenFrames: [primary], screenIndex: 0, primaryIndex: 0)
            .windowIDsByPID.isEmpty)
        #expect(WindowInventory(windowInfo: info, screenFrames: [], screenIndex: 0, primaryIndex: 0)
            .windowIDsByPID.isEmpty)
    }

    private func window(id: CGWindowID, frame: CGRect, onScreen: Bool = true, alpha: Double = 1) -> [String: Any] {
        [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid_t(100),
         kCGWindowIsOnscreen as String: onScreen, kCGWindowAlpha as String: alpha,
         kCGWindowBounds as String: ScreenGeometry.axRect(fromAppKit: frame, primaryFrame: primary).dictionaryRepresentation]
    }
}
