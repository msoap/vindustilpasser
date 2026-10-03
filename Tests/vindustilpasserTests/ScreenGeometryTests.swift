import Testing
import CoreGraphics

struct ScreenGeometryTests {
    @Test func primaryAndSatelliteRoundTrips() {
        let primary = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let windows = [
            CGRect(x: 30, y: 40, width: 700, height: 500),
            CGRect(x: -1000, y: 150, width: 800, height: 600),
            CGRect(x: 2100, y: -200, width: 950, height: 700),
            CGRect(x: 100, y: 1200, width: 600, height: 500),
            CGRect(x: -250, y: -900, width: 650, height: 400)
        ]
        for window in windows {
            let ax = ScreenGeometry.axRect(fromAppKit: window, primaryFrame: primary)
            #expect(ScreenGeometry.appKitRect(fromAX: ax, primaryFrame: primary) == window)
        }
    }

    @Test func largestOverlapAndFallback() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800),
                       CGRect(x: -1200, y: 0, width: 1200, height: 800),
                       CGRect(x: 0, y: 800, width: 1000, height: 700)]
        #expect(ScreenGeometry.screenIndex(for: CGRect(x: -300, y: 100, width: 500, height: 500), in: screens, primaryIndex: 0) == 1)
        #expect(ScreenGeometry.screenIndex(for: CGRect(x: 100, y: 900, width: 500, height: 300), in: screens, primaryIndex: 0) == 2)
        #expect(ScreenGeometry.screenIndex(for: CGRect(x: 5000, y: 5000, width: 100, height: 100), in: screens, primaryIndex: 0) == 0)
    }
}
