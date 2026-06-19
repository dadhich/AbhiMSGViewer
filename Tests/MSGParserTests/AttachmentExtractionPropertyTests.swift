// MSGParserTests - Property-based tests for attachment extraction round-trip
// Feature: msg-file-viewer, Property 9: Attachment Extraction Round-Trip

import XCTest
import SwiftCheck
import Foundation
@testable import MSGParser

// MARK: - Helpers

/// Encodes a string as UTF-16LE Data (for PT_UNICODE substg streams).
private func encodeUTF16LE(_ string: String) -> Data {
    return string.data(using: .utf16LittleEndian) ?? Data()
}

/// Generates the substg stream name for a property.
private func substgStreamName(propertyID: UInt16, type: UInt16) -> String {
    let idHex = String(format: "%04X", propertyID)
    let typeHex = String(format: "%04X", type)
    return "__substg1.0_\(idHex)\(typeHex)"
}

/// Builds a 16-byte property entry: [type:UInt16][id:UInt16][flags:UInt32][value:8 bytes]
private func buildPropertyEntry(type: UInt16, id: UInt16, flags: UInt32 = 0x00000002, inlineValue: Data) -> Data {
    var entry = Data(count: 16)
    // Type (UInt16 little-endian) at offset 0
    entry[0] = UInt8(type & 0xFF)
    entry[1] = UInt8((type >> 8) & 0xFF)
    // ID (UInt16 little-endian) at offset 2
    entry[2] = UInt8(id & 0xFF)
    entry[3] = UInt8((id >> 8) & 0xFF)
    // Flags (UInt32 little-endian) at offset 4
    entry[4] = UInt8(flags & 0xFF)
    entry[5] = UInt8((flags >> 8) & 0xFF)
    entry[6] = UInt8((flags >> 16) & 0xFF)
    entry[7] = UInt8((flags >> 24) & 0xFF)
    // Value (8 bytes) at offset 8
    let valueBytes = inlineValue + Data(count: max(0, 8 - inlineValue.count))
    for i in 0..<min(8, valueBytes.count) {
        entry[8 + i] = valueBytes[i]
    }
    return entry
}

/// Builds UInt32 as 4-byte little-endian Data.
private func uint32LEData(_ value: UInt32) -> Data {
    var v = value.littleEndian
    return Data(bytes: &v, count: 4)
}

/// Builds Int32 as 4-byte little-endian Data.
private func int32LEData(_ value: Int32) -> Data {
    var v = value.littleEndian
    return Data(bytes: &v, count: 4)
}

// MARK: - Test Data Model

/// Represents a generated attachment for property testing.
struct GeneratedAttachment {
    let longFilename: String?
    let shortFilename: String?
    let binaryData: Data?
    let mimeType: String?
    let explicitSize: Int32?

    /// The expected filename after extraction (long > short > fallback).
    var expectedFilename: String {
        if let long = longFilename { return long }
        if let short = shortFilename { return short }
        return "Attachment_0"
    }

    /// The expected size after extraction.
    var expectedSize: Int {
        if let explicit = explicitSize { return Int(explicit) }
        return binaryData?.count ?? 0
    }

    /// The expected isCorrupted value.
    var expectedIsCorrupted: Bool {
        return binaryData == nil
    }

