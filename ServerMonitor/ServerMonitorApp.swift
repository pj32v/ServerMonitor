import SwiftUI
import AppKit

@main
struct ServerMonitorApp: App {
    @StateObject private var viewModel = MonitorViewModel()

    init() {
        // Set dynamic Dock icon on launch to bypass LaunchServices cache
        if let icon = NSImage(named: "AppIcon") {
            NSApplication.shared.applicationIconImage = icon
        } else if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
                  let icon = NSImage(contentsOfFile: path) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        Window("ServerMonitor", id: "mainWindow") {
            ContentView()
                .environmentObject(viewModel)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1220, height: 820)

        MenuBarExtra {
            MenuBarPopupView()
                .environmentObject(viewModel)
        } label: {
            MenuBarStatusLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
