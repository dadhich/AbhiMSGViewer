// MSGParser - Body Content Extraction
// Extracts plain text, HTML, and RTF body formats from MAPI properties and streams

import Foundation

/// Extracts email body content (plain text, HTML, RTF) from MAPI properties and streams.
public struct BodyExtractor {

    // MARK: - Stream Names

    /// Stream name for the HTML body (PidTagHtml: id=0x1013, type=0x0102)
    private static let htmlStreamName = "__substg1.0_10130102"

    /// Stream name for the compressed RTF body (PidTagRtfCompressed: id=0x1009, type=0x0102)
    private static let rtfStreamName = "__substg1.0_10090102"

    // MARK: - Public API

    /// Extracts all available body formats from the given properties and streams.
    ///
    /// This method attempts to extract plain text, HTML, and RTF body content independently.
    /// If one format fails to extract, the others are still returned. No errors are thrown;
    /// failed formats are represented as nil in the returned `EmailBody`.
    ///
    /// - Parameters:
    ///   - properties: The extracted MAPI properties for the message.
    ///   - streams: The raw stream data dictionary from the CFB structure.
    ///   - codePage: The code page from PidTagInternetCodepage, or nil if not available.
    /// - Returns: An `EmailBody` containing whichever formats were successfully extracted.
    public static func extractBody(
        from properties: [MAPIProperty],
        streams: [String: Data],
        codePage: UInt32?
    ) -> EmailBody {
        let plainText = extractPlainText(from: properties)
        let html = extractHTML(from: streams, codePage: codePage, properties: properties)
        let rtf = extractRTF(from: streams, properties: properties)

        return EmailBody(plainText: plainText, html: html, rtf: rtf)
    }

    // MARK: - Plain Text Extraction

    /// Extracts plain text body from PidTagBody in the properties array.
    ///
    /// PidTagBody (id=0x1000, type=0x001F) is stored as a PT_UNICODE string value.
    /// The MAPIPropertyExtractor already handles decoding from UTF-16LE or the
    /// appropriate code page, so we just look for the string value.
    private static func extractPlainText(from properties: [MAPIProperty]) -> String? {
        for property in properties {
            if property.tag.id == MAPIPropertyTag.bodyPlainText.id {
                if case .string(let text) = property.value {
                    return text.isEmpty ? nil : text
                }
            }
        }
        return nil
    }

    // MARK: - HTML Extraction

    /// Extracts HTML body from the PidTagHtml stream.
    ///
    /// The HTML body is stored as binary data in the stream "__substg1.0_10130102".
    /// Decoding priority:
    /// 1. Try UTF-8
    /// 2. If that fails or the HTML declares a charset in a meta tag, use that charset
    /// 3. Fall back to the code page from PidTagInternetCodepage
    private static func extractHTML(from streams: [String: Data], codePage: UInt32?, properties: [MAPIProperty]? = nil) -> String? {
        // Try direct stream lookup first
        var htmlData: Data? = streams[htmlStreamName]

        // Fallback: check if HTML was extracted as a binary property
        if htmlData == nil, let properties = properties {
            for property in properties {
                if property.tag.id == 0x1013 {  // PidTagHtml
                    if case .binary(let data) = property.value {
                        htmlData = data
                        break
                    }
                }
            }
        }

        guard let resolvedData = htmlData, !resolvedData.isEmpty else {
            return nil
        }

        // First attempt: decode as UTF-8
        if let utf8String = String(data: resolvedData, encoding: .utf8) {
            // Check if HTML declares a different charset via meta tag
            if let declaredCharset = extractCharsetFromHTML(utf8String),
               let charset = stringEncoding(forCharset: declaredCharset),
               charset != .utf8 {
                // Re-decode with the declared charset
                if let reDecoded = String(data: resolvedData, encoding: charset) {
                    return reDecoded.isEmpty ? nil : reDecoded
                }
            }
            return utf8String.isEmpty ? nil : utf8String
        }

        // UTF-8 failed; try code page encoding
        if let codePage = codePage {
            let encoding = stringEncoding(forCodePage: codePage)
            if let decoded = String(data: resolvedData, encoding: encoding) {
                return decoded.isEmpty ? nil : decoded
            }
        }

        // Last resort: try latin1 which can decode any byte sequence
        if let latin1 = String(data: resolvedData, encoding: .isoLatin1) {
            return latin1.isEmpty ? nil : latin1
        }

        return nil
    }

