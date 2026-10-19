import CoreGraphics
import Foundation

struct WindowInventory {
    private(set) var windowIDsByPID: [pid_t: Set<CGWindowID>] = [:]

    init(windowInfo: [[String: Any]], screenFrames: [CGRect], screenIndex: Int, primaryIndex: Int) {
        guard screenFrames.indices.contains(screenIndex), screenFrames.indices.contains(primaryIndex) else { return }
        for info in windowInfo {
            guard let id = info[kCGWindowNumber as String] as? CGWindowID, id != kCGNullWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid > 0,
                  info[kCGWindowIsOnscreen as String] as? Bool == true,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let axFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  [axFrame.minX, axFrame.minY, axFrame.width, axFrame.height].allSatisfy(\.isFinite),
                  axFrame.width > 0, axFrame.height > 0 else { continue }
            let frame = ScreenGeometry.appKitRect(fromAX: axFrame, primaryFrame: screenFrames[primaryIndex])
            guard frame.intersects(screenFrames[screenIndex]),
                  ScreenGeometry.screenIndex(for: frame, in: screenFrames, primaryIndex: primaryIndex) == screenIndex else {
                continue
            }
            windowIDsByPID[pid, default: []].insert(id)
        }
    }

    func contains(_ windowID: CGWindowID, pid: pid_t) -> Bool {
        windowIDsByPID[pid]?.contains(windowID) == true
    }
}
