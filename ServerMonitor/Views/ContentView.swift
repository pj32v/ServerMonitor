import SwiftUI
import AppKit

// MARK: - AppKit Window Hook for Persistent Frame & Autosaving
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onWindow(window)
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var viewModel: MonitorViewModel

    var body: some View {
        Group {
            if viewModel.isConnected {
                DashboardView()
                    .frame(minWidth: 1060, minHeight: 720)
            } else {
                ConnectionView()
                    .frame(minWidth: 460, maxWidth: 520, minHeight: 580, maxHeight: 620)
            }
        }
        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: viewModel.isConnected)
        .background(
            WindowAccessor { window in
                window.setFrameAutosaveName("ServerMonitorMainWindow")
                if viewModel.isConnected {
                    if window.frame.width < 1200 || window.frame.height < 800 {
                        var f = window.frame
                        if f.width < 1200 { f.size.width = 1220 }
                        if f.height < 800 { f.size.height = 820 }
                        window.setFrame(f, display: true, animate: false)
                    }
                }
            }
        )
    }
}
