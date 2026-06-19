// MSGParserTests - Property-based tests for MAPI property extraction round-trip
// Feature: msg-file-viewer, Property 4: MAPI Property Extraction Round-Trip

import XCTest
import SwiftCheck
import Foundation
@testable import MSGParser

// MARK: - Helpers

/// FILETIME epoch offset: seconds between 1601-01-01 and 1970-01-01.
private let filetimeEpochOffset: Double = 11_644_473_600

/// 100-nanosecond intervals per second.
private let filetimeIntervalsPerSecond: Double = 10_000_000

/// Converts a Date to a FILETIME UInt64 value.
private func dateToFileTime(_ date: Date) -> UInt64 {
    let seconds = date.timeIntervalSince1970 + filetimeEpochOffset
    return UInt64(seconds * filetimeIntervalsPerSecond)
}

/// Converts a FILETIME UInt64 back to a Date (for comparison).
private func fileTimeToDate(_ fileTime: UInt64) -> Date {
    let seconds = Double(fileTime) / filetimeIntervalsPerSecond - filetimeEpochOffset
    return Date(timeIntervalSince1970: seconds)
}

/// Encodes a string as UTF-16LE Data (for PT_UNICODE substg streams).
private func encodeUTF16LE(_ string: String) -> Data {
    return string.data(using: .utf16LittleEndian) ?? Data()
}

/// Builds a property stream entry (16 bytes): [type:UInt16][id:UInt16][flags:UInt32][value:8 bytes]
private func buildPropertyEntry(type: UInt16, id: UInt16, flags: UInt32 = 0x00000002, value: Data) -> Data {
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
    let valueBytes = value + Data(count: max(0, 8 - value.count))
    for i in 0..<8 {
        entry[8 + i] = valueBytes[i]
    }
    return entry
}

/// Builds a UInt64 value as 8 bytes in little-endian.
private func uint64LEData(_ value: UInt64) -> Data {
    var v = value.littleEndian
    return Data(bytes: &v, count: 8)
}

/// Builds a UInt32 value as 4 bytes in little-endian (padded to 8 for value area).
private func uint32LEData(_ value: UInt32) -> Data {
    var v = value.littleEndian
    return Data(bytes: &v, count: 4)
}

/// Generates the substg stream name for a property.
private func substgStreamName(propertyID: UInt16, type: UInt16) -> String {
    let idHex = String(format: "%04X", propertyID)
    let typeHex = String(format: "%04X", type)
    return "__substg1.0_\(idHex)\(typeHex)"
}

/// Represents a generated set of MAPI properties for testing.
struct GeneratedMAPIProperties {
    let subject: String?
    let senderName: String?
    let senderEmail: String?
    let sentDate: Date?

    /// Builds the streams dictionary that MAPIPropertyExtractor.extractProperties expects.
    func buildStreams() -> [String: Data] {
        var streams = [String: Data]()

        // Root header: 32 bytes of zeros
        var propertyStream = Data(count: 32)

        // Add each present property as a 16-byte entry + substg stream

        if let subject = subject {
            let type: UInt16 = 0x001F  // PT_UNICODE
            let id: UInt16 = 0x0037    // PidTagSubject
            let encoded = encodeUTF16LE(subject)
            let sizeData = uint32LEData(UInt32(encoded.count))
            let entry = buildPropertyEntry(type: type, id: id, value: sizeData)
            propertyStream.append(entry)
            streams[substgStreamName(propertyID: id, type: type)] = encoded
        }

        if let senderName = senderName {
            let type: UInt16 = 0x001F  // PT_UNICODE
            let id: UInt16 = 0x0C1A    // PidTagSenderName
            let encoded = encodeUTF16LE(senderName)
            let sizeData = uint32LEData(UInt32(encoded.count))
            let entry = buildPropertyEntry(type: type, id: id, value: sizeData)
            propertyStream.append(entry)
            streams[substgStreamName(propertyID: id, type: type)] = encoded
        }

        if let senderEmail = senderEmail {
            let type: UInt16 = 0x001F  // PT_UNICODE
            let id: UInt16 = 0x0C1F    // PidTagSenderEmailAddress
            let encoded = encodeUTF16LE(senderEmail)
            let sizeData = uint32LEData(UInt32(encoded.count))
            let entry = buildPropertyEntry(type: type, id: id, value: sizeData)
            propertyStream.append(entry)
            streams[substgStreamName(propertyID: id, type: type)] = encoded
        }

        if let sentDate = sentDate {
            let type: UInt16 = 0x0040  // PT_SYSTIME
            let id: UInt16 = 0x0039    // PidTagClientSubmitTime
            let fileTime = dateToFileTime(sentDate)
            let valueData = uint64LEData(fileTime)
            let entry = buildPropertyEntry(type: type, id: id, value: valueData)
            propertyStream.append(entry)
        }

        streams["__properties_version1.0"] = propertyStream
        return streams
    }
}

