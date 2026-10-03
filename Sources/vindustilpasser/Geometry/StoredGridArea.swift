import Foundation

struct StoredGridArea: Codable, Equatable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
    var columns: Int
    var rows: Int

    var isValid: Bool {
        columns > 0 && rows > 0 && x >= 0 && y >= 0 && x < columns && y < rows
            && width > 0 && height > 0 && width <= columns - x && height <= rows - y
    }
}
