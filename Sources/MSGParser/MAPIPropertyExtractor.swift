// MSGParser - MAPI Property Extractor
// Extracts typed MAPI properties from CFB stream data

import Foundation

/// Extracts typed MAPI properties from CFB stream data.
public struct MAPIPropertyExtractor {

    // MARK: - Constants

    /// The property stream name used in MSG root and sub-storages.
    private static let propertyStreamName = "__properties_version1.0"

    /// Header size for root storage property streams (8 bytes reserved + 24 bytes metadata).
    private static let rootHeaderSize = 32

    /// Header size for sub-storage property streams (8 bytes reserved).
    private static let subStorageHeaderSize = 8

    /// Size of each property entry in the property stream (16 bytes).
    private static let propertyEntrySize = 16

    /// FILETIME epoch offset: seconds between 1601-01-01 and 1970-01-01.
    private static let filetimeEpochOffset: Double = 11_644_473_600

    /// 100-nanosecond intervals per second.
    private static let filetimeIntervalsPerSecond: Double = 10_000_000

    // MARK: - Public API

    /// Extracts all properties from the streams of a storage.
    ///
    /// The `streams` dictionary maps stream names (e.g., `"__properties_version1.0"`,
    /// `"__substg1.0_0037001F"`) to their raw `Data`. The method finds the property stream,
    /// parses each entry, and resolves variable-length data from the corresponding substg streams.
    ///
    /// - Parameters:
    ///   - streams: A dictionary mapping stream names to their data content.
    ///   - codePage: An optional code page value (from PidTagInternetCodepage) for ANSI string decoding.
    ///              If nil, defaults to UTF-8.
    ///   - isRootStorage: Whether this is the root storage (32-byte header) or a sub-storage (8-byte header).
    /// - Returns: An array of extracted `MAPIProperty` values.
    /// - Throws: `MSGParserError.propertyExtractionFailed` if the property stream is missing or malformed.
    public static func extractProperties(
        from streams: [String: Data],
        codePage: UInt32? = nil,
        isRootStorage: Bool = true
    ) throws -> [MAPIProperty] {
        guard let propertyData = streams[propertyStreamName] else {
            throw MSGParserError.propertyExtractionFailed(
                "missing property stream '\(propertyStreamName)'"
            )
        }

        let headerSize = isRootStorage ? rootHeaderSize : subStorageHeaderSize

        // Ensure we have at least the header
        guard propertyData.count >= headerSize else {
            throw MSGParserError.propertyExtractionFailed(
                "property stream too short: \(propertyData.count) bytes, expected at least \(headerSize)"
            )
        }

        // Determine the effective code page for ANSI string decoding
        let effectiveCodePage = codePage ?? resolveCodePage(from: streams, propertyData: propertyData, headerSize: headerSize)

        let entryCount = (propertyData.count - headerSize) / propertyEntrySize
        var properties = [MAPIProperty]()
        properties.reserveCapacity(entryCount)

        for i in 0..<entryCount {
            let entryOffset = headerSize + (i * propertyEntrySize)

            // Parse the 16-byte entry: [type:UInt16][id:UInt16][flags:UInt32][value:8 bytes]
            let propertyType: UInt16 = propertyData.readLittleEndianUInt16(at: entryOffset)
            let propertyID: UInt16 = propertyData.readLittleEndianUInt16(at: entryOffset + 2)
            // flags at entryOffset + 4 (4 bytes) - not used for extraction
            // value at entryOffset + 8 (8 bytes)

            let tag = MAPIPropertyTag(id: propertyID, type: propertyType)

            if let value = extractValue(
                type: propertyType,
                propertyID: propertyID,
                entryOffset: entryOffset,
                propertyData: propertyData,
                streams: streams,
                codePage: effectiveCodePage
            ) {
                properties.append(MAPIProperty(tag: tag, value: value))
            }
            // Skip unrecognized property types without failing
        }

        return properties
    }

    // MARK: - Value Extraction