    /// Builds the streams dictionary for this attachment sub-storage.
    func buildStreams() -> [String: Data] {
        var streams = [String: Data]()
        var propertyStream = Data()

        // 8-byte header for sub-storage
        propertyStream.append(contentsOf: [UInt8](repeating: 0, count: 8))

        // PidTagAttachLongFilename (id=0x3707, type=0x001F PT_UNICODE)
        if let longName = longFilename {
            let type: UInt16 = 0x001F
            let id: UInt16 = 0x3707
            let encoded = encodeUTF16LE(longName)
            let sizeData = uint32LEData(UInt32(encoded.count))
            propertyStream.append(buildPropertyEntry(type: type, id: id, inlineValue: sizeData))
            streams[substgStreamName(propertyID: id, type: type)] = encoded
        }

        // PidTagAttachFilename (id=0x3704, type=0x001F PT_UNICODE)
        if let shortName = shortFilename {
            let type: UInt16 = 0x001F
            let id: UInt16 = 0x3704
            let encoded = encodeUTF16LE(shortName)
            let sizeData = uint32LEData(UInt32(encoded.count))
            propertyStream.append(buildPropertyEntry(type: type, id: id, inlineValue: sizeData))
            streams[substgStreamName(propertyID: id, type: type)] = encoded
        }

        // PidTagAttachDataBinary (id=0x3701, type=0x0102 PT_BINARY)
        if let data = binaryData {
            let type: UInt16 = 0x0102
            let id: UInt16 = 0x3701
            let sizeData = uint32LEData(UInt32(data.count))
            propertyStream.append(buildPropertyEntry(type: type, id: id, inlineValue: sizeData))
            streams[substgStreamName(propertyID: id, type: type)] = data
        }

        // PidTagAttachMimeTag (id=0x370E, type=0x001F PT_UNICODE)
        if let mime = mimeType {
            let type: UInt16 = 0x001F
            let id: UInt16 = 0x370E
            let encoded = encodeUTF16LE(mime)
            let sizeData = uint32LEData(UInt32(encoded.count))
            propertyStream.append(buildPropertyEntry(type: type, id: id, inlineValue: sizeData))
            streams[substgStreamName(propertyID: id, type: type)] = encoded
        }

        // PidTagAttachSize (id=0x0E20, type=0x0003 PT_LONG) - inline value
        if let size = explicitSize {
            let type: UInt16 = 0x0003
            let id: UInt16 = 0x0E20
            let valueData = int32LEData(size)
            propertyStream.append(buildPropertyEntry(type: type, id: id, inlineValue: valueData))
        }

        streams["__properties_version1.0"] = propertyStream
        return streams
    }
}

// MARK: - Generators

/// Generates a filename suitable for attachment testing (printable ASCII, 1-30 chars with extension).
private func filenameGen() -> Gen<String> {
    let nameCharGen = Gen<Character>.fromElements(in: "a"..."z")
    let extensions = ["pdf", "docx", "png", "jpg", "txt", "xlsx", "zip"]
    return Gen<String>.compose { composer in
        let length = composer.generate(using: Gen<Int>.choose((1, 20)))
        let nameChars = (0..<length).map { _ in composer.generate(using: nameCharGen) }
        let ext = composer.generate(using: Gen.fromElements(of: extensions))
        return String(nameChars) + "." + ext
    }
}

/// Generates binary data of random length (1-200 bytes).
private func binaryDataGen() -> Gen<Data> {
    return Gen<Data>.compose { composer in
        let length = composer.generate(using: Gen<Int>.choose((1, 200)))
        let bytes: [UInt8] = (0..<length).map { _ in composer.generate(using: Gen<UInt8>.choose((0, 255))) }
        return Data(bytes)
    }
}

/// Generates an optional MIME type string.
private func optionalMimeGen() -> Gen<String?> {
    let mimeTypes = [
        "application/pdf",
        "image/png",
        "image/jpeg",
        "text/plain",
        "application/octet-stream",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    ]
    return Gen<String?>.frequency([
        (1, Gen.pure(nil)),
        (3, Gen.fromElements(of: mimeTypes).map { Optional($0) })
    ])
}

/// Generates an attachment with both long and short filenames (tests filename preference).
private func attachmentWithBothFilenamesGen() -> Gen<GeneratedAttachment> {
    return Gen<GeneratedAttachment>.compose { composer in
        let longName = composer.generate(using: filenameGen())
        let shortName = composer.generate(using: filenameGen())
        let data = composer.generate(using: binaryDataGen())
        let mime = composer.generate(using: optionalMimeGen())
        let useExplicitSize = composer.generate(using: Gen<Bool>.pure(false))
        let explicitSize: Int32? = useExplicitSize ? Int32(data.count) : nil
        return GeneratedAttachment(
            longFilename: longName,
            shortFilename: shortName,
            binaryData: data,
            mimeType: mime,
            explicitSize: explicitSize
        )
    }
}

