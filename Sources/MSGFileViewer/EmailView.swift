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
                loadingView
            } else if let error = viewModel.error {
                errorView(error: error)
            } else if let email = viewModel.email {
                emailContentView(email: email)
            } else {
                emptyStateView
            }
        }
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading email…")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Error State

    private func errorView(error: Error) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 56, height: 56)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.red)
            }
            Text("Unable to Open File")
                .font(.system(size: 15, weight: .semibold))
            Text(error.localizedDescription)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "envelope.open")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.6))
            Text("Open a .msg file to view its contents.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Email Content

    @ViewBuilder
    private func emailContentView(email: Email) -> some View {
        VStack(spacing: 0) {
            // Metadata section
            ScrollView {
                metadataSection(email: email)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
            .frame(maxHeight: 220)
            .background(Color(nsColor: .controlBackgroundColor))

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
        VStack(alignment: .leading, spacing: 14) {
            // Subject - prominent
            Text(email.subject ?? "No Subject")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(3)
                .textSelection(.enabled)

            // Metadata rows
            VStack(alignment: .leading, spacing: 10) {
                metadataRow(label: "From", value: formattedSender(name: email.senderName, email: email.senderEmail), color: .blue)

                metadataRow(label: "To", value: formattedRecipients(email.toRecipients), color: .green)

                if !email.ccRecipients.isEmpty {
                    metadataRow(label: "CC", value: formattedRecipients(email.ccRecipients), color: .orange)
                }

                metadataRow(label: "Date", value: formattedDate(email.sentDate), color: .purple)
            }
        }
    }

    // MARK: - Metadata Row with Badge

    private func metadataRow(label: String, value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.1))
                )
                .frame(width: 56, alignment: .center)

            Text(value)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .textSelection(.enabled)
                .lineLimit(3)
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