    /// Extracts a typed value for a single property entry.
    ///
    /// - Parameters:
    ///   - type: The MAPI property type (e.g., 0x001F for PT_UNICODE).
    ///   - propertyID: The property identifier.
    ///   - entryOffset: Byte offset of this entry in the property stream.
    ///   - propertyData: The raw property stream data.
    ///   - streams: All streams in the storage for resolving variable-length data.
    ///   - codePage: The code page for ANSI string decoding.
    /// - Returns: The extracted `MAPIPropertyValue`, or nil if the type is unrecognized.
    private static func extractValue(
        type: UInt16,
        propertyID: UInt16,
        entryOffset: Int,
        propertyData: Data,
        streams: [String: Data],
        codePage: UInt32
    ) -> MAPIPropertyValue? {
        let valueOffset = entryOffset + 8

        switch type {
        case MAPIPropertyTag.typeUnicode:
            // PT_UNICODE: variable-length, data in substg stream
            return extractUnicodeString(propertyID: propertyID, type: type, streams: streams)

        case MAPIPropertyTag.typeString8:
            // PT_STRING8: variable-length, ANSI data in substg stream
            return extractAnsiString(propertyID: propertyID, type: type, streams: streams, codePage: codePage)

        case MAPIPropertyTag.typeBinary:
            // PT_BINARY: variable-length, data in substg stream
            return extractBinaryData(propertyID: propertyID, type: type, streams: streams)

        case MAPIPropertyTag.typeLong:
            // PT_LONG: 32-bit integer stored in the value area (first 4 bytes)
            guard valueOffset + 4 <= propertyData.count else { return nil }
            let intValue: Int32 = propertyData.readLittleEndianInt32(at: valueOffset)
            return .int32(intValue)

        case MAPIPropertyTag.typeI8:
            // PT_I8: 64-bit integer stored in the value area (all 8 bytes)
            guard valueOffset + 8 <= propertyData.count else { return nil }
            let intValue: Int64 = propertyData.readLittleEndianInt64(at: valueOffset)
            return .int64(intValue)

        case MAPIPropertyTag.typeSysTime:
            // PT_SYSTIME: FILETIME (64-bit, 100ns intervals since 1601-01-01)
            guard valueOffset + 8 <= propertyData.count else { return nil }
            let fileTime: UInt64 = propertyData.readLittleEndianUInt64(at: valueOffset)
            let date = convertFileTimeToDate(fileTime)
            return .time(date)

        case MAPIPropertyTag.typeBoolean:
            // PT_BOOLEAN: 16-bit value in the value area (non-zero = true)
            guard valueOffset + 2 <= propertyData.count else { return nil }
            let boolValue: UInt16 = propertyData.readLittleEndianUInt16(at: valueOffset)
            return .boolean(boolValue != 0)

        case 0x000D:
            // PT_OBJECT: embedded object, data stored in substg stream (same as binary)
            return extractBinaryData(propertyID: propertyID, type: type, streams: streams)

        default:
            // Unrecognized property type - skip without failing
            return nil
        }
    }

    // MARK: - Variable-Length Property Extraction

    /// Extracts a Unicode (UTF-16LE) string from the corresponding substg stream.
    /// Tries the exact type first, then falls back to alternate string types and prefix search.
    private static func extractUnicodeString(
        propertyID: UInt16,
        type: UInt16,
        streams: [String: Data]
    ) -> MAPIPropertyValue? {
        // Try exact match first
        let primaryName = substgStreamName(propertyID: propertyID, type: type)
        var data: Data? = streams[primaryName]

        // Fallback: try PT_STRING8 name if PT_UNICODE name not found
        if data == nil && type == MAPIPropertyTag.typeUnicode {
            let altName = substgStreamName(propertyID: propertyID, type: MAPIPropertyTag.typeString8)
            if let altData = streams[altName] {
                // It's actually stored as ANSI in a Unicode-typed property entry
                // Try to decode as UTF-8
                if let string = String(data: altData, encoding: .utf8) {
                    let trimmed = string.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                    return .string(trimmed)
                }
            }
        }

        // Fallback: prefix search
        if data == nil {
            let prefix = "__substg1.0_\(String(format: "%04X", propertyID))"
            for (name, streamData) in streams {
                if name.hasPrefix(prefix) {
                    data = streamData
                    break
                }
            }
        }

        guard let resolvedData = data else { return nil }

        // UTF-16LE decoding; strip trailing null characters
        guard let string = String(data: resolvedData, encoding: .utf16LittleEndian) else { return nil }
        let trimmed = string.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        return .string(trimmed)
    }

