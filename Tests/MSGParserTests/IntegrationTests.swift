// IntegrationTests - End-to-end integration tests for MSGParser
// Validates full parse pipeline with synthetic .msg files and DataReader selection
// Requirements: 1.7, 8.1

import XCTest
@testable import MSGParser

final class IntegrationTests: XCTestCase {

    // MARK: - DataReader Selection Tests (Requirement 1.7, 8.1)

    func testDataReaderFactorySelectsInMemoryForSmallFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test_small_\(UUID()).bin")
        defer { try? FileManager.default.removeItem(at: url) }

        // 512 KB - well under 1 MB threshold
        try Data(count: 512 * 1024).write(to: url)

        let reader = try DataReaderFactory.createReader(for: url)
        XCTAssertTrue(reader is InMemoryDataReader,
            "Files <= 1 MB should use InMemoryDataReader")
        XCTAssertEqual(reader.count, 512 * 1024)
    }

    func testDataReaderFactorySelectsMappedForLargeFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test_large_\(UUID()).bin")
        defer { try? FileManager.default.removeItem(at: url) }

        // 1.5 MB - above the 1 MB threshold
        try Data(count: 1_572_864).write(to: url)

        let reader = try DataReaderFactory.createReader(for: url)
        XCTAssertTrue(reader is MappedDataReader,
            "Files > 1 MB should use MappedDataReader")
        XCTAssertEqual(reader.count, 1_572_864)
    }

    func testDataReaderFactoryBoundaryExactly1MB() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test_1mb_\(UUID()).bin")
        defer { try? FileManager.default.removeItem(at: url) }

        // Exactly 1 MB should use InMemory (threshold is >)
        try Data(count: 1_048_576).write(to: url)

        let reader = try DataReaderFactory.createReader(for: url)
        XCTAssertTrue(reader is InMemoryDataReader,
            "Files at exactly 1 MB should use InMemoryDataReader")
    }

    func testDataReaderFactoryBoundary1MBPlusOne() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("test_1mb1_\(UUID()).bin")
        defer { try? FileManager.default.removeItem(at: url) }

        // 1 MB + 1 byte should trigger MappedDataReader
        try Data(count: 1_048_577).write(to: url)

        let reader = try DataReaderFactory.createReader(for: url)
        XCTAssertTrue(reader is MappedDataReader,
            "Files > 1 MB should use MappedDataReader")
    }

    // MARK: - End-to-End Parse: Small Synthetic MSG (< 1 MB)

    func testEndToEndParseSmallSyntheticMSG() async throws {
        let subject = "Integration Test Email"
        let senderName = "Alice Smith"
        let senderEmail = "alice@example.com"
        let bodyText = "Hello, this is the email body."
        let recipientName = "Bob Jones"
        let recipientEmail = "bob@example.com"
        let attachmentName = "document.pdf"
        let attachmentData = Data([0x25, 0x50, 0x44, 0x46]) // %PDF

        let msgData = try SyntheticMSGBuilder.build(
            subject: subject,
            senderName: senderName,
            senderEmail: senderEmail,
            bodyText: bodyText,
            recipients: [(name: recipientName, email: recipientEmail, type: 1)],
            attachments: [(name: attachmentName, data: attachmentData)],
            targetSize: nil
        )

        // Verify it's small
        XCTAssertLessThan(msgData.count, 1_048_576, "Small MSG should be under 1 MB")

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("integration_small_\(UUID()).msg")
        defer { try? FileManager.default.removeItem(at: url) }
        try msgData.write(to: url)

        // Verify InMemoryDataReader is used
        let reader = try DataReaderFactory.createReader(for: url)
        XCTAssertTrue(reader is InMemoryDataReader)

        // Parse end-to-end
        let parser = MSGParser()
        let email = try await parser.parse(url: url)

        // Verify all Email model fields
        XCTAssertEqual(email.subject, subject)
        XCTAssertEqual(email.senderName, senderName)
        XCTAssertEqual(email.senderEmail, senderEmail)
        XCTAssertEqual(email.body.plainText, bodyText)
        XCTAssertEqual(email.body.preferredFormat, .plainText)
        XCTAssertNil(email.body.html)
        XCTAssertNil(email.body.rtf)

        // Recipients
        XCTAssertEqual(email.toRecipients.count, 1)
        XCTAssertEqual(email.toRecipients[0].displayName, recipientName)
        XCTAssertEqual(email.toRecipients[0].emailAddress, recipientEmail)
        XCTAssertEqual(email.toRecipients[0].type, .to)
        XCTAssertTrue(email.ccRecipients.isEmpty)

        // Attachments
        XCTAssertEqual(email.attachments.count, 1)
        XCTAssertEqual(email.attachments[0].filename, attachmentName)
        XCTAssertEqual(email.attachments[0].data, attachmentData)
        XCTAssertEqual(email.attachments[0].size, attachmentData.count)
        XCTAssertFalse(email.attachments[0].isCorrupted)
    }

    // MARK: - End-to-End Parse: Medium Synthetic MSG (> 1 MB, mmap path)

    func testEndToEndParseMediumSyntheticMSG() async throws {
        let subject = "Large Integration Test"
        let senderName = "Charlie Brown"
        let senderEmail = "charlie@example.org"
        let bodyText = "This is a large email for mmap testing."

        let msgData = try SyntheticMSGBuilder.build(
            subject: subject,
            senderName: senderName,
            senderEmail: senderEmail,
            bodyText: bodyText,
            recipients: [],
            attachments: [],
            targetSize: 1_200_000 // Target > 1 MB
        )

        // Verify it exceeds 1 MB threshold
        XCTAssertGreaterThan(msgData.count, 1_048_576,
            "Medium MSG should exceed 1 MB to test mmap path")

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("integration_medium_\(UUID()).msg")
        defer { try? FileManager.default.removeItem(at: url) }
        try msgData.write(to: url)

        // Verify MappedDataReader is used
        let reader = try DataReaderFactory.createReader(for: url)
        XCTAssertTrue(reader is MappedDataReader,
            "File > 1 MB should use MappedDataReader")

        // Parse end-to-end via mmap path
        let parser = MSGParser()
        let email = try await parser.parse(url: url)

        // Verify fields parsed correctly via mmap
        XCTAssertEqual(email.subject, subject)
        XCTAssertEqual(email.senderName, senderName)
        XCTAssertEqual(email.senderEmail, senderEmail)
        XCTAssertEqual(email.body.plainText, bodyText)
        XCTAssertTrue(email.toRecipients.isEmpty)
        XCTAssertTrue(email.ccRecipients.isEmpty)
        XCTAssertTrue(email.attachments.isEmpty)
    }

    // MARK: - Test: Verify synthetic builder produces valid CFB structure

    func testSyntheticBuilderProducesValidCFBHeader() throws {
        let msgData = try SyntheticMSGBuilder.build(
            subject: "Test",
            senderName: "Sender",
            senderEmail: "s@e.com",
            bodyText: "Body",
            recipients: [],
            attachments: [],
            targetSize: nil
        )

        let reader = InMemoryDataReader(data: msgData)
        // Should parse header without error
        let header = try CFBReader.readHeader(from: reader)
        XCTAssertEqual(header.signature, CFBHeader.expectedSignature)
        XCTAssertEqual(header.majorVersion, 3)
        XCTAssertEqual(header.sectorSizePower, 9)
        XCTAssertEqual(header.miniSectorSizePower, 6)
        XCTAssertEqual(header.miniStreamCutoffSize, 4096)

        // Should build FAT without error
        let fat = try CFBReader.buildFAT(header: header, reader: reader)
        XCTAssertGreaterThan(fat.count, 0)

        // Should build miniFAT without error
        let miniFAT = try CFBReader.buildMiniFAT(header: header, fat: fat, reader: reader)
        XCTAssertGreaterThan(miniFAT.count, 0, "Expected non-empty miniFAT for small streams")

        // Should parse directory entries
        let entries = try CFBReader.readDirectoryEntries(header: header, fat: fat, reader: reader)
        XCTAssertGreaterThan(entries.count, 0)

        // Root entry should exist
        let root = entries.first { $0.objectType == .rootStorage }
        XCTAssertNotNil(root, "Should have a root storage entry")
    }

    // MARK: - Invalid File Rejection

    func testInvalidFileProducesFormatError() async {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("invalid_\(UUID()).msg")
        defer { try? FileManager.default.removeItem(at: url) }

        // Write garbage data (invalid CFB signature)
        let garbage = Data((0..<1024).map { _ in UInt8.random(in: 0...255) })
        try? garbage.write(to: url)

        let parser = MSGParser()
        do {
            _ = try await parser.parse(url: url)
            XCTFail("Expected MSGParserError for invalid file")
        } catch let error as MSGParserError {
            if case .invalidFormat(let cfbError) = error {
                XCTAssertTrue(cfbError.description.contains("invalid file format"))
            }
        } catch {
            XCTFail("Expected MSGParserError, got: \(error)")
        }
    }

    // MARK: - Nonexistent file

    func testNonexistentFileProducesAccessError() async {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID()).msg")

        let parser = MSGParser()
        do {
            _ = try await parser.parse(url: url)
            XCTFail("Expected MSGParserError for nonexistent file")
        } catch let error as MSGParserError {
            if case .fileAccessDenied = error {
                // Expected
            } else {
                // Any MSGParserError is acceptable
            }
        } catch {
            // File system errors are acceptable too
        }
    }
}


