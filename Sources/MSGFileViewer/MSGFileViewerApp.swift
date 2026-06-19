// MSGFileViewer - Native macOS application for viewing .msg files
// SwiftUI App lifecycle entry point

import SwiftUI
import AppKit
import MSGParser

@main
struct MSGFileViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showingAbout = false

    var body: some Scene {
        WindowGroup {
            WelcomeView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    WindowManager.shared.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {
                Button("About MSG File Viewer") {
                    showAboutPanel()
                }
            }
        }
    }
    
    private func showAboutPanel() {
        let aboutView = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: aboutView)
        window.title = "About MSG File Viewer"
        window.setContentSize(NSSize(width: 360, height: 320))
        window.styleMask = [.titled, .closable]
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

/// Application delegate handling file open events from Finder and dock.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        WindowManager.shared.handleOpenURLs(urls)
    }
}

/// Welcome view shown in the initial window with drag-and-drop support.
/// When a .msg file is dropped or opened, it routes through WindowManager
/// which creates a dedicated window with EmailView + EmailViewModel for that file.
struct WelcomeView: View {
    @State private var isDropTargeted = false
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundColor(isDropTargeted ? .accentColor : .secondary.opacity(0.4))
                    .frame(width: 280, height: 180)
                    .animation(.easeInOut(duration: 0.2), value: isDropTargeted)
                
                VStack(spacing: 12) {
                    if #available(macOS 14.0, *) {
                        Image(systemName: "envelope.badge.shield.half.filled")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                            .symbolEffect(.pulse, options: .repeating, value: isDropTargeted)
                    } else {
                        Image(systemName: "envelope.badge.shield.half.filled")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                    }
                    
                    Text("Drop .msg file here")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("or use File → Open (⌘O)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(spacing: 4) {
                Text("MSG File Viewer")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Read Outlook .msg files natively on macOS")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .frame(minWidth: 500, minHeight: 380)
        .background(.ultraThinMaterial)
        .msgFileDrop(isTargeted: $isDropTargeted) { url in
            WindowManager.shared.openFile(url: url)
        }
    }
}
