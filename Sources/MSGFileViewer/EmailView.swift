// MSGFileViewer - EmailView
// Main view for displaying parsed email content with metadata section

import SwiftUI
import MSGParser

/// Main view that displays the parsed email content including metadata,
/// body, and attachments.
struct EmailView: View {
    @ObservedObject var viewModel: EmailViewModel

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("Loading email…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Error")
                        .font(.headline)
                    Text(error.localizedDescription)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if let email = viewModel.email {
                emailContentView(email: email)
            } else {
                Text("Open a .msg file to view its contents.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Email Content

    @ViewBuilder
    private func emailContentView(email: Email) -> some View {
        VStack(spacing: 0) {
            // Metadata section (scrollable if needed, but compact)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    metadataSection(email: email)
                }
                .padding()
            }
            .frame(maxHeight: 200)  // Cap metadata height

            Divider()

            // Body content takes remaining space
            BodyContentView(emailBody: email.body, selectedFormat: $viewModel.selectedBodyFormat)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Attachments at the bottom
            if !email.attachments.isEmpty {
                Divider()
                AttachmentListView(attachments: email.attachments) { attachment in
                    viewModel.saveAttachment(attachment)
                }
            }
        }
    }

    // MARK: - Metadata Section

    @ViewBuilder
    private func metadataSection(email: Email) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Subject
            Text(email.subject ?? "No Subject")
                .font(.title2)
                .fontWeight(.semibold)
                .lineLimit(3)
            
            // Metadata grid with labels
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Text("From")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                    Text(formattedSender(name: email.senderName, email: email.senderEmail))
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
                
                GridRow {
                    Text("To")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                    Text(formattedRecipients(email.toRecipients))
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
                
                if !email.ccRecipients.isEmpty {
                    GridRow {
                        Text("CC")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .trailing)
                        Text(formattedRecipients(email.ccRecipients))
                            .font(.subheadline)
                            .textSelection(.enabled)
                    }
                }
                
                GridRow {
                    Text("Date")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(width: 50, alignment: .trailing)
                    Text(formattedDate(email.sentDate))
                        .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Formatting Helpers

    /// Formats the sender display string.
    /// Shows "Name <email>" if both are present, just name or email if one is available,
    /// or "Unknown Sender" if both are nil.
    private func formattedSender(name: String?, email: String?) -> String {
        switch (name, email) {
        case let (name?, email?):
            return "\(name) <\(email)>"
        case let (name?, nil):
            return name
        case let (nil, email?):
            return email
        case (nil, nil):
            return "Unknown Sender"
        }
    }

    /// Formats a list of recipients as a comma-separated string.
    /// Shows displayName if available, otherwise emailAddress, otherwise "Unknown".
    private func formattedRecipients(_ recipients: [Recipient]) -> String {
        if recipients.isEmpty {
            return "None"
        }
        return recipients.map { recipient in
            if let displayName = recipient.displayName, !displayName.isEmpty {
                return displayName
            } else if let emailAddress = recipient.emailAddress, !emailAddress.isEmpty {
                return emailAddress
            } else {
                return "Unknown"
            }
        }.joined(separator: ", ")
    }

    /// Formats a date using the user's locale and timezone with medium date and short time style.
    /// Returns "No Date" if the date is nil.
    private func formattedDate(_ date: Date?) -> String {
        guard let date = date else {
            return "No Date"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}