/// Generates an attachment with only a short filename (tests fallback).
private func attachmentWithOnlyShortFilenameGen() -> Gen<GeneratedAttachment> {
    return Gen<GeneratedAttachment>.compose { composer in
        let shortName = composer.generate(using: filenameGen())
        let data = composer.generate(using: binaryDataGen())
        let mime = composer.generate(using: optionalMimeGen())
        return GeneratedAttachment(
            longFilename: nil,
            shortFilename: shortName,
            binaryData: data,
            mimeType: mime,
            explicitSize: nil
        )
    }
}

/// Generates an attachment with valid binary data (tests data identity and isCorrupted=false).
private func attachmentWithValidDataGen() -> Gen<GeneratedAttachment> {
    return Gen<GeneratedAttachment>.compose { composer in
        let longName = composer.generate(using: filenameGen())
        let data = composer.generate(using: binaryDataGen())
        let mime = composer.generate(using: optionalMimeGen())
        let useExplicitSize = composer.generate(using: Gen<Bool>.frequency([(1, Gen.pure(true)), (1, Gen.pure(false))]))
        let explicitSize: Int32? = useExplicitSize ? Int32(data.count) : nil
        return GeneratedAttachment(
            longFilename: longName,
            shortFilename: nil,
            binaryData: data,
            mimeType: mime,
            explicitSize: explicitSize
        )
    }
}

/// Generates an attachment without binary data (tests isCorrupted=true, data=nil).
private func attachmentWithoutDataGen() -> Gen<GeneratedAttachment> {
    return Gen<GeneratedAttachment>.compose { composer in
        let longName = composer.generate(using: filenameGen())
        let mime = composer.generate(using: optionalMimeGen())
        return GeneratedAttachment(
            longFilename: longName,
            shortFilename: nil,
            binaryData: nil,
            mimeType: mime,
            explicitSize: nil
        )
    }
}

/// Generates an attachment with explicit size property set.
private func attachmentWithExplicitSizeGen() -> Gen<GeneratedAttachment> {
    return Gen<GeneratedAttachment>.compose { composer in
        let longName = composer.generate(using: filenameGen())
        let data = composer.generate(using: binaryDataGen())
        let mime = composer.generate(using: optionalMimeGen())
        let explicitSize = Int32(data.count)
        return GeneratedAttachment(
            longFilename: longName,
            shortFilename: nil,
            binaryData: data,
            mimeType: mime,
            explicitSize: explicitSize
        )
    }
}

// MARK: - Arbitrary Conformance

extension GeneratedAttachment: Arbitrary {
    static var arbitrary: Gen<GeneratedAttachment> {
        return Gen<GeneratedAttachment>.frequency([
            (2, attachmentWithBothFilenamesGen()),
            (2, attachmentWithOnlyShortFilenameGen()),
            (2, attachmentWithValidDataGen()),
            (2, attachmentWithoutDataGen()),
            (1, attachmentWithExplicitSizeGen())
        ])
    }
}

// MARK: - Tests

/// **Validates: Requirements 4.1, 4.2, 4.3, 4.6, 4.7**
final class AttachmentExtractionPropertyTests: XCTestCase {

    // MARK: - Property 9: Attachment Extraction Round-Trip

