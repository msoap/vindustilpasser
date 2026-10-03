import CoreGraphics

enum WindowFrameApplication {
    static func apply(
        _ requested: CGRect,
        readFrame: () throws -> CGRect,
        setSize: (CGSize) throws -> Void,
        setPosition: (CGPoint) throws -> Void
    ) throws -> CGRect {
        try setSize(requested.size)
        try setPosition(requested.origin)
        var actual = try readFrame()
        if abs(actual.width - requested.width) > 1 || abs(actual.height - requested.height) > 1 {
            try setSize(requested.size)
            actual = try readFrame()
        }
        if abs(actual.minX - requested.minX) > 1 || abs(actual.minY - requested.minY) > 1 {
            try setPosition(requested.origin)
            actual = try readFrame()
        }
        return actual
    }
}