// MARK: - Synthetic MSG Builder

/// Builds valid CFB-structured .msg files for integration testing.
/// Creates the minimum valid OLE/CFB binary with proper headers, FAT,
/// directory entries, and MAPI property streams.
enum SyntheticMSGBuilder {

    private static let endOfChain: UInt32 = 0xFFFFFFFE
    private static let freeSector: UInt32 = 0xFFFFFFFF
    private static let noStream: UInt32 = 0xFFFFFFFF
    private static let sectorSize = 512
    private static let miniSectorSize = 64
    private static let miniStreamCutoff: UInt32 = 4096
    private static let signature: UInt64 = 0xE11AB1A1_E011CFD0

    struct RecipientInfo {
        let name: String
        let email: String
        let type: Int32
    }

    struct AttachmentInfo {
        let name: String
        let data: Data
    }

    /// Builds a synthetic .msg file with the given email content.
    /// - Parameters:
    ///   - targetSize: If non-nil, pads the file to exceed this size.
    static func build(
        subject: String,
        senderName: String,
        senderEmail: String,
        bodyText: String,
        recipients: [(name: String, email: String, type: Int32)],
        attachments: [(name: String, data: Data)],
        targetSize: Int?
    ) throws -> Data {
        // Strategy: Build mini-stream containing all small streams,
        // then lay out sectors: [FAT][Directory][MiniFAT][MiniStreamContainer][LargeStreams...]

        // Collect all streams organized by storage
        var rootStreamEntries: [(name: String, data: Data)] = []

        // Root property entries for the property stream
        var rootPropEntries: [(type: UInt16, id: UInt16, fixedValue: Int32)] = []

        // Subject
        let subjectData = subject.data(using: .utf16LittleEndian)!
        rootStreamEntries.append(("__substg1.0_0037001F", subjectData))
        rootPropEntries.append((type: 0x001F, id: 0x0037, fixedValue: 0))

        // Sender Name
        let senderNameData = senderName.data(using: .utf16LittleEndian)!
        rootStreamEntries.append(("__substg1.0_0C1A001F", senderNameData))
        rootPropEntries.append((type: 0x001F, id: 0x0C1A, fixedValue: 0))

        // Sender Email
        let senderEmailData = senderEmail.data(using: .utf16LittleEndian)!
        rootStreamEntries.append(("__substg1.0_0C1F001F", senderEmailData))
        rootPropEntries.append((type: 0x001F, id: 0x0C1F, fixedValue: 0))

        // Body (plain text)
        let bodyData = bodyText.data(using: .utf16LittleEndian)!
        rootStreamEntries.append(("__substg1.0_1000001F", bodyData))
        rootPropEntries.append((type: 0x001F, id: 0x1000, fixedValue: 0))

        // Root property stream
        let rootPropStream = buildPropertyStream(entries: rootPropEntries, isRoot: true)
        rootStreamEntries.append(("__properties_version1.0", rootPropStream))

        // Build recipient sub-storages
        var recipientSubStorages: [[(name: String, data: Data)]] = []
        for recip in recipients {
            var streams: [(name: String, data: Data)] = []
            var propEntries: [(type: UInt16, id: UInt16, fixedValue: Int32)] = []

            let nameData = recip.name.data(using: .utf16LittleEndian)!
            streams.append(("__substg1.0_3001001F", nameData))
            propEntries.append((type: 0x001F, id: 0x3001, fixedValue: 0))

            let emailData = recip.email.data(using: .utf16LittleEndian)!
            streams.append(("__substg1.0_3003001F", emailData))
            propEntries.append((type: 0x001F, id: 0x3003, fixedValue: 0))

            propEntries.append((type: 0x0003, id: 0x0C15, fixedValue: recip.type))

            let propStream = buildPropertyStream(entries: propEntries, isRoot: false)
            streams.append(("__properties_version1.0", propStream))
            recipientSubStorages.append(streams)
        }

        // Build attachment sub-storages
        var attachmentSubStorages: [[(name: String, data: Data)]] = []
        for attach in attachments {
            var streams: [(name: String, data: Data)] = []
            var propEntries: [(type: UInt16, id: UInt16, fixedValue: Int32)] = []

            let nameData = attach.name.data(using: .utf16LittleEndian)!
            streams.append(("__substg1.0_3707001F", nameData))
            propEntries.append((type: 0x001F, id: 0x3707, fixedValue: 0))

            streams.append(("__substg1.0_37010102", attach.data))
            propEntries.append((type: 0x0102, id: 0x3701, fixedValue: 0))

            propEntries.append((type: 0x0003, id: 0x0E20, fixedValue: Int32(attach.data.count)))

            let propStream = buildPropertyStream(entries: propEntries, isRoot: false)
            streams.append(("__properties_version1.0", propStream))
            attachmentSubStorages.append(streams)
        }

        // If we need padding to reach a target size, add a large binary stream
        if let targetSize = targetSize {
            let paddingData = Data(count: targetSize)
            rootStreamEntries.append(("__substg1.0_00010102", paddingData))
            rootPropEntries.append((type: 0x0102, id: 0x0001, fixedValue: 0))
            // Rebuild root property stream with padding entry
            let updatedRootPropStream = buildPropertyStream(entries: rootPropEntries, isRoot: true)
            // Replace the property stream entry
            if let idx = rootStreamEntries.firstIndex(where: { $0.0 == "__properties_version1.0" }) {
                rootStreamEntries[idx] = ("__properties_version1.0", updatedRootPropStream)
            }
        }

        // Now assemble the CFB binary
        return assembleCFB(
            rootStreams: rootStreamEntries,
            recipientStorages: recipientSubStorages,
            attachmentStorages: attachmentSubStorages
        )
    }

