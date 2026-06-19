// MSGFileViewer - WindowManager
// Manages multi-window document opening with deduplication and window limit

import SwiftUI
import AppKit
import MSGParser

/// Manages open document windows with deduplication by file path and a maximum window limit.
///
/// Tracks open windows by their file path to prevent duplicate windows for the same file.
/// Limits the total number of simultaneous windows to `maxWindows` (20).
/// Handles file open requests from Finder double-click, dock icon drop, and File > Open menu.
@MainActor
final class WindowManager: ObservableObject {
    static let shared = WindowManager()

    /// Maps standardized file paths to their open windows.
    private(set) var openWindows: [String: NSWindow] = [:]

    /// Maximum number of simultaneous windows allowed.
    let maxWindows = 20

    private init() {}

    // MARK: - Public API

    /// Opens a file in a new window or brings an existing window to front if already open.
    ///
    /// - Parameter url: The URL of the .msg file to open.
    func openFile(url: URL) {
        let path = url.standardizedFileURL.path

        // Clean up any stale entries (windows that were closed outside our control)
        cleanUpClosedWindows()

        // Check if the file is already open — bring existing window to front
        if let existingWindow = openWindows[path] {
            if existingWindow.isMiniaturized {
                existingWindow.deminiaturize(nil)
            }
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Check window limit
        guard openWindows.count < maxWindows else {
            showWindowLimitAlert()
            return
        }

        // Create new window with EmailViewModel
        let viewModel = EmailViewModel()
        viewModel.openFile(url: url)

        let emailView = EmailView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: emailView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = url.lastPathComponent
        window.setContentSize(NSSize(width: 800, height: 600))
        window.minSize = NSSize(width: 600, height: 400)
        window.center()

        // Observe window close to remove from tracking
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let closedWindow = notification.object as? NSWindow else { return }
            Task { @MainActor in
                self?.removeWindow(closedWindow)
            }
        }

        openWindows[path] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Handles file open requests from Finder double-click or dock icon drop.
    ///
    /// Filters URLs to only process .msg files, then opens each one.
    /// - Parameter urls: Array of file URLs to open.
    func handleOpenURLs(_ urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "msg" {
            openFile(url: url)
        }
    }

    /// Returns true if a file at the given path is already open.
    ///
    /// - Parameter path: The standardized file path to check.
    /// - Returns: Whether a window is already open for this file.
    func isFileOpen(path: String) -> Bool {
        return openWindows[path] != nil
    }

    /// Returns the current number of open windows.
    var windowCount: Int {
        return openWindows.count
    }

    /// Presents a file open dialog filtered to .msg files.
    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "msg")].compactMap { $0 }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select .msg files to open"

        panel.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in
                self?.handleOpenURLs(panel.urls)
            }
        }
    }

    // MARK: - Private Helpers

    /// Shows an alert when the maximum window limit has been reached.
    private func showWindowLimitAlert() {
        let alert = NSAlert()
        alert.messageText = "Maximum number of windows reached"
        alert.informativeText = "Close an existing window before opening a new file. The limit is \(maxWindows) simultaneous windows."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Removes a closed window from the tracking dictionary.
    private func removeWindow(_ window: NSWindow) {
        openWindows = openWindows.filter { $0.value !== window }
    }

    /// Removes entries for windows that have been closed outside our notification path.
    private func cleanUpClosedWindows() {
        openWindows = openWindows.filter { _, window in
            // Keep windows that are still valid and known to the application
            // A window that is visible, miniaturized, or part of the app's window list is still alive
            return NSApp.windows.contains(window)
        }
    }

    // MARK: - Testing Support

    /// Resets the manager state. For testing only.
    func reset() {
        openWindows.removeAll()
    }

    /// Registers an external window for a given path. For testing only.
    func registerWindow(_ window: NSWindow, forPath path: String) {
        openWindows[path] = window
    }
}
