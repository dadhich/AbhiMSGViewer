// MSGFileViewer - FileDropModifier
// Provides drag-and-drop support for opening .msg files

import SwiftUI
import UniformTypeIdentifiers

/// The UTType for Microsoft Outlook .msg files.
extension UTType {
    static let outlookMessage = UTType(
        exportedAs: "com.microsoft.outlook-message",
        conformingTo: .data
    )
}

/// A ViewModifier that adds .msg file drop support to any view.
/// Shows a visual drop indicator (highlighted border) when a file is targeted,
/// validates the dropped file has a .msg extension or the
/// `com.microsoft.outlook-message` UTType, and invokes the onDrop callback.
struct FileDropModifier: ViewModifier {
    @Binding var isTargeted: Bool
    let onDrop: (URL) -> Void

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .opacity(isTargeted ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.2), value: isTargeted)
            )
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        // Check if the provider can load a file URL
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

            // Validate the dropped file is a .msg file by extension or UTType
            guard Self.isValidMSGFile(url: url) else { return }

            DispatchQueue.main.async {
                onDrop(url)
            }
        }
        return true
    }

    /// Validates whether a file URL represents a valid .msg file.
    /// Checks both the file extension and the UTType conformance.
    /// - Parameter url: The file URL to validate.
    /// - Returns: `true` if the file has a `.msg` extension or conforms to
    ///            `com.microsoft.outlook-message` UTType.
    static func isValidMSGFile(url: URL) -> Bool {
        // Check by file extension
        if url.pathExtension.lowercased() == "msg" {
            return true
        }

        // Check by UTType conformance
        if let fileType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if fileType == .outlookMessage || fileType.conforms(to: .outlookMessage) {
                return true
            }
        }

        return false
    }
}

extension View {
    /// Adds .msg file drag-and-drop support to the view.
    /// - Parameters:
    ///   - isTargeted: Binding that indicates whether a drag is currently hovering over the view.
    ///   - onDrop: Closure invoked with the validated .msg file URL when a valid drop occurs.
    /// - Returns: A view with drag-and-drop support for .msg files.
    func msgFileDrop(isTargeted: Binding<Bool>, onDrop: @escaping (URL) -> Void) -> some View {
        modifier(FileDropModifier(isTargeted: isTargeted, onDrop: onDrop))
    }
}