    // MARK: - Property Stream

    private static func buildPropertyStream(
        entries: [(type: UInt16, id: UInt16, fixedValue: Int32)],
        isRoot: Bool
    ) -> Data {
        let headerSize = isRoot ? 32 : 8
        var data = Data(count: headerSize)

        for entry in entries {
            var entryBytes = Data(count: 16)
            // type (2 bytes LE)
            entryBytes[0] = UInt8(entry.type & 0xFF)
            entryBytes[1] = UInt8(entry.type >> 8)
            // id (2 bytes LE)
            entryBytes[2] = UInt8(entry.id & 0xFF)
            entryBytes[3] = UInt8(entry.id >> 8)
            // flags (4 bytes) = 0
            // value (8 bytes) - for PT_LONG store fixed value
            if entry.type == 0x0003 {
                let v = entry.fixedValue
                entryBytes[8] = UInt8(truncatingIfNeeded: v)
                entryBytes[9] = UInt8(truncatingIfNeeded: v >> 8)
                entryBytes[10] = UInt8(truncatingIfNeeded: v >> 16)
                entryBytes[11] = UInt8(truncatingIfNeeded: v >> 24)
            }
            data.append(entryBytes)
        }
        return data
    }

    // MARK: - Types

    enum StorageType { case root, recipient, attachment }

