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
        .library(name: "SaverCore", targets: ["SaverCore"]),
        .library(name: "SaverKit", targets: ["SaverKit"]),
        .library(name: "SolarSystemCore", targets: ["SolarSystemCore"]),
        .library(name: "SolarSystemRender", targets: ["SolarSystemRender"]),
        .library(name: "SolarSystemSaver", targets: ["SolarSystemSaver"]),
        .library(name: "ThreeBodyCore", targets: ["ThreeBodyCore"]),
        .library(name: "ThreeBodyRender", targets: ["ThreeBodyRender"]),
        .library(name: "ThreeBodySaver", targets: ["ThreeBodySaver"]),
        .library(name: "VortexCore", targets: ["VortexCore"]),
        .library(name: "VortexRender", targets: ["VortexRender"]),
        .library(name: "VortexSaver", targets: ["VortexSaver"]),
        .library(name: "GargantuaCore", targets: ["GargantuaCore"]),
        .library(name: "GargantuaRender", targets: ["GargantuaRender"]),
        .library(name: "GargantuaSaver", targets: ["GargantuaSaver"]),
        .executable(name: "SolarSystemApp", targets: ["SolarSystemApp"]),
        .executable(name: "ThreeBodyApp", targets: ["ThreeBodyApp"]),
        .executable(name: "VortexApp", targets: ["VortexApp"]),
        .executable(name: "GargantuaApp", targets: ["GargantuaApp"]),
        .executable(name: "ssverify", targets: ["ssverify"]),
    ],
    targets: [
        // The Foundation-only half of the shared code. Split out from SaverKit so
        // the physics modules can use it without linking AppKit, ScreenSaver and
        // Metal — which is what makes "Core is testable headlessly" true rather
        // than merely intended.
        .target(name: "SaverCore", swiftSettings: [.swiftLanguageMode(.v5)]),

        // Shared by every saver: the small amount that is genuinely common to
        // hosting a ScreenSaverView, rather than to drawing any particular scene.
        .target(
            name: "SaverKit", dependencies: ["SaverCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]),

        // Vendored astronomy-engine (MIT, Don Cross). See LICENSES/.
        .target(name: "CAstronomy", publicHeadersPath: "include"),
        .target(
            name: "SolarSystemCore", dependencies: ["CAstronomy"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "SolarSystemRender", dependencies: ["SolarSystemCore", "SaverKit"],
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

        .target(
            name: "ThreeBodyCore", dependencies: ["SaverCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "ThreeBodyRender", dependencies: ["ThreeBodyCore", "SaverKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "ThreeBodySaver", dependencies: ["ThreeBodyRender", "ThreeBodyCore", "SaverKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "ThreeBodyApp", dependencies: ["ThreeBodyRender", "ThreeBodyCore", "SaverKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]),

        .target(
            name: "VortexCore", dependencies: ["SaverCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "VortexRender", dependencies: ["VortexCore", "SaverKit"],
            // The .metal source is compiled to a metallib by Scripts/build-saver.sh for
            // the shipped bundle. SwiftPM only ever type-checks this target, so the file
            // is excluded here rather than being treated as an unbuildable Swift source.
            exclude: ["Vortex.metal"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "VortexSaver", dependencies: ["VortexRender", "VortexCore", "SaverKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "VortexApp", dependencies: ["VortexRender", "VortexCore", "SaverKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]),

        .target(
            name: "GargantuaCore", dependencies: ["SaverCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "GargantuaRender", dependencies: ["GargantuaCore", "SaverKit"],
            exclude: ["Gargantua.metal"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "GargantuaSaver",
            dependencies: ["GargantuaRender", "GargantuaCore", "SaverKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "GargantuaApp", dependencies: ["GargantuaRender", "GargantuaCore", "SaverKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]),

        .testTarget(
            name: "SolarSystemCoreTests",
            dependencies: ["SolarSystemCore", "SolarSystemRender"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "ThreeBodyCoreTests", dependencies: ["ThreeBodyCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "VortexTests", dependencies: ["VortexCore", "VortexRender"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "GargantuaTests", dependencies: ["GargantuaCore", "GargantuaRender"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
