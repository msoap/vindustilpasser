// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vindustilpasser",
    platforms: [.macOS(.v11)],
    products: [.executable(name: "vindustilpasser", targets: ["vindustilpasser"])],
    targets: [.executableTarget(name: "vindustilpasser")],
    swiftLanguageModes: [.v5]
)
