import AppKit
import Foundation
import SolarSystemCore
import SolarSystemRender

/// Owns the window. Everything about driving the scene lives in `SolarSystemSceneView`,
/// shared with the screensaver so the two hosts cannot drift apart.
final class AppHost: NSObject, NSApplicationDelegate {
    private let renderer: SolarSystemRenderer
    private let options: LaunchOptions
    /// NSWindow releases itself when closed by default; hold it so it outlives launch.
    private var window: NSWindow?

    init(renderer: SolarSystemRenderer, options: LaunchOptions) {
        self.renderer = renderer
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rect = NSRect(x: 0, y: 0, width: options.width, height: options.height)
        let window = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Solar System — galactic drift"
        window.center()
        window.contentView = SolarSystemSceneView(
            renderer: renderer,
            frame: rect,
            quality: .full,
            allowsCameraControl: options.allowsCameraControl
        )
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
