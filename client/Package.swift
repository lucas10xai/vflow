// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VFlow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VFlow", targets: ["VFlow"]),
    ],
    targets: [
        // Toàn bộ logic thuần (không AppKit), test được.
        .target(name: "VFlowCore"),
        // Lớp AppKit/SwiftUI mỏng: phím nóng, micro, dán, thanh trạng thái, menu.
        .executableTarget(name: "VFlow", dependencies: ["VFlowCore"]),
        .testTarget(name: "VFlowCoreTests", dependencies: ["VFlowCore"]),
        .testTarget(name: "VFlowTests", dependencies: ["VFlow", "VFlowCore"]),
    ],
    swiftLanguageModes: [.v6]
)
