// MSGParserTests - Property-based tests for recipient extraction completeness
// Feature: msg-file-viewer, Property 5: Recipient Extraction Completeness

import XCTest
import SwiftCheck
import Foundation
@testable import MSGParser

// MARK: - Helpers

/// Encodes a string as UTF-16LE Data (for PT_UNICODE substg streams).
private func encodeUTF16LE(_ string: String) -> Data {
    return string.data(using: .utf16LittleEndian) ?? Data()
}

/// Builds a 16-byte property entry: [type:UInt16][id:UInt16][flags:UInt32][value:8 bytes]
private func buildPropertyEntry(type: UInt16, id: UInt16, int32Value: Int32) -> Data {
    var entry = Data(count: 16)
    // Type (UInt16 little-endian) at offset 0
    entry[0] = UInt8(type & 0xFF)
    entry[1] = UInt8((type >> 8) & 0xFF)
    // ID (UInt16 little-endian) at offset 2
    entry[2] = UInt8(id & 0xFF)
    entry[3] = UInt8((id >> 8) & 0xFF)
    // Flags (UInt32 little-endian) at offset 4
    entry[4] = 0; entry[5] = 0; entry[6] = 0; entry[7] = 0
    // Value (8 bytes) at offset 8 - first 4 bytes are the int32 value
    var valueLE = int32Value.littleEndian
    withUnsafeBytes(of: &valueLE) { bytes in
        for i in 0..<4 {
            entry[8 + i] = bytes[i]
        }
    }
    // Remaining 4 bytes are zero (padding)
    entry[12] = 0; entry[13] = 0; entry[14] = 0; entry[15] = 0
    return entry
}

/// Builds a recipient sub-storage streams dictionary from given parameters.
/// Uses an 8-byte header (sub-storage format) for the property stream.
private func buildRecipientStreams(
    displayName: String,
    emailAddress: String,
    recipientType: Int32
) -> [String: Data] {
    var streams = [String: Data]()
    var propertyStream = Data()

    // 8-byte header for sub-storage (reserved bytes)
    propertyStream.append(contentsOf: [UInt8](repeating: 0, count: 8))

    // RecipientType property entry (PT_LONG = 0x0003, id = 0x0C15)
    let recipientTypeEntry = buildPropertyEntry(type: 0x0003, id: 0x0C15, int32Value: recipientType)
    propertyStream.append(recipientTypeEntry)

    // DisplayName property entry (PT_UNICODE = 0x001F, id = 0x3001)
    let displayNameEntry = buildPropertyEntry(type: 0x001F, id: 0x3001, int32Value: 0)
    propertyStream.append(displayNameEntry)
    streams["__substg1.0_3001001F"] = encodeUTF16LE(displayName)

    // EmailAddress property entry (PT_UNICODE = 0x001F, id = 0x3003)
    let emailEntry = buildPropertyEntry(type: 0x001F, id: 0x3003, int32Value: 0)
    propertyStream.append(emailEntry)
    streams["__substg1.0_3003001F"] = encodeUTF16LE(emailAddress)

    streams["__properties_version1.0"] = propertyStream
    return streams
}

// MARK: - Generated Recipient Model

/// Represents a single generated recipient for property testing.
struct GeneratedRecipient {
    let displayName: String
    let emailAddress: String
    /// 1 = TO, 2 = CC
    let recipientType: Int32
}

extension GeneratedRecipient: Arbitrary {
    static var arbitrary: Gen<GeneratedRecipient> {
        return recipientGen()
    }
}

// MARK: - Generators

/// Generates a non-empty string of lowercase ASCII characters (safe for UTF-16LE encoding).
private func safeStringGen() -> Gen<String> {
    let charGen = Gen<Character>.fromElements(in: "a"..."z")
    return Gen<[Character]>.compose { composer in
        let length = composer.generate(using: Gen<Int>.choose((1, 30)))
        return (0..<length).map { _ in composer.generate(using: charGen) }
    }.map { String($0) }
}

/// Generates a safe email-like string (localpart@domain.com).
private func safeEmailGen() -> Gen<String> {
    return Gen<String>.compose { composer in
        let local = composer.generate(using: safeStringGen())
        let domain = composer.generate(using: safeStringGen())
        return "\(local)@\(domain).com"
    }
}

/// Generates a recipient type: 1 (TO) or 2 (CC).
private func recipientTypeGen() -> Gen<Int32> {
    return Gen<Int32>.fromElements(of: [1, 2])
}

/// Generates a single GeneratedRecipient.
private func recipientGen() -> Gen<GeneratedRecipient> {
    return Gen<GeneratedRecipient>.compose { composer in
        let name = composer.generate(using: safeStringGen())
        let email = composer.generate(using: safeEmailGen())
        let type = composer.generate(using: recipientTypeGen())
        return GeneratedRecipient(displayName: name, emailAddress: email, recipientType: type)
    }
}

/// Generates an array of 1-20 recipients.
private func recipientListGen() -> Gen<[GeneratedRecipient]> {
    return Gen<[GeneratedRecipient]>.compose { composer in
        let count = composer.generate(using: Gen<Int>.choose((1, 20)))
        return (0..<count).map { _ in composer.generate(using: recipientGen()) }
    }
}

// MARK: - Tests

/// **Validates: Requirements 2.3, 2.4, 2.8**
final class RecipientExtractionPropertyTests: XCTestCase {

    // MARK: - Property 5: Recipient Extraction Completeness

    /// **Validates: Requirements 2.3, 2.4, 2.8**
    /// For any set of N recipients (of type TO or CC) encoded into recipient sub-storages,
    /// the extractor SHALL return exactly N recipients of the correct type, each with their
    /// original display name and email address preserved.
    func testRecipientExtractionCompleteness() {
        property("Extracted recipients match generated recipients in count, type, name, and email") <- forAll(recipientListGen()) { (recipients: [GeneratedRecipient]) in
            // Build the array of stream dictionaries
            let recipientStreams: [[String: Data]] = recipients.map { recipient in
                buildRecipientStreams(
                    displayName: recipient.displayName,
                    emailAddress: recipient.emailAddress,
                    recipientType: recipient.recipientType
                )
            }

            // Extract recipients using MAPIPropertyExtractor
            guard let extracted = try? MAPIPropertyExtractor.extractRecipients(from: recipientStreams) else {
                return false
            }

            // Verify exactly N recipients returned
            guard extracted.count == recipients.count else { return false }

            // Verify each recipient has correct type, displayName, and emailAddress
            for (index, generated) in recipients.enumerated() {
                let result = extracted[index]

                // Verify type
                let expectedType: RecipientType = generated.recipientType == 1 ? .to : .cc
                guard result.type == expectedType else { return false }

                // Verify displayName preserved
                guard result.displayName == generated.displayName else { return false }

                // Verify emailAddress preserved
                guard result.emailAddress == generated.emailAddress else { return false }
            }

            return true
        }
    }
}
