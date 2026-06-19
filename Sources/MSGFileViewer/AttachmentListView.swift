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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "paperclip")
                        .foregroundColor(.secondary)
                    Text("Attachments")
                        .font(.headline)
                    Text("(\(attachments.count))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(attachments) { attachment in
                            AttachmentCard(attachment: attachment, onSave: onSave)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                }
            }
        }
    }
}

struct AttachmentCard: View {
    let attachment: Attachment
    let onSave: (Attachment) -> Void
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: iconForAttachment(attachment))
                .font(.title2)
                .foregroundColor(attachment.isCorrupted ? .red : .accentColor)
            
            Text(attachment.filename)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 100)
            
            Text(attachment.formattedSize)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(width: 120, height: 100)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
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
    
    private func iconForAttachment(_ attachment: Attachment) -> String {
        let ext = (attachment.filename as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.richtext"
        case "doc", "docx": return "doc.text"
        case "xls", "xlsx": return "tablecells"
        case "ppt", "pptx": return "rectangle.stack"
        case "jpg", "jpeg", "png", "gif", "bmp": return "photo"
        case "zip", "rar", "7z": return "archivebox"
        case "txt": return "doc.plaintext"
        case "msg": return "envelope"
        default: return "doc"
        }
    }
}