    /// Extracts an ANSI string from the corresponding substg stream using the specified code page.
    /// Tries the exact type first, then falls back to alternate string types and prefix search.
    private static func extractAnsiString(
        propertyID: UInt16,
        type: UInt16,
        streams: [String: Data],
        codePage: UInt32
    ) -> MAPIPropertyValue? {
        // Try exact match first
        let primaryName = substgStreamName(propertyID: propertyID, type: type)
        var data: Data? = streams[primaryName]

        // Fallback: try PT_UNICODE name if PT_STRING8 name not found
        if data == nil && type == MAPIPropertyTag.typeString8 {
            let altName = substgStreamName(propertyID: propertyID, type: MAPIPropertyTag.typeUnicode)
            if let altData = streams[altName] {
                // It's stored as Unicode - decode as UTF-16LE
                if let string = String(data: altData, encoding: .utf16LittleEndian) {
                    let trimmed = string.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
                    return .string(trimmed)
                }
            }
        }

        // Fallback: prefix search
        if data == nil {
            let prefix = "__substg1.0_\(String(format: "%04X", propertyID))"
            for (name, streamData) in streams {
                if name.hasPrefix(prefix) {
                    data = streamData
                    break
                }
            }
        }

        guard let resolvedData = data else { return nil }

        let encoding = stringEncoding(forCodePage: codePage)
        guard let string = String(data: resolvedData, encoding: encoding) else {
            // Fallback to UTF-8 if the specified encoding fails
            guard let fallback = String(data: resolvedData, encoding: .utf8) else { return nil }
            let trimmed = fallback.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
            return .string(trimmed)
        }
        let trimmed = string.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        return .string(trimmed)
    }

    /// Extracts binary data from the corresponding substg stream.
    /// Tries the exact type first, then falls back to common binary type variants.
    private static func extractBinaryData(
        propertyID: UInt16,
        type: UInt16,
        streams: [String: Data]
    ) -> MAPIPropertyValue? {
        // Try exact match first
        let primaryName = substgStreamName(propertyID: propertyID, type: type)
        if let data = streams[primaryName] {
            return .binary(data)
        }

        // Fallback: try PT_BINARY (0x0102) if original type was different
        if type != MAPIPropertyTag.typeBinary {
            let binaryName = substgStreamName(propertyID: propertyID, type: MAPIPropertyTag.typeBinary)
            if let data = streams[binaryName] {
                return .binary(data)
            }
        }

        // Fallback: try PT_OBJECT (0x000D) if original type was different
        if type != 0x000D {
            let objectName = substgStreamName(propertyID: propertyID, type: 0x000D)
            if let data = streams[objectName] {
                return .binary(data)
            }
        }

        // Last resort: search for any stream matching the property ID prefix
        let prefix = "__substg1.0_\(String(format: "%04X", propertyID))"
        for (name, data) in streams {
            if name.hasPrefix(prefix) {
                return .binary(data)
            }
        }

        return nil
    }

    // MARK: - Stream Name Generation

    /// Generates the substg stream name for a variable-length property.
    ///
    /// The format is `__substg1.0_XXXXYYYY` where XXXX is the property ID in uppercase hex
    /// and YYYY is the property type in uppercase hex.
    private static func substgStreamName(propertyID: UInt16, type: UInt16) -> String {
        let idHex = String(format: "%04X", propertyID)
        let typeHex = String(format: "%04X", type)
        return "__substg1.0_\(idHex)\(typeHex)"
    }

    // MARK: - FILETIME Conversion

    /// Converts a Windows FILETIME value to a Swift `Date`.
    ///
    /// FILETIME is a 64-bit value representing 100-nanosecond intervals since January 1, 1601.
    /// We convert to Unix epoch (January 1, 1970) by subtracting the offset.
    private static func convertFileTimeToDate(_ fileTime: UInt64) -> Date {
        let seconds = Double(fileTime) / filetimeIntervalsPerSecond - filetimeEpochOffset
        return Date(timeIntervalSince1970: seconds)
    }

    // MARK: - Code Page Resolution

