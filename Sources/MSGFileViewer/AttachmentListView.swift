// MSGFileViewer - AttachmentListView
// Displays a list of email attachments with save functionality

import SwiftUI
import MSGParser

/// A view that displays the list of attachments for a parsed email.
///
/// Shows each attachment's filename and formatted size, with a save button
/// for non-corrupted attachments and a warning indicator for corrupted ones.
/// The entire section is hidden when the attachments array is empty.
struct AttachmentListView: View {
    let attachments: [Attachment]
    let onSave: (Attachment) -> Void

    var body: some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Attachments (\(attachments.count))")
                    .font(.headline)

                ForEach(attachments) { attachment in
                    HStack {
                        if attachment.isCorrupted {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                        } else {
                            Image(systemName: "paperclip")
                        }

                        VStack(alignment: .leading) {
                            Text(attachment.filename)
                                .lineLimit(1)
                            Text(attachment.formattedSize)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if !attachment.isCorrupted {
                            Button("Save") {
                                onSave(attachment)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
    }
}
