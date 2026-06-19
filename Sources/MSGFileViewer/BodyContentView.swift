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
            // Format toggle (Picker) when multiple formats available
            if availableFormats.count > 1 {
                Picker("Format", selection: $selectedFormat) {
                    ForEach(availableFormats, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
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
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                }
            case .rtf:
                if let rtfData = emailBody.rtf {
                    RTFView(data: rtfData)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .none:
                Text("No body content")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
