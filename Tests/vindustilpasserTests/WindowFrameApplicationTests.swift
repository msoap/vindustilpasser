import CoreGraphics
import Testing

struct WindowFrameApplicationTests {
    @Test func retriesSizeAfterMovingFromRightEdge() throws {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        var current = CGRect(x: 500, y: 0, width: 500, height: 800)
        var sizeWrites = 0
        let actual = try WindowFrameApplication.apply(screen, readFrame: { current }, setSize: { size in
            sizeWrites += 1
            current.size = CGSize(width: min(size.width, screen.maxX - current.minX), height: size.height)
        }, setPosition: { position in
            current.origin = position
        })
        #expect(actual == screen)
        #expect(sizeWrites == 2)
    }

    @Test func reappliesPositionAfterResizeMovesWindow() throws {
        let requested = CGRect(x: 500, y: 0, width: 500, height: 800)
        var current = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let actual = try WindowFrameApplication.apply(requested, readFrame: { current }, setSize: { size in
            current.size = size
            current.origin.x = 0
        }, setPosition: { position in
            current.origin = position
        })
        #expect(actual == requested)
    }
}