    /// Attempts to resolve the code page from the property stream itself.
    ///
    /// Looks for PidTagInternetCodepage (0x3FDE, PT_LONG) in the property entries
    /// to determine the code page before full extraction.
    private static func resolveCodePage(
        from streams: [String: Data],
        propertyData: Data,
        headerSize: Int
    ) -> UInt32 {
        let entryCount = (propertyData.count - headerSize) / propertyEntrySize

        for i in 0..<entryCount {
            let entryOffset = headerSize + (i * propertyEntrySize)
            let propertyType: UInt16 = propertyData.readLittleEndianUInt16(at: entryOffset)
            let propertyID: UInt16 = propertyData.readLittleEndianUInt16(at: entryOffset + 2)

            // PidTagInternetCodepage: id=0x3FDE, type=PT_LONG(0x0003)
            if propertyID == 0x3FDE && propertyType == MAPIPropertyTag.typeLong {
                let valueOffset = entryOffset + 8
                if valueOffset + 4 <= propertyData.count {
                    let codePageValue: Int32 = propertyData.readLittleEndianInt32(at: valueOffset)
                    return UInt32(bitPattern: codePageValue)
                }
            }
        }

        // Default: UTF-8
        return 65001
    }

    // MARK: - Recipient Extraction

    /// Extracts recipients from their sub-storage streams.
    ///
    /// In an MSG file, recipients are stored as sub-storages named
    /// `__recip_version2.0_#XXXXXXXX` where XXXXXXXX is a zero-padded hex index.
    /// Each sub-storage contains a property stream and substg streams just like
    /// the root storage, but with an 8-byte header.
    ///
    /// - Parameters:
    ///   - recipientStreams: An array where each element is a dictionary mapping
    ///                       stream names to their data for one recipient sub-storage.
    ///   - codePage: An optional code page for ANSI string decoding. If nil, defaults to UTF-8.
    /// - Returns: An array of `Recipient` values extracted from the sub-storages.
    /// - Throws: `MSGParserError.propertyExtractionFailed` if property extraction fails for a recipient.
    public static func extractRecipients(
        from recipientStreams: [[String: Data]],
        codePage: UInt32? = nil
    ) throws -> [Recipient] {
        var recipients = [Recipient]()
        recipients.reserveCapacity(recipientStreams.count)

        for streams in recipientStreams {
            let properties = try extractProperties(
                from: streams,
                codePage: codePage,
                isRootStorage: false
            )

            var displayName: String?
            var emailAddress: String?
            var recipientTypeValue: Int32 = 1 // Default to TO if not specified

            for property in properties {
                switch property.tag.id {
                case MAPIPropertyTag.displayName.id:  // 0x3001
                    if case .string(let value) = property.value {
                        displayName = value
                    }
                case MAPIPropertyTag.emailAddress.id:  // 0x3003
                    if case .string(let value) = property.value {
                        emailAddress = value
                    }
                case MAPIPropertyTag.recipientType.id:  // 0x0C15
                    if case .int32(let value) = property.value {
                        recipientTypeValue = value
                    }
                default:
                    break
                }
            }

            // Fallback: check PidTagSmtpAddress (0x39FE) if primary email is empty
            if emailAddress == nil || emailAddress?.isEmpty == true {
                for property in properties {
                    if property.tag.id == 0x39FE {
                        if case .string(let value) = property.value {
                            emailAddress = value
                            break
                        }
                    }
                }
            }

            let type = RecipientType(rawValue: recipientTypeValue) ?? .to
            let recipient = Recipient(
                displayName: displayName,
                emailAddress: emailAddress,
                type: type
            )
            recipients.append(recipient)
        }

        return recipients
    }

    // MARK: - Attachment Extraction