    /// Extracts the charset value from an HTML charset meta tag.
    ///
    /// Looks for patterns like:
    /// - `<meta charset="UTF-8">`
    /// - `<meta http-equiv="Content-Type" content="text/html; charset=windows-1252">`
    private static func extractCharsetFromHTML(_ html: String) -> String? {
        // Pattern 1: <meta charset="...">
        let charsetPattern = #"<meta[^>]+charset=[\"']?([^\"'\s;>]+)"#
        if let range = html.range(of: charsetPattern, options: [.regularExpression, .caseInsensitive]) {
            let match = String(html[range])
            // Extract the charset value after "charset="
            if let charsetRange = match.range(of: "charset=", options: .caseInsensitive) {
                var value = String(match[charsetRange.upperBound...])
                // Remove surrounding quotes if present
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ;>"))
                if !value.isEmpty {
                    return value.lowercased()
                }
            }
        }

        // Pattern 2: content="text/html; charset=..."
        let contentPattern = #"content=[\"'][^\"']*charset=([^\"'\s;>]+)"#
        if let range = html.range(of: contentPattern, options: [.regularExpression, .caseInsensitive]) {
            let match = String(html[range])
            if let charsetRange = match.range(of: "charset=", options: .caseInsensitive) {
                var value = String(match[charsetRange.upperBound...])
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ;>"))
                if !value.isEmpty {
                    return value.lowercased()
                }
            }
        }

        return nil
    }

    // MARK: - RTF Extraction

    /// Extracts RTF body by decompressing PidTagRtfCompressed data.
    ///
    /// The compressed RTF is stored in the stream "__substg1.0_10090102".
    /// Uses LZFuDecompressor to decompress. If decompression fails for any reason,
    /// returns nil rather than crashing.
    private static func extractRTF(from streams: [String: Data], properties: [MAPIProperty]? = nil) -> Data? {
        // Try direct stream lookup first
        var compressedData: Data? = streams[rtfStreamName]

        // Fallback: check properties for RTF binary data
        if compressedData == nil, let properties = properties {
            for property in properties {
                if property.tag.id == 0x1009 {  // PidTagRtfCompressed
                    if case .binary(let data) = property.value {
                        compressedData = data
                        break
                    }
                }
            }
        }

        guard let resolvedData = compressedData, !resolvedData.isEmpty else {
            return nil
        }

        do {
            let decompressed = try LZFuDecompressor.decompress(resolvedData)
            return decompressed.isEmpty ? nil : decompressed
        } catch {
            // Decompression failed — return nil per requirement 3.7
            return nil
        }
    }

    // MARK: - Encoding Helpers

    /// Maps a charset name (from HTML meta tag) to a Swift String.Encoding.
    private static func stringEncoding(forCharset charset: String) -> String.Encoding? {
        switch charset {
        case "utf-8":
            return .utf8
        case "iso-8859-1", "latin1":
            return .isoLatin1
        case "iso-8859-2", "latin2":
            return .isoLatin2
        case "windows-1250", "cp1250":
            return .windowsCP1250
        case "windows-1251", "cp1251":
            return .windowsCP1251
        case "windows-1252", "cp1252":
            return .windowsCP1252
        case "windows-1253", "cp1253":
            return .windowsCP1253
        case "windows-1254", "cp1254":
            return .windowsCP1254
        case "ascii", "us-ascii":
            return .ascii
        case "shift_jis", "shift-jis", "sjis":
            return .shiftJIS
        case "iso-2022-jp":
            return .iso2022JP
        case "euc-jp":
            return .japaneseEUC
        case "utf-16", "utf-16le":
            return .utf16LittleEndian
        case "utf-16be":
            return .utf16BigEndian
        default:
            return nil
        }
    }

    /// Maps a Windows code page number to a Swift String.Encoding.
    private static func stringEncoding(forCodePage codePage: UInt32) -> String.Encoding {
        switch codePage {
        case 65001:
            return .utf8
        case 1252:
            return .windowsCP1252
        case 28591:
            return .isoLatin1
        case 1250:
            return .windowsCP1250
        case 1251:
            return .windowsCP1251
        case 1253:
            return .windowsCP1253
        case 1254:
            return .windowsCP1254
        case 1256:
            // Windows-1256 (Arabic) - not directly available, fallback to UTF-8
            return .utf8
        case 50220, 50221, 50222:
            return .iso2022JP
        case 932:
            return .shiftJIS
        case 20127:
            return .ascii
        default:
            return .utf8
        }
    }
}
