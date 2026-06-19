// MSGParser - Error types
// Defines errors for CFB parsing, LZFu decompression, and top-level parsing

import Foundation

/// Errors from CFB (Compound File Binary Format) parsing.
public enum CFBError: Error, CustomStringConvertible {
    /// The file does not have a valid OLE/CFB signature.
    case invalidSignature(expected: String, found: String)
    /// The file is corrupted at the specified sector.
    case corruptedFile(sectorIndex: UInt32, reason: String)
    /// The CFB version is not supported (only versions 3 and 4 are valid).
    case unsupportedVersion(UInt16)
    /// A stream could not be read from the file.
    case streamReadFailed(entryName: String, reason: String)

    public var description: String {
        switch self {
        case .invalidSignature(let expected, let found):
            return "invalid file format: expected signature \(expected), found \(found)"
        case .corruptedFile(let sector, let reason):
            return "corrupted file at sector \(sector): \(reason)"
        case .unsupportedVersion(let version):
            return "unsupported CFB version: \(version)"
        case .streamReadFailed(let name, let reason):
            return "failed to read stream '\(name)': \(reason)"
        }
    }
}

/// Errors from LZFu decompression of RTF body content.
public enum LZFuError: Error {
    /// The compressed data does not have a valid LZFu or MELA signature.
    case invalidSignature
    /// The CRC check failed after decompression.
    case crcMismatch(expected: UInt32, computed: UInt32)
    /// The compressed data is malformed at the given position.
    case corruptedData(position: Int)
    /// The decompressed data exceeded the declared uncompressed size.
    case uncompressedSizeExceeded
}

/// Top-level parser errors exposed to the UI layer.
public enum MSGParserError: Error, LocalizedError {
    /// The file could not be accessed (sandbox or permission issue).
    case fileAccessDenied(URL)
    /// The file is not a valid OLE/CFB format.
    case invalidFormat(CFBError)
    /// MAPI property extraction failed.
    case propertyExtractionFailed(String)
    /// RTF body decompression failed.
    case decompressionFailed(LZFuError)

    public var errorDescription: String? {
        switch self {
        case .fileAccessDenied(let url):
            return "Unable to open file: access denied to \(url.lastPathComponent)"
        case .invalidFormat(let cfbError):
            return "Unable to open file: \(cfbError.description)"
        case .propertyExtractionFailed(let detail):
            return "Failed to extract email data: \(detail)"
        case .decompressionFailed(let lzfuError):
            return "RTF decompression failed: \(lzfuError)"
        }
    }
}
