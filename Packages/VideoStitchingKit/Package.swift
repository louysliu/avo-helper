// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VideoStitchingKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VideoStitchingCore", targets: ["VideoStitchingCore"]),
        .library(name: "LongScreenVideo", targets: ["LongScreenVideo"]),
        .library(name: "HyprLongshotVideo", targets: ["HyprLongshotVideo"])
    ],
    dependencies: [.package(url: "https://github.com/yeatse/opencv-spm.git", exact: "4.13.0")],
    targets: [
        .target(name: "VideoStitchingCore"),
        .binaryTarget(name: "LongScreenBridge", path: "../LongScreenBridge/LongScreenBridge.xcframework"),
        .target(name: "LongScreenVideo", dependencies: ["VideoStitchingCore", "LongScreenBridge"]),
        .testTarget(name: "LongScreenVideoTests", dependencies: ["LongScreenVideo", "VideoStitchingCore"]),
        .target(name: "HyprPhaseCorrelation", dependencies: [.product(name: "OpenCV", package: "opencv-spm")], publicHeadersPath: "include"),
        .target(name: "HyprLongshotVideo", dependencies: ["VideoStitchingCore", "HyprPhaseCorrelation"]),
        .testTarget(name: "HyprLongshotVideoTests", dependencies: ["HyprLongshotVideo", "VideoStitchingCore"]),
        .testTarget(name: "VideoStitchingCoreTests", dependencies: ["VideoStitchingCore"])
    ],
    cxxLanguageStandard: .cxx17
)
