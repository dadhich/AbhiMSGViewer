// Tests for MAPIPropertyExtractor.extractRecipients

import XCTest
@testable import MSGParser

final class RecipientExtractionTests: XCTestCase {

    // MARK: - Helper: Build a recipient sub-storage streams dictionary

    /// Builds a minimal streams dictionary for a recipient sub-storage.
    /// The property stream uses an 8-byte header (sub-storage format).
    ///
    /// Each property entry is 16 bytes: [type:UInt16][id:UInt16][flags:UInt32][value:8 bytes]
    /// For fixed-length types (PT_LONG), the value is inline.
    /// For variable-length types (PT_UNICODE), the value references a substg stream.
    private func buildRecipientStreams(
        displayName: String? = nil,
        emailAddress: String? = nil,
        recipientType: Int32 = 1
    ) -> [String: Data] {
        var streams = [String: Data]()
        var propertyStream = Data()

        // 8-byte header for sub-storage (reserved bytes)
        propertyStream.append(contentsOf: [UInt8](repeating: 0, count: 8))

        // Add recipientType property entry (PT_LONG = 0x0003, id = 0x0C15)
        appendPropertyEntry(
            to: &propertyStream,
            type: 0x0003,
            id: 0x0C15,
            int32Value: recipientType
        )

        // Add displayName property entry (PT_UNICODE = 0x001F, id = 0x3001)
        if let name = displayName {
            appendPropertyEntry(
                to: &propertyStream,
                type: 0x001F,
                id: 0x3001,
                int32Value: 0 // placeholder for variable-length; actual data in substg
            )
            // Store the actual string in the substg stream
            let streamName = "__substg1.0_3001001F"
            streams[streamName] = name.data(using: .utf16LittleEndian)!
        }

        // Add emailAddress property entry (PT_UNICODE = 0x001F, id = 0x3003)
        if let email = emailAddress {
            appendPropertyEntry(
                to: &propertyStream,
                type: 0x001F,
                id: 0x3003,
                int32Value: 0 // placeholder for variable-length
            )
            let streamName = "__substg1.0_3003001F"
            streams[streamName] = email.data(using: .utf16LittleEndian)!
        }

        streams["__properties_version1.0"] = propertyStream
        return streams
    }

    /// Appends a 16-byte property entry to a property stream.
    private func appendPropertyEntry(
        to data: inout Data,
        type: UInt16,
        id: UInt16,
        int32Value: Int32
    ) {
        // type (2 bytes, little-endian)
        var typeLE = type.littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &typeLE) { Array($0) })

        // id (2 bytes, little-endian)
        var idLE = id.littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &idLE) { Array($0) })

        // flags (4 bytes)
        data.append(contentsOf: [UInt8](repeating: 0, count: 4))

        // value (8 bytes, first 4 are the int32 value)
        var valueLE = int32Value.littleEndian
        data.append(contentsOf: withUnsafeBytes(of: &valueLE) { Array($0) })
        data.append(contentsOf: [UInt8](repeating: 0, count: 4)) // padding
    }

    // MARK: - Tests

    func testExtractSingleToRecipient() throws {
        let streams = buildRecipientStreams(
            displayName: "Alice Smith",
            emailAddress: "alice@example.com",
            recipientType: 1
        )

        let recipients = try MAPIPropertyExtractor.extractRecipients(from: [streams])

        XCTAssertEqual(recipients.count, 1)
        XCTAssertEqual(recipients[0].displayName, "Alice Smith")
        XCTAssertEqual(recipients[0].emailAddress, "alice@example.com")
        XCTAssertEqual(recipients[0].type, .to)
    }

    func testExtractCCRecipient() throws {
        let streams = buildRecipientStreams(
            displayName: "Bob Jones",
            emailAddress: "bob@example.com",
            recipientType: 2
        )

        let recipients = try MAPIPropertyExtractor.extractRecipients(from: [streams])

        XCTAssertEqual(recipients.count, 1)
        XCTAssertEqual(recipients[0].type, .cc)
    }

    func testExtractBCCRecipient() throws {
        let streams = buildRecipientStreams(
            displayName: "Charlie",
            emailAddress: "charlie@example.com",
            recipientType: 3
        )

        let recipients = try MAPIPropertyExtractor.extractRecipients(from: [streams])

        XCTAssertEqual(recipients.count, 1)
        XCTAssertEqual(recipients[0].type, .bcc)
    }

    func testExtractMultipleRecipients() throws {
        let toStreams = buildRecipientStreams(
            displayName: "Alice",
            emailAddress: "alice@example.com",
            recipientType: 1
        )
        let ccStreams = buildRecipientStreams(
            displayName: "Bob",
            emailAddress: "bob@example.com",
            recipientType: 2
        )
        let bccStreams = buildRecipientStreams(
            displayName: "Charlie",
            emailAddress: "charlie@example.com",
            recipientType: 3
        )

        let recipients = try MAPIPropertyExtractor.extractRecipients(
            from: [toStreams, ccStreams, bccStreams]
        )

        XCTAssertEqual(recipients.count, 3)
        XCTAssertEqual(recipients[0].type, .to)
        XCTAssertEqual(recipients[1].type, .cc)
        XCTAssertEqual(recipients[2].type, .bcc)
    }

    func testExtractEmptyRecipientList() throws {
        let recipients = try MAPIPropertyExtractor.extractRecipients(from: [])
        XCTAssertEqual(recipients.count, 0)
    }

    func testRecipientWithMissingDisplayName() throws {
        let streams = buildRecipientStreams(
            displayName: nil,
            emailAddress: "noname@example.com",
            recipientType: 1
        )

        let recipients = try MAPIPropertyExtractor.extractRecipients(from: [streams])

        XCTAssertEqual(recipients.count, 1)
        XCTAssertNil(recipients[0].displayName)
        XCTAssertEqual(recipients[0].emailAddress, "noname@example.com")
    }

    func testRecipientWithMissingEmailAddress() throws {
        let streams = buildRecipientStreams(
            displayName: "No Email",
            emailAddress: nil,
            recipientType: 1
        )

        let recipients = try MAPIPropertyExtractor.extractRecipients(from: [streams])

        XCTAssertEqual(recipients.count, 1)
        XCTAssertEqual(recipients[0].displayName, "No Email")
        XCTAssertNil(recipients[0].emailAddress)
    }

    func testUnknownRecipientTypeDefaultsToTO() throws {
        let streams = buildRecipientStreams(
            displayName: "Unknown Type",
            emailAddress: "unknown@example.com",
            recipientType: 99 // Invalid type
        )

        let recipients = try MAPIPropertyExtractor.extractRecipients(from: [streams])

        XCTAssertEqual(recipients.count, 1)
        XCTAssertEqual(recipients[0].type, .to) // Defaults to TO
    }

    func testHandleLargeRecipientCount() throws {
        // Verify 1000+ recipients without truncation
        let count = 1050
        var allStreams = [[String: Data]]()
        allStreams.reserveCapacity(count)

        for i in 0..<count {
            let streams = buildRecipientStreams(
                displayName: "Recipient \(i)",
                emailAddress: "recipient\(i)@example.com",
                recipientType: 1
            )
            allStreams.append(streams)
        }

        let recipients = try MAPIPropertyExtractor.extractRecipients(from: allStreams)

        XCTAssertEqual(recipients.count, count)
        // Verify first and last to ensure no truncation
        XCTAssertEqual(recipients[0].displayName, "Recipient 0")
        XCTAssertEqual(recipients[count - 1].displayName, "Recipient \(count - 1)")
    }
}