// MARK: - Arbitrary Conformance

extension GeneratedMAPIProperties: Arbitrary {
    static var arbitrary: Gen<GeneratedMAPIProperties> {
        return generatedPropertiesGen()
    }
}

// MARK: - Generators

/// Generates a non-empty ASCII-safe string suitable for email subjects/names.
/// We restrict to printable ASCII to avoid encoding edge cases unrelated to this test.
private func safeStringGen() -> Gen<String> {
    let charGen = Gen<Character>.fromElements(in: "a"..."z")
    return Gen<[Character]>.compose { composer in
        let length = composer.generate(using: Gen<Int>.choose((1, 50)))
        return (0..<length).map { _ in composer.generate(using: charGen) }
    }.map { String($0) }
}

/// Generates an optional safe string.
private func optionalSafeStringGen() -> Gen<String?> {
    return Gen<String?>.frequency([
        (1, Gen.pure(nil)),
        (3, safeStringGen().map { Optional($0) })
    ])
}

/// Generates an optional Date within a reasonable range (year 2000-2024).
/// The date is rounded to second precision since FILETIME has 100ns granularity
/// and we compare at second-level precision.
private func optionalDateGen() -> Gen<Date?> {
    // Unix timestamps for 2000-01-01 to 2024-12-31
    let minTimestamp: Int = 946_684_800   // 2000-01-01
    let maxTimestamp: Int = 1_735_689_600  // 2024-12-31
    return Gen<Date?>.frequency([
        (1, Gen.pure(nil)),
        (3, Gen<Int>.choose((minTimestamp, maxTimestamp)).map { ts in
            Optional(Date(timeIntervalSince1970: TimeInterval(ts)))
        })
    ])
}

/// Generates a `GeneratedMAPIProperties` with random presence/absence of each field.
func generatedPropertiesGen() -> Gen<GeneratedMAPIProperties> {
    return Gen<GeneratedMAPIProperties>.compose { composer in
        let subject = composer.generate(using: optionalSafeStringGen())
        let senderName = composer.generate(using: optionalSafeStringGen())
        let senderEmail = composer.generate(using: optionalSafeStringGen())
        let sentDate = composer.generate(using: optionalDateGen())
        return GeneratedMAPIProperties(
            subject: subject,
            senderName: senderName,
            senderEmail: senderEmail,
            sentDate: sentDate
        )
    }
}

// MARK: - Tests

/// **Validates: Requirements 2.1, 2.2, 2.5, 2.6, 2.7**
final class MAPIPropertyExtractionPropertyTests: XCTestCase {

    // MARK: - Property 4: MAPI Property Extraction Round-Trip

