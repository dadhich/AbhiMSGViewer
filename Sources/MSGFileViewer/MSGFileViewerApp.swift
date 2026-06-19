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
        ZStack {
            // Subtle gradient background
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.95),
                    Color.accentColor.opacity(0.03)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // App branding
                VStack(spacing: 8) {
                    Text("MSG File Viewer")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Read Outlook .msg files natively on macOS")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                }

                // Drop zone
                dropZoneView
                    .padding(.horizontal, 40)

                // Feature hints
                VStack(spacing: 6) {
                    featureHint(icon: "doc.richtext", text: "HTML, Plain Text & RTF body rendering")
                    featureHint(icon: "paperclip", text: "Extract and save attachments")
                    featureHint(icon: "person.2", text: "Full recipient and metadata display")
                }
                .padding(.top, 4)

                Spacer()
            }
            .padding(.vertical, 24)
        }
        .frame(minWidth: 520, minHeight: 440)
        .msgFileDrop(isTargeted: $isDropTargeted) { url in
            WindowManager.shared.openFile(url: url)
        }
    }

    // MARK: - Drop Zone

    private var dropZoneView: some View {
        VStack(spacing: 16) {
            // Icon with gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.15), Color.accentColor.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                if #available(macOS 14.0, *) {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.accentColor, .accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .symbolEffect(.pulse, options: .repeating, value: isDropTargeted)
                } else {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.accentColor, .accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }

            VStack(spacing: 6) {
                Text("Drop .msg file here")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)

                Text("or use File → Open (⌘O)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isDropTargeted ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isDropTargeted ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.15),
                    lineWidth: isDropTargeted ? 2 : 1
                )
        )
        .scaleEffect(isDropTargeted ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDropTargeted)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }

    // MARK: - Feature Hint

    private func featureHint(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.accentColor.opacity(0.8))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}
