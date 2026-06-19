// MSGFileViewer - AttachmentListView
// Displays a list of email attachments with save functionality

import SwiftUI
import MSGParser

/// A view that displays the list of attachments for a parsed email.
///
/// Shows each attachment as a card with file-type icon, filename, and size.
/// Cards are horizontally scrollable for compact layout.
/// The entire section is hidden when the attachments array is empty.
struct AttachmentListView: View {
    let attachments: [Attachment]
    let onSave: (Attachment) -> Void

    var body: some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.accentColor)
                    Text("Attachments")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("\(attachments.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.12))
                        )
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Attachment cards
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(attachments) { attachment in
                            AttachmentCard(attachment: attachment, onSave: onSave)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

struct AttachmentCard: View {
    let attachment: Attachment
    let onSave: (Attachment) -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 8) {
            // File type icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconBackgroundColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: iconForAttachment(attachment))
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(attachment.isCorrupted ? .red : iconBackgroundColor)
            }

            // Filename
            Text(attachment.filename)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 100)
                .foregroundColor(.primary)

            // File size
            Text(attachment.formattedSize)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .frame(width: 128, height: 110)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovering ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(isHovering ? 0.1 : 0.05), radius: isHovering ? 6 : 3, x: 0, y: isHovering ? 3 : 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovering ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            if !attachment.isCorrupted {
                onSave(attachment)
            }
        }
        .help(attachment.isCorrupted ? "Attachment is corrupted" : "Click to save \(attachment.filename)")
    }

    // MARK: - Icon Helpers

    private var iconBackgroundColor: Color {
        let ext = (attachment.filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return .red
        case "doc", "docx": return .blue
        case "xls", "xlsx": return .green
        case "ppt", "pptx": return .orange
        case "jpg", "jpeg", "png", "gif", "bmp": return .purple
        case "zip", "rar", "7z": return .brown
        case "txt": return .gray
        case "msg": return .cyan
        default: return .accentColor
        }
    }

    private func iconForAttachment(_ attachment: Attachment) -> String {
        let ext = (attachment.filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx": return "tablecells.fill"
        case "ppt", "pptx": return "rectangle.stack.fill"
        case "jpg", "jpeg", "png", "gif", "bmp": return "photo.fill"
        case "zip", "rar", "7z": return "archivebox.fill"
        case "txt": return "doc.plaintext.fill"
        case "msg": return "envelope.fill"
        default: return "doc.fill"
        }
    }
}