    /// Extracts attachments from attachment sub-storage streams.
    ///
    /// Each element in `attachmentStreams` represents the streams dictionary for one
    /// attachment sub-storage (named `__attach_version2.0_#XXXXXXXX` in the CFB).
    ///
    /// - Parameters:
    ///   - attachmentStreams: An array of stream dictionaries, one per attachment sub-storage.
    ///   - codePage: An optional code page for ANSI string decoding.
    /// - Returns: An array of `Attachment` values.
    /// - Throws: `MSGParserError.propertyExtractionFailed` if property extraction fails.
    public static func extractAttachments(
        from attachmentStreams: [[String: Data]],
        codePage: UInt32? = nil
    ) throws -> [Attachment] {
        var attachments = [Attachment]()
        attachments.reserveCapacity(attachmentStreams.count)

        for (index, streams) in attachmentStreams.enumerated() {
            let properties = try extractProperties(
                from: streams,
                codePage: codePage,
                isRootStorage: false
            )

            // Extract filename: prefer PidTagAttachLongFilename, fallback to PidTagAttachFilename
            let filename: String
            if let longName = findStringProperty(
                properties: properties,
                id: MAPIPropertyTag.attachLongFilename.id,
                type: MAPIPropertyTag.attachLongFilename.type
            ) {
                filename = longName
            } else if let shortName = findStringProperty(
                properties: properties,
                id: MAPIPropertyTag.attachFilename.id,
                type: MAPIPropertyTag.attachFilename.type
            ) {
                filename = shortName
            } else {
                filename = "Attachment_\(index)"
            }

            // Extract binary data from PidTagAttachDataBinary
            let binaryData: Data?
            let isCorrupted: Bool
            if let data = findBinaryProperty(
                properties: properties,
                id: MAPIPropertyTag.attachDataBinary.id,
                type: MAPIPropertyTag.attachDataBinary.type
            ) {
                binaryData = data
                isCorrupted = false
            } else {
                binaryData = nil
                isCorrupted = true
            }

            // Extract size from PidTagAttachSize or compute from data length
            let size: Int
            if let sizeValue = findInt32Property(
                properties: properties,
                id: MAPIPropertyTag.attachSize.id,
                type: MAPIPropertyTag.attachSize.type
            ) {
                size = Int(sizeValue)
            } else {
                size = binaryData?.count ?? 0
            }

            // Extract MIME type from PidTagAttachMimeTag (optional)
            let mimeType = findStringProperty(
                properties: properties,
                id: MAPIPropertyTag.attachMimeTag.id,
                type: MAPIPropertyTag.attachMimeTag.type
            )

            let attachment = Attachment(
                filename: filename,
                size: size,
                mimeType: mimeType,
                data: binaryData,
                isCorrupted: isCorrupted
            )
            attachments.append(attachment)
        }

        return attachments
    }

    // MARK: - Property Lookup Helpers

    /// Finds a string value for a property with the given ID (ignoring type to handle STRING8/UNICODE variants).
    private static func findStringProperty(
        properties: [MAPIProperty],
        id: UInt16,
        type: UInt16
    ) -> String? {
        for property in properties {
            if property.tag.id == id {
                if case .string(let value) = property.value {
                    return value
                }
            }
        }
        return nil
    }

    /// Finds binary data for a property with the given ID (ignoring type).
    private static func findBinaryProperty(
        properties: [MAPIProperty],
        id: UInt16,
        type: UInt16
    ) -> Data? {
        for property in properties {
            if property.tag.id == id {
                if case .binary(let value) = property.value {
                    return value
                }
            }
        }
        return nil
    }

    /// Finds an Int32 value for a property with the given ID (ignoring type).
    private static func findInt32Property(
        properties: [MAPIProperty],
        id: UInt16,
        type: UInt16
    ) -> Int32? {
        for property in properties {
            if property.tag.id == id {
                if case .int32(let value) = property.value {
                    return value
                }
            }
        }
        return nil
    }

    // MARK: - Code Page to String Encoding

    /// Maps a Windows code page number to a Swift `String.Encoding`.
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
            // ISO-2022-JP variants
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

// MARK: - Data Extension for Little-Endian Reading

extension Data {
    /// Reads a UInt16 in little-endian format at the given byte offset.
    func readLittleEndianUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= self.count else { return 0 }
        return self.withUnsafeBytes { buffer in
            UInt16(littleEndian: buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
        }
    }

    /// Reads an Int32 in little-endian format at the given byte offset.
    func readLittleEndianInt32(at offset: Int) -> Int32 {
        guard offset + 4 <= self.count else { return 0 }
        return self.withUnsafeBytes { buffer in
            Int32(littleEndian: buffer.loadUnaligned(fromByteOffset: offset, as: Int32.self))
        }
    }

    /// Reads a UInt32 in little-endian format at the given byte offset.
    func readLittleEndianUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= self.count else { return 0 }
        return self.withUnsafeBytes { buffer in
            UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
    }

    /// Reads an Int64 in little-endian format at the given byte offset.
    func readLittleEndianInt64(at offset: Int) -> Int64 {
        guard offset + 8 <= self.count else { return 0 }
        return self.withUnsafeBytes { buffer in
            Int64(littleEndian: buffer.loadUnaligned(fromByteOffset: offset, as: Int64.self))
        }
    }

    /// Reads a UInt64 in little-endian format at the given byte offset.
    func readLittleEndianUInt64(at offset: Int) -> UInt64 {
        guard offset + 8 <= self.count else { return 0 }
        return self.withUnsafeBytes { buffer in
            UInt64(littleEndian: buffer.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
        }
    }
}
