import Foundation

struct GridSelection: Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    func sizeLabel(fine: Bool) -> String {
        func cells(_ count: Int) -> String {
            if fine { return String(count) }
            return count.isMultiple(of: 2) ? String(count / 2) : "\(count / 2).5"
        }
        return "\(cells(width))×\(cells(height))"
    }
}