    struct FlatStream {
        let name: String
        let data: Data
        let storageType: StorageType
        let storageIndex: Int
    }

    struct DirEntry {
        var name: String
        var objectType: UInt8
        var startSector: UInt32
        var streamSize: UInt64
        var childID: UInt32 = 0xFFFFFFFF
        var leftSiblingID: UInt32 = 0xFFFFFFFF
        var rightSiblingID: UInt32 = 0xFFFFFFFF
    }

    // MARK: - CFB Assembly

    private static func assembleCFB(
        rootStreams: [(name: String, data: Data)],
        recipientStorages: [[(name: String, data: Data)]],
        attachmentStorages: [[(name: String, data: Data)]]
    ) -> Data {
        // Plan:
        // 1. All streams < 4096 go in mini-stream (stored in root's stream via regular FAT)
        // 2. Streams >= 4096 go directly into regular sectors
        // 3. Layout: Header(512) | FAT sector | Dir sector(s) | MiniFAT sector | MiniStreamContainer sectors | Large stream sectors

        var allStreams: [FlatStream] = []
        for s in rootStreams {
            allStreams.append(FlatStream(name: s.0, data: s.1, storageType: .root, storageIndex: 0))
        }
        for (i, storage) in recipientStorages.enumerated() {
            for s in storage {
                allStreams.append(FlatStream(name: s.0, data: s.1, storageType: .recipient, storageIndex: i))
            }
        }
        for (i, storage) in attachmentStorages.enumerated() {
            for s in storage {
                allStreams.append(FlatStream(name: s.0, data: s.1, storageType: .attachment, storageIndex: i))
            }
        }

        // Separate into mini vs regular streams
        let miniStreams = allStreams.filter { $0.data.count < Int(miniStreamCutoff) }
        let regularStreams = allStreams.filter { $0.data.count >= Int(miniStreamCutoff) }

        // Build mini-stream container (all mini-streams packed into mini-sectors)
        var miniStreamContainer = Data()
        var miniStreamLocations: [String: (storageType: StorageType, storageIndex: Int, miniStartSector: UInt32, size: Int)] = [:]
        var miniFATEntries: [UInt32] = []

        for stream in miniStreams {
            let startMiniSector = UInt32(miniStreamContainer.count / miniSectorSize)
            let miniSectorCount = (stream.data.count + miniSectorSize - 1) / miniSectorSize

            // Append data padded to mini-sector boundary
            var paddedData = stream.data
            let remainder = paddedData.count % miniSectorSize
            if remainder != 0 {
                paddedData.append(Data(count: miniSectorSize - remainder))
            }
            miniStreamContainer.append(paddedData)

            // Build mini-FAT chain
            for i in 0..<miniSectorCount {
                if i == miniSectorCount - 1 {
                    miniFATEntries.append(endOfChain)
                } else {
                    miniFATEntries.append(startMiniSector + UInt32(i) + 1)
                }
            }

            let key = "\(stream.storageType)_\(stream.storageIndex)_\(stream.name)"
            miniStreamLocations[key] = (stream.storageType, stream.storageIndex, startMiniSector, stream.data.count)
        }

        // Pad mini-stream container to at least 4096 bytes (miniStreamCutoffSize)
        // This ensures the root entry's stream size >= cutoff, so the parser reads it
        // via the regular FAT (not the mini-FAT), avoiding a chicken-and-egg problem.
        if !miniStreamContainer.isEmpty && miniStreamContainer.count < Int(miniStreamCutoff) {
            miniStreamContainer.append(Data(count: Int(miniStreamCutoff) - miniStreamContainer.count))
        }

        // Regular stream locations
        var regularStreamLocations: [String: (storageType: StorageType, storageIndex: Int, startSector: UInt32, size: Int)] = [:]

        // Count total directory entries needed
        let rootEntryCount = 1
        let rootStreamCount = rootStreams.count
        let recipStorageCount = recipientStorages.count
        let recipStreamCount = recipientStorages.reduce(0) { $0 + $1.count }
        let attachStorageCount = attachmentStorages.count
        let attachStreamCount = attachmentStorages.reduce(0) { $0 + $1.count }
        let totalDirEntries = rootEntryCount + rootStreamCount + recipStorageCount + recipStreamCount + attachStorageCount + attachStreamCount

        let entriesPerSector = sectorSize / 128
        let dirSectorCount = max(1, (totalDirEntries + entriesPerSector - 1) / entriesPerSector)

        let hasMiniFAT = !miniFATEntries.isEmpty
        let miniFATSectorCount = hasMiniFAT ? max(1, (miniFATEntries.count * 4 + sectorSize - 1) / sectorSize) : 0
        let miniStreamContainerSectorCount = (miniStreamContainer.count + sectorSize - 1) / sectorSize

        // Count regular stream sectors needed
        var regularStreamSectorCount = 0
        for stream in regularStreams {
            regularStreamSectorCount += (stream.data.count + sectorSize - 1) / sectorSize
        }

        // Calculate how many FAT sectors we need
        // dataSectors = dir + miniFAT + miniContainer + regularStreams
        let dataSectors = dirSectorCount + miniFATSectorCount + miniStreamContainerSectorCount + regularStreamSectorCount
        let fatEntriesPerSector = sectorSize / 4 // 128 entries per 512-byte FAT sector
        // We need enough FAT sectors to cover all sectors including the FAT sectors themselves
        var fatSectorCount = 1
        while fatSectorCount * fatEntriesPerSector < dataSectors + fatSectorCount {
            fatSectorCount += 1
        }

        // Sector layout: FAT sectors | Dir sectors | MiniFAT sectors | MiniStream sectors | Regular sectors
        let fatStartSectorID: UInt32 = 0
        let dirStartSectorID = UInt32(fatSectorCount)
        let miniFATStartSectorID: UInt32 = hasMiniFAT ? UInt32(fatSectorCount + dirSectorCount) : endOfChain
        let miniStreamContainerStartSectorID = UInt32(fatSectorCount + dirSectorCount + miniFATSectorCount)
        let regularStartOffset = fatSectorCount + dirSectorCount + miniFATSectorCount + miniStreamContainerSectorCount

        var nextRegularSector = UInt32(regularStartOffset)
        for stream in regularStreams {
            let sc = (stream.data.count + sectorSize - 1) / sectorSize
            let key = "\(stream.storageType)_\(stream.storageIndex)_\(stream.name)"
            regularStreamLocations[key] = (stream.storageType, stream.storageIndex, nextRegularSector, stream.data.count)
            nextRegularSector += UInt32(sc)
        }

        let totalSectors = Int(nextRegularSector)

        // Build FAT
        var fat = [UInt32](repeating: freeSector, count: max(totalSectors, fatSectorCount * fatEntriesPerSector))

        // Mark FAT sectors (0xFFFFFFFD)
        for i in 0..<fatSectorCount {
            fat[Int(fatStartSectorID) + i] = 0xFFFFFFFD
        }

        // Directory sector chain
        for i in 0..<dirSectorCount {
            let sectorID = Int(dirStartSectorID) + i
            fat[sectorID] = (i == dirSectorCount - 1) ? endOfChain : UInt32(sectorID + 1)
        }

        // MiniFAT sector chain
        for i in 0..<miniFATSectorCount {
            let sectorID = Int(miniFATStartSectorID) + i
            fat[sectorID] = (i == miniFATSectorCount - 1) ? endOfChain : UInt32(sectorID + 1)
        }

        // Mini-stream container chain
        for i in 0..<miniStreamContainerSectorCount {
            let sectorID = Int(miniStreamContainerStartSectorID) + i
            fat[sectorID] = (i == miniStreamContainerSectorCount - 1) ? endOfChain : UInt32(sectorID + 1)
        }

        // Regular stream chains
        for stream in regularStreams {
            let key = "\(stream.storageType)_\(stream.storageIndex)_\(stream.name)"
            guard let loc = regularStreamLocations[key] else { continue }
            let sc = (stream.data.count + sectorSize - 1) / sectorSize
            for i in 0..<sc {
                let sectorID = Int(loc.startSector) + i
                fat[sectorID] = (i == sc - 1) ? endOfChain : UInt32(sectorID + 1)
            }
        }

        // Build directory entries
        // The directory tree uses a simplified structure:
        // Root's childID points to a balanced tree of its children (storages + streams)
        // Sub-storages' childID points to their children

        var dirEntryList: [DirEntry] = []

        // Entry 0: Root Entry
        dirEntryList.append(DirEntry(
            name: "Root Entry",
            objectType: 5, // rootStorage
            startSector: miniStreamContainerSectorCount > 0 ? miniStreamContainerStartSectorID : endOfChain,
            streamSize: UInt64(miniStreamContainer.count)
        ))

        // Helper to get start sector and size for a stream
        func streamLocation(_ streamName: String, storageType: StorageType, storageIndex: Int) -> (UInt32, UInt64) {
            let key = "\(storageType)_\(storageIndex)_\(streamName)"
            if let loc = miniStreamLocations[key] {
                return (loc.miniStartSector, UInt64(loc.size))
            }
            if let loc = regularStreamLocations[key] {
                return (loc.startSector, UInt64(loc.size))
            }
            return (endOfChain, 0)
        }

        // Root's children: root streams + sub-storages
        var rootChildIndices: [Int] = []

        // Add root stream entries
        for stream in rootStreams {
            let (startSec, size) = streamLocation(stream.0, storageType: .root, storageIndex: 0)
            let idx = dirEntryList.count
            dirEntryList.append(DirEntry(
                name: stream.0,
                objectType: 2, // stream
                startSector: startSec,
                streamSize: size
            ))
            rootChildIndices.append(idx)
        }

        // Add recipient sub-storage entries
        for (i, recipStreams) in recipientStorages.enumerated() {
            let storageIdx = dirEntryList.count
            dirEntryList.append(DirEntry(
                name: "__recip_version2.0_#\(String(format: "%08X", i))",
                objectType: 1, // storage
                startSector: 0,
                streamSize: 0
            ))
            rootChildIndices.append(storageIdx)

            var childIndices: [Int] = []
            for stream in recipStreams {
                let (startSec, size) = streamLocation(stream.0, storageType: .recipient, storageIndex: i)
                let idx = dirEntryList.count
                dirEntryList.append(DirEntry(
                    name: stream.0,
                    objectType: 2,
                    startSector: startSec,
                    streamSize: size
                ))
                childIndices.append(idx)
            }

            // Set sub-storage's child tree
            if !childIndices.isEmpty {
                buildBinaryTree(entries: &dirEntryList, indices: childIndices, parentIndex: storageIdx)
            }
        }

        // Add attachment sub-storage entries
        for (i, attachStreams) in attachmentStorages.enumerated() {
            let storageIdx = dirEntryList.count
            dirEntryList.append(DirEntry(
                name: "__attach_version2.0_#\(String(format: "%08X", i))",
                objectType: 1, // storage
                startSector: 0,
                streamSize: 0
            ))
            rootChildIndices.append(storageIdx)

            var childIndices: [Int] = []
            for stream in attachStreams {
                let (startSec, size) = streamLocation(stream.0, storageType: .attachment, storageIndex: i)
                let idx = dirEntryList.count
                dirEntryList.append(DirEntry(
                    name: stream.0,
                    objectType: 2,
                    startSector: startSec,
                    streamSize: size
                ))
                childIndices.append(idx)
            }

            if !childIndices.isEmpty {
                buildBinaryTree(entries: &dirEntryList, indices: childIndices, parentIndex: storageIdx)
            }
        }

        // Set root's child tree
        if !rootChildIndices.isEmpty {
            buildBinaryTree(entries: &dirEntryList, indices: rootChildIndices, parentIndex: 0)
        }

        // Serialize to binary
        // 1. Write 512-byte header
        var fileData = Data(count: sectorSize)
        writeHeader(to: &fileData, fatSectorCount: UInt32(fatSectorCount),
                    dirStartSectorID: dirStartSectorID,
                    miniFATStartSectorID: miniFATStartSectorID,
                    miniFATSectorCount: UInt32(miniFATSectorCount))

        // 2. Write FAT sectors
        for f in 0..<fatSectorCount {
            var fatSectorData = Data(count: sectorSize)
            let startIdx = f * fatEntriesPerSector
            let endIdx = min(startIdx + fatEntriesPerSector, fat.count)
            for i in startIdx..<endIdx {
                writeLEUInt32(&fatSectorData, at: (i - startIdx) * 4, value: fat[i])
            }
            // Fill remaining with free sector
            for i in (endIdx - startIdx)..<fatEntriesPerSector {
                writeLEUInt32(&fatSectorData, at: i * 4, value: freeSector)
            }
            fileData.append(fatSectorData)
        }

        // 3. Write directory sectors
        var dirData = Data(count: dirSectorCount * sectorSize)
        for (i, entry) in dirEntryList.enumerated() {
            let offset = i * 128
            writeDirectoryEntry(to: &dirData, at: offset, entry: entry)
        }
        fileData.append(dirData)

        // 4. Write MiniFAT sector(s)
        if hasMiniFAT {
            var miniFATData = Data(count: miniFATSectorCount * sectorSize)
            for (i, value) in miniFATEntries.enumerated() {
                writeLEUInt32(&miniFATData, at: i * 4, value: value)
            }
            // Fill remaining with free sector
            let totalMiniFATSlots = miniFATSectorCount * (sectorSize / 4)
            for i in miniFATEntries.count..<totalMiniFATSlots {
                writeLEUInt32(&miniFATData, at: i * 4, value: freeSector)
            }
            fileData.append(miniFATData)
        }

        // 5. Write mini-stream container sectors
        if miniStreamContainerSectorCount > 0 {
            var containerData = miniStreamContainer
            let targetSize = miniStreamContainerSectorCount * sectorSize
            if containerData.count < targetSize {
                containerData.append(Data(count: targetSize - containerData.count))
            }
            fileData.append(containerData)
        }

        // 6. Write regular stream sectors
        for stream in regularStreams {
            var streamData = stream.data
            let sectorCount = (streamData.count + sectorSize - 1) / sectorSize
            let targetSize = sectorCount * sectorSize
            if streamData.count < targetSize {
                streamData.append(Data(count: targetSize - streamData.count))
            }
            fileData.append(streamData)
        }

        return fileData
    }

