// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TruthLensCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TruthLensCore", targets: ["TruthLensCore"])],
    targets: [
        .target(name: "TruthLensCore"),
        .testTarget(name: "TruthLensCoreTests", dependencies: ["TruthLensCore"]),
    ]
)