    /// Verifies that long filename is preferred over short filename.
    /// **Validates: Requirements 4.1, 4.2**
    func testAttachmentFilenamePrefersLongOverShort() {
        property("Long filename is preferred over short filename") <- forAll(attachmentWithBothFilenamesGen()) { (generated: GeneratedAttachment) in
            let streams = generated.buildStreams()

            guard let attachments = try? MAPIPropertyExtractor.extractAttachments(
                from: [streams],
                codePage: nil
            ) else {
                return false
            }

            guard attachments.count == 1 else { return false }
            let attachment = attachments[0]

            // Long filename should be preferred
            return attachment.filename == generated.longFilename
        }
    }

    /// Verifies that short filename is used when long filename is absent.
    /// **Validates: Requirements 4.1, 4.2**
    func testAttachmentFilenameUsesShortWhenLongAbsent() {
        property("Short filename is used when long filename is absent") <- forAll(attachmentWithOnlyShortFilenameGen()) { (generated: GeneratedAttachment) in
            let streams = generated.buildStreams()

            guard let attachments = try? MAPIPropertyExtractor.extractAttachments(
                from: [streams],
                codePage: nil
            ) else {
                return false
            }

            guard attachments.count == 1 else { return false }
            let attachment = attachments[0]

            return attachment.filename == generated.shortFilename
        }
    }

    /// Verifies that extracted binary data is identical to original and isCorrupted = false.
    /// **Validates: Requirements 4.3, 4.7**
    func testAttachmentDataIdentityAndNotCorrupted() {
        property("Binary data is identical to original and not corrupted") <- forAll(attachmentWithValidDataGen()) { (generated: GeneratedAttachment) in
            let streams = generated.buildStreams()

            guard let attachments = try? MAPIPropertyExtractor.extractAttachments(
                from: [streams],
                codePage: nil
            ) else {
                return false
            }

            guard attachments.count == 1 else { return false }
            let attachment = attachments[0]

            // Data must match exactly
            guard attachment.data == generated.binaryData else { return false }
            // Must not be corrupted
            guard attachment.isCorrupted == false else { return false }

            return true
        }
    }

    /// Verifies that missing binary data produces isCorrupted = true with nil data.
    /// **Validates: Requirements 4.6, 4.7**
    func testMissingBinaryDataProducesCorrupted() {
        property("Missing binary data marks attachment as corrupted with nil data") <- forAll(attachmentWithoutDataGen()) { (generated: GeneratedAttachment) in
            let streams = generated.buildStreams()

            guard let attachments = try? MAPIPropertyExtractor.extractAttachments(
                from: [streams],
                codePage: nil
            ) else {
                return false
            }

            guard attachments.count == 1 else { return false }
            let attachment = attachments[0]

            // Should be corrupted
            guard attachment.isCorrupted == true else { return false }
            // Data should be nil
            guard attachment.data == nil else { return false }

            return true
        }
    }

    /// Verifies that MIME type is correctly extracted when present, nil when absent.
    /// **Validates: Requirements 4.1, 4.2**
    func testAttachmentMimeTypeExtraction() {
        property("MIME type matches generated value or is nil when absent") <- forAll(GeneratedAttachment.arbitrary) { (generated: GeneratedAttachment) in
            let streams = generated.buildStreams()

            guard let attachments = try? MAPIPropertyExtractor.extractAttachments(
                from: [streams],
                codePage: nil
            ) else {
                return false
            }

            guard attachments.count == 1 else { return false }
            let attachment = attachments[0]

            return attachment.mimeType == generated.mimeType
        }
    }

    /// Verifies that size matches PidTagAttachSize if present, or data.count otherwise.
    /// **Validates: Requirements 4.3**
    func testAttachmentSizeMatchesExpected() {
        property("Size matches explicit PidTagAttachSize or data.count") <- forAll(GeneratedAttachment.arbitrary) { (generated: GeneratedAttachment) in
            let streams = generated.buildStreams()

            guard let attachments = try? MAPIPropertyExtractor.extractAttachments(
                from: [streams],
                codePage: nil
            ) else {
                return false
            }

            guard attachments.count == 1 else { return false }
            let attachment = attachments[0]

            return attachment.size == generated.expectedSize
        }
    }
}
