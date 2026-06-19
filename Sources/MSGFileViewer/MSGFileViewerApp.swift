// MSGFileViewer - Native macOS application for viewing .msg files
// SwiftUI App lifecycle entry point

import SwiftUI
import AppKit
import MSGParser

@main
struct MSGFileViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
        }
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

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("MSG File Viewer")
                .font(.title)
            Text("Drop a .msg file here or use File > Open")
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 600, minHeight: 400)
        .msgFileDrop(isTargeted: $isDropTargeted) { url in
            WindowManager.shared.openFile(url: url)
        }
    }
}
