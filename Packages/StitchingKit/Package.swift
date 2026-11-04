// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StitchingKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StitchingEngines", targets: ["StitchingEngines"]),
        .executable(name: "stitch-benchmark", targets: ["StitchBenchmark"])
    ],
    targets: [
        .target(name: "StitchingCore"),
        .target(name: "EkibunStitch", dependencies: ["StitchingCore"]),
        .target(name: "LongStitch", dependencies: ["StitchingCore"]),
        .target(name: "ZoomItStitch", dependencies: ["StitchingCore"]),
        .target(name: "SeamlyStitch", dependencies: ["StitchingCore"]),
        .target(name: "StitchingEngines", dependencies: ["StitchingCore", "EkibunStitch", "LongStitch", "ZoomItStitch", "SeamlyStitch"]),
        .executableTarget(name: "StitchBenchmark", dependencies: ["StitchingEngines"]),
        .testTarget(name: "StitchingCoreTests", dependencies: ["StitchingCore", "StitchingEngines"])
    ]
)