    /// **Validates: Requirements 2.1, 2.2, 2.5, 2.6, 2.7**
    /// For any set of MAPI properties (subject, sender name, sender email, sent date) encoded
    /// into a valid property stream, extracting those properties produces values identical to
    /// the originals. Missing properties produce nil without affecting extraction of others.
    func testMAPIPropertyExtractionRoundTrip() {
        property("Extracted MAPI properties match generated originals") <- forAll(generatedPropertiesGen()) { (generated: GeneratedMAPIProperties) in
            let streams = generated.buildStreams()

            guard let properties = try? MAPIPropertyExtractor.extractProperties(
                from: streams,
                codePage: nil,
                isRootStorage: true
            ) else {
                // Extraction should not throw for well-formed streams
                return false
            }

            // Helper to find a property value by tag
            func findString(id: UInt16, type: UInt16) -> String? {
                let tag = MAPIPropertyTag(id: id, type: type)
                guard let prop = properties.first(where: { $0.tag == tag }) else { return nil }
                if case .string(let s) = prop.value { return s }
                return nil
            }

            func findDate(id: UInt16, type: UInt16) -> Date? {
                let tag = MAPIPropertyTag(id: id, type: type)
                guard let prop = properties.first(where: { $0.tag == tag }) else { return nil }
                if case .time(let d) = prop.value { return d }
                return nil
            }

            // Verify subject
            let extractedSubject = findString(id: 0x0037, type: 0x001F)
            guard extractedSubject == generated.subject else { return false }

            // Verify sender name
            let extractedSenderName = findString(id: 0x0C1A, type: 0x001F)
            guard extractedSenderName == generated.senderName else { return false }

            // Verify sender email
            let extractedSenderEmail = findString(id: 0x0C1F, type: 0x001F)
            guard extractedSenderEmail == generated.senderEmail else { return false }

            // Verify sent date (compare at second precision due to FILETIME rounding)
            let extractedDate = findDate(id: 0x0039, type: 0x0040)
            if let genDate = generated.sentDate {
                guard let extDate = extractedDate else { return false }
                // Compare at 1-second precision (FILETIME conversion may lose sub-second precision)
                let diff = abs(genDate.timeIntervalSince1970 - extDate.timeIntervalSince1970)
                guard diff < 1.0 else { return false }
            } else {
                guard extractedDate == nil else { return false }
            }

            return true
        }
    }

    /// **Validates: Requirements 2.1, 2.2, 2.5, 2.6, 2.7**
    /// Verify that missing properties produce nil without affecting extraction of present properties.
    /// When some properties are absent, the extractor still correctly extracts remaining ones.
    func testMissingPropertiesProduceNilWithoutAffectingOthers() {
        property("Missing properties are nil without affecting other property extraction") <- forAll(generatedPropertiesGen()) { (generated: GeneratedMAPIProperties) in
            let streams = generated.buildStreams()

            guard let properties = try? MAPIPropertyExtractor.extractProperties(
                from: streams,
                codePage: nil,
                isRootStorage: true
            ) else {
                return false
            }

            // Count how many properties we expect to be extracted
            var expectedCount = 0
            if generated.subject != nil { expectedCount += 1 }
            if generated.senderName != nil { expectedCount += 1 }
            if generated.senderEmail != nil { expectedCount += 1 }
            if generated.sentDate != nil { expectedCount += 1 }

            // The number of extracted properties should match
            // (only the properties we put in the stream should be extracted)
            guard properties.count == expectedCount else { return false }

            // Verify absent properties are truly not in the result
            func hasProperty(id: UInt16, type: UInt16) -> Bool {
                let tag = MAPIPropertyTag(id: id, type: type)
                return properties.contains(where: { $0.tag == tag })
            }

            if generated.subject == nil {
                guard !hasProperty(id: 0x0037, type: 0x001F) else { return false }
            }
            if generated.senderName == nil {
                guard !hasProperty(id: 0x0C1A, type: 0x001F) else { return false }
            }
            if generated.senderEmail == nil {
                guard !hasProperty(id: 0x0C1F, type: 0x001F) else { return false }
            }
            if generated.sentDate == nil {
                guard !hasProperty(id: 0x0039, type: 0x0040) else { return false }
            }

            return true
        }
    }
}
