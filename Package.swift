// swift-tools-version:6.0
import PackageDescription

// One package, several screensavers. SwiftPM is here for `swift test`, `swift format`
// and type-checking; the loadable .saver bundles are built by Scripts/build-saver.sh,
// which SwiftPM cannot produce.
//
// Each saver keeps its own Core/Render/Saver split, so the module boundary enforces
// that its physics stays free of AppKit and remains testable headlessly.
let package = Package(
    name: "Screensavers",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SaverKit", targets: ["SaverKit"]),
        .library(name: "SolarSystemCore", targets: ["SolarSystemCore"]),
        .library(name: "SolarSystemRender", targets: ["SolarSystemRender"]),
        .library(name: "SolarSystemSaver", targets: ["SolarSystemSaver"]),
        .library(name: "ThreeBodyCore", targets: ["ThreeBodyCore"]),
        .library(name: "ThreeBodyRender", targets: ["ThreeBodyRender"]),
        .library(name: "ThreeBodySaver", targets: ["ThreeBodySaver"]),
        .executable(name: "SolarSystemApp", targets: ["SolarSystemApp"]),
        .executable(name: "ThreeBodyApp", targets: ["ThreeBodyApp"]),
        .executable(name: "ssverify", targets: ["ssverify"]),
    ],
    targets: [
        // Shared by every saver: the small amount that is genuinely common to
        // hosting a ScreenSaverView, rather than to drawing any particular scene.
        .target(name: "SaverKit", swiftSettings: [.swiftLanguageMode(.v5)]),

        // Vendored astronomy-engine (MIT, Don Cross). See LICENSES/.
        .target(name: "CAstronomy", publicHeadersPath: "include"),
        .target(
            name: "SolarSystemCore", dependencies: ["CAstronomy"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "SolarSystemRender", dependencies: ["SolarSystemCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "SolarSystemSaver",
            dependencies: ["SolarSystemRender", "SolarSystemCore", "SaverKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "ssverify", dependencies: ["SolarSystemCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "SolarSystemApp", dependencies: ["SolarSystemRender", "SolarSystemCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]),

        .target(name: "ThreeBodyCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "ThreeBodyRender", dependencies: ["ThreeBodyCore", "SaverKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "ThreeBodySaver", dependencies: ["ThreeBodyRender", "ThreeBodyCore", "SaverKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "ThreeBodyApp", dependencies: ["ThreeBodyRender", "ThreeBodyCore", "SaverKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]),

        .testTarget(
            name: "SolarSystemCoreTests",
            dependencies: ["SolarSystemCore", "SolarSystemRender"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "ThreeBodyCoreTests", dependencies: ["ThreeBodyCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
