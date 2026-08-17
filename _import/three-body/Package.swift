// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ThreeBodyProblem",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ThreeBodyCore", targets: ["ThreeBodyCore"]),
        .library(name: "ThreeBodyRender", targets: ["ThreeBodyRender"]),
        .library(name: "ThreeBodySaver", targets: ["ThreeBodySaver"]),
        .executable(name: "ThreeBodyApp", targets: ["ThreeBodyApp"]),
    ],
    targets: [
        // Gravity, integrators, scenarios, framing and the scene lifecycle.
        // Imports nothing but Foundation, which is what lets the physics be
        // measured headlessly — and is enforced by the module boundary rather
        // than by good intentions.
        .target(
            name: "ThreeBodyCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Core Graphics drawing, settings persistence and the options sheet.
        // Shared by the app and the .saver bundle, so the screensaver and the
        // iteration target can never drift apart.
        .target(
            name: "ThreeBodyRender",
            dependencies: ["ThreeBodyCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // ScreenSaverView subclass. Built as a library here so `swift build`
        // type-checks it; Scripts/build-saver.sh links it into an actual
        // loadable .saver bundle, which SwiftPM cannot emit.
        .target(
            name: "ThreeBodySaver",
            dependencies: ["ThreeBodyRender", "ThreeBodyCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Plain window running the same engine: the fast iteration target, and
        // the only way to watch a scene without locking the screen.
        .executableTarget(
            name: "ThreeBodyApp",
            dependencies: ["ThreeBodyRender", "ThreeBodyCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ThreeBodyCoreTests",
            dependencies: ["ThreeBodyCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
