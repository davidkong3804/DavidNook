// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DavidNookCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DavidNookCore", targets: ["DavidNookCore"]),
    ],
    dependencies: [
        // MIT；內含 OpenCC 1.1.2 字典（Apache-2.0）。上游最後更新 2021，故以 revision 釘選。
        .package(url: "https://github.com/ddddxxx/SwiftyOpenCC.git", revision: "1d8105a0f7199c90af722bff62728050c858e777"),
    ],
    targets: [
        .target(
            name: "DavidNookCore",
            dependencies: [.product(name: "OpenCC", package: "SwiftyOpenCC")]
        ),
        .testTarget(
            name: "DavidNookCoreTests",
            dependencies: ["DavidNookCore"]
        ),
    ]
)
