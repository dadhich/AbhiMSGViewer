// MSGFileViewer - BodyContentView
// Displays email body content with format toggle for HTML, plain text, and RTF

import SwiftUI
import AppKit
import MSGParser

/// Displays the email body content with a format toggle when multiple formats are available.
struct BodyContentView: View {
    let emailBody: EmailBody
    @Binding var selectedFormat: BodyFormat

    var body: some View {
        VStack(spacing: 0) {
            // Format toolbar when multiple formats available
            if availableFormats.count > 1 {
                formatPickerBar
            }

            // Content display
            switch selectedFormat {
            case .html:
                if let html = emailBody.html {
                    OfflineWebView(htmlContent: html)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .plainText:
                if let text = emailBody.plainText {
                    ScrollView {
                        Text(text)
                            .font(.system(size: 13, weight: .regular, design: .default))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                }
            case .rtf:
                if let rtfData = emailBody.rtf {
                    RTFView(data: rtfData)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .none:
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No body content")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Format Picker Bar

    private var formatPickerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Picker("", selection: $selectedFormat) {
                ForEach(availableFormats, id: \.self) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Color(nsColor: .controlBackgroundColor)
                .shadow(color: .black.opacity(0.04), radius: 1, x: 0, y: 1)
        )
    }

    /// Returns the list of available body formats based on what content exists.
    var availableFormats: [BodyFormat] {
        var formats = [BodyFormat]()
        if emailBody.html != nil { formats.append(.html) }
        if emailBody.plainText != nil { formats.append(.plainText) }
        if emailBody.rtf != nil { formats.append(.rtf) }
        return formats
    }
}

/// NSViewRepresentable wrapper for rendering RTF data using NSTextView.
struct RTFView: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.autoresizingMask = [.width, .height]
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if let attrString = NSAttributedString(rtf: data, documentAttributes: nil) {
            textView.textStorage?.setAttributedString(attrString)
        }
    }
}
