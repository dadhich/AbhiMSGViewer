// MSGFileViewer - EmailViewModel
// Drives the SwiftUI view layer for displaying parsed .msg email data

import SwiftUI
import MSGParser

/// Observable view model for displaying a parsed email.
@MainActor
final class EmailViewModel: ObservableObject {
    @Published var email: Email?
    @Published var isLoading: Bool = false
    @Published var error: MSGParserError?
    @Published var selectedBodyFormat: BodyFormat = .html

    private let parser = MSGParser()

    /// Opens and parses a .msg file at the given URL.
    ///
    /// Sets loading state immediately, performs parsing on a background executor
    /// via the MSGParser actor, then updates published properties on completion.
    func openFile(url: URL) {
        isLoading = true
        error = nil
        email = nil

        Task {
            do {
                let parsedEmail = try await parser.parse(url: url)
                self.email = parsedEmail
                self.selectedBodyFormat = parsedEmail.body.preferredFormat
            } catch let parserError as MSGParserError {
                self.error = parserError
            } catch {
                self.error = MSGParserError.propertyExtractionFailed(error.localizedDescription)
            }
            self.isLoading = false
        }
    }

    /// Exports an attachment to disk by presenting an NSSavePanel.
    ///
    /// Shows a save dialog with the attachment's filename as the suggested name.
    /// If the user confirms, writes the attachment data to the selected location.
    func saveAttachment(_ attachment: Attachment) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = attachment.filename
        panel.canCreateDirectories = true

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }

            guard let data = attachment.data else {
                Task { @MainActor in
                    self?.error = MSGParserError.propertyExtractionFailed(
                        "Attachment data is unavailable"
                    )
                }
                return
            }

            do {
                try data.write(to: url, options: .atomic)
            } catch {
                Task { @MainActor in
                    self?.error = MSGParserError.propertyExtractionFailed(
                        "Failed to save attachment: \(error.localizedDescription)"
                    )
                }
            }
        }
    }
}