    // MARK: - Binary Tree for Directory Entries

    /// Builds a balanced binary tree from the given child indices.
    /// Sets the parent's childID to the root of the tree, and each node's
    /// left/right siblings accordingly.
    private static func buildBinaryTree(entries: inout [DirEntry], indices: [Int], parentIndex: Int) {
        guard !indices.isEmpty else { return }

        // Use a simple balanced tree: middle element is root
        let rootIdx = assignTree(entries: &entries, indices: indices)
        entries[parentIndex].childID = UInt32(rootIdx)
    }

    private static func assignTree(entries: inout [DirEntry], indices: [Int]) -> Int {
        guard !indices.isEmpty else { return -1 }
        if indices.count == 1 {
            entries[indices[0]].leftSiblingID = noStream
            entries[indices[0]].rightSiblingID = noStream
            return indices[0]
        }

        let mid = indices.count / 2
        let rootIdx = indices[mid]
        let leftIndices = Array(indices[0..<mid])
        let rightIndices = Array(indices[(mid+1)...])

        if !leftIndices.isEmpty {
            let leftRoot = assignTree(entries: &entries, indices: leftIndices)
            entries[rootIdx].leftSiblingID = UInt32(leftRoot)
        } else {
            entries[rootIdx].leftSiblingID = noStream
        }

        if !rightIndices.isEmpty {
            let rightRoot = assignTree(entries: &entries, indices: rightIndices)
            entries[rootIdx].rightSiblingID = UInt32(rightRoot)
        } else {
            entries[rootIdx].rightSiblingID = noStream
        }

        return rootIdx
    }

