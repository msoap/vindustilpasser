// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vindustilpasser",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "vindustilpasser", targets: ["vindustilpasser"])],
    targets: [.executableTarget(name: "vindustilpasser")],
    swiftLanguageModes: [.v5]
)
