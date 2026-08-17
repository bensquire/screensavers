// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SolarSystem",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SolarSystemCore", targets: ["SolarSystemCore"]),
        .library(name: "SolarSystemRender", targets: ["SolarSystemRender"]),
        .library(name: "SolarSystemSaver", targets: ["SolarSystemSaver"]),
        .executable(name: "ssverify", targets: ["ssverify"]),
        .executable(name: "SolarSystemApp", targets: ["SolarSystemApp"]),
    ],
    targets: [
        // Vendored astronomy-engine (MIT, Don Cross). See LICENSES/.
        .target(
            name: "CAstronomy",
            publicHeadersPath: "include"
        ),
        // Ephemeris + frame transforms + the display model. No rendering here,
        // so it stays testable and reusable by the app and the .saver bundle.
        .target(
            name: "SolarSystemCore",
            dependencies: ["CAstronomy"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // SceneKit geometry + scene graph. Shared by the app and the .saver bundle,
        // so the screensaver and the iteration target can never drift apart.
        .target(
            name: "SolarSystemRender",
            dependencies: ["SolarSystemCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // ScreenSaverView subclass. Built as a library here so `swift build` type-checks
        // it; Scripts/build-saver.sh links it into an actual loadable .saver bundle.
        .target(
            name: "SolarSystemSaver",
            dependencies: ["SolarSystemRender", "SolarSystemCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Prints positions in a form you can diff against JPL Horizons.
        .executableTarget(
            name: "ssverify",
            dependencies: ["SolarSystemCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // SceneKit app: fast iteration target before wrapping as a .saver.
        .executableTarget(
            name: "SolarSystemApp",
            dependencies: ["SolarSystemRender", "SolarSystemCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SolarSystemCoreTests",
            dependencies: ["SolarSystemCore", "SolarSystemRender"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