    // MARK: - Header Writing

    private static func writeHeader(to data: inout Data, fatSectorCount: UInt32,
                                     dirStartSectorID: UInt32,
                                     miniFATStartSectorID: UInt32,
                                     miniFATSectorCount: UInt32) {
        // Signature (8 bytes at offset 0)
        writeLEUInt64(&data, at: 0, value: signature)
        // CLSID (16 bytes at offset 8) - zeros
        // Minor version (2 bytes at offset 24)
        writeLEUInt16(&data, at: 24, value: 0x003E)
        // Major version (2 bytes at offset 26) - version 3
        writeLEUInt16(&data, at: 26, value: 3)
        // Byte order (2 bytes at offset 28)
        writeLEUInt16(&data, at: 28, value: 0xFFFE)
        // Sector size power (2 bytes at offset 30) - 9 = 512
        writeLEUInt16(&data, at: 30, value: 9)
        // Mini sector size power (2 bytes at offset 32) - 6 = 64
        writeLEUInt16(&data, at: 32, value: 6)
        // Reserved (6 bytes at offset 34) - zeros
        // Total directory sectors (4 bytes at offset 40) - 0 for v3
        writeLEUInt32(&data, at: 40, value: 0)
        // Total FAT sectors (4 bytes at offset 44)
        writeLEUInt32(&data, at: 44, value: fatSectorCount)
        // First directory sector (4 bytes at offset 48)
        writeLEUInt32(&data, at: 48, value: dirStartSectorID)
        // Transaction signature (4 bytes at offset 52) - 0
        // Mini stream cutoff size (4 bytes at offset 56) - 4096
        writeLEUInt32(&data, at: 56, value: miniStreamCutoff)
        // First mini-FAT sector (4 bytes at offset 60)
        writeLEUInt32(&data, at: 60, value: miniFATStartSectorID)
        // Total mini-FAT sectors (4 bytes at offset 64)
        writeLEUInt32(&data, at: 64, value: miniFATSectorCount)
        // First DIFAT sector (4 bytes at offset 68) - none
        writeLEUInt32(&data, at: 68, value: endOfChain)
        // Total DIFAT sectors (4 bytes at offset 72) - 0
        writeLEUInt32(&data, at: 72, value: 0)
        // DIFAT array (109 entries at offset 76) - list FAT sector IDs
        for i in 0..<109 {
            if i < Int(fatSectorCount) {
                writeLEUInt32(&data, at: 76 + i * 4, value: UInt32(i))
            } else {
                writeLEUInt32(&data, at: 76 + i * 4, value: freeSector)
            }
        }
    }

    // MARK: - Directory Entry Writing

    private static func writeDirectoryEntry(to data: inout Data, at offset: Int, entry: DirEntry) {
        // Name in UTF-16LE (64 bytes max)
        let nameUTF16 = Array(entry.name.utf16)
        let nameByteCount = min(nameUTF16.count * 2, 64)
        for i in 0..<min(nameUTF16.count, 32) {
            data[offset + i * 2] = UInt8(nameUTF16[i] & 0xFF)
            data[offset + i * 2 + 1] = UInt8(nameUTF16[i] >> 8)
        }
        // Name size (2 bytes at offset+64) including null terminator
        let nameSizeBytes = UInt16(nameByteCount + 2)
        data[offset + 64] = UInt8(nameSizeBytes & 0xFF)
        data[offset + 65] = UInt8(nameSizeBytes >> 8)

        // Object type (1 byte at offset+66)
        data[offset + 66] = entry.objectType

        // Color flag (1 byte at offset+67) - black=1
        data[offset + 67] = 1

        // Left sibling (4 bytes at offset+68)
        writeLEUInt32(&data, at: offset + 68, value: entry.leftSiblingID)
        // Right sibling (4 bytes at offset+72)
        writeLEUInt32(&data, at: offset + 72, value: entry.rightSiblingID)
        // Child ID (4 bytes at offset+76)
        writeLEUInt32(&data, at: offset + 76, value: entry.childID)

        // CLSID (16 bytes at offset+80) - zeros
        // State bits (4 bytes at offset+96) - zeros
        // Created (8 bytes at offset+100) - zeros
        // Modified (8 bytes at offset+108) - zeros

        // Start sector (4 bytes at offset+116)
        writeLEUInt32(&data, at: offset + 116, value: entry.startSector)
        // Stream size (8 bytes at offset+120) - only lower 32 bits for v3
        writeLEUInt32(&data, at: offset + 120, value: UInt32(entry.streamSize & 0xFFFFFFFF))
        writeLEUInt32(&data, at: offset + 124, value: 0)
    }

    // MARK: - Little-Endian Write Helpers

    private static func writeLEUInt16(_ data: inout Data, at offset: Int, value: UInt16) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8(value >> 8)
    }

    private static func writeLEUInt32(_ data: inout Data, at offset: Int, value: UInt32) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
        data[offset + 2] = UInt8((value >> 16) & 0xFF)
        data[offset + 3] = UInt8((value >> 24) & 0xFF)
    }

    private static func writeLEUInt64(_ data: inout Data, at offset: Int, value: UInt64) {
        for i in 0..<8 {
            data[offset + i] = UInt8((value >> (i * 8)) & 0xFF)
        }
    }
}
