// CFBDirectoryEntryTests - Unit tests for CFBReader.readDirectoryEntries

import XCTest
@testable import MSGParser

final class CFBDirectoryEntryTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a minimal CFBHeader suitable for testing directory entry parsing.
    private func makeHeader(
        firstDirectorySector: UInt32 = 0,
        majorVersion: UInt16 = 3,
        sectorSizePower: UInt16 = 9  // 512 bytes
    ) -> CFBHeader {
        CFBHeader(
            signature: CFBHeader.expectedSignature,
            minorVersion: 0x003E,
            majorVersion: majorVersion,
            byteOrder: 0xFFFE,
            sectorSizePower: sectorSizePower,
            miniSectorSizePower: 6,
            totalFATSectors: 1,
            firstDirectorySector: firstDirectorySector,
            miniStreamCutoffSize: 4096,
            firstMiniFATSector: 0xFFFFFFFE,
            totalMiniFATSectors: 0,
            firstDIFATSector: 0xFFFFFFFE,
            totalDIFATSectors: 0,
            difatArray: []
        )
    }

    /// Creates a 128-byte directory entry with specified fields.
    private func makeDirectoryEntryBytes(
        name: String = "Root Entry",
        objectType: UInt8 = 5,
        leftSiblingID: UInt32 = 0xFFFFFFFF,
        rightSiblingID: UInt32 = 0xFFFFFFFF,
        childID: UInt32 = 0xFFFFFFFF,
        startSector: UInt32 = 0,
        streamSize: UInt64 = 0
    ) -> Data {
        var entry = Data(count: 128)

        // Encode name as UTF-16LE (bytes 0-63)
        let utf16 = Array(name.utf16)
        for (i, unit) in utf16.prefix(32).enumerated() {
            entry[i * 2] = UInt8(unit & 0xFF)
            entry[i * 2 + 1] = UInt8(unit >> 8)
        }

        // Name size in bytes (including null terminator) at offset 64-65
        let nameSize = UInt16((utf16.count + 1) * 2)
        entry[64] = UInt8(nameSize & 0xFF)
        entry[65] = UInt8(nameSize >> 8)

        // Object type at offset 66
        entry[66] = objectType

        // Left sibling ID at offset 68-71
        entry[68] = UInt8(leftSiblingID & 0xFF)
        entry[69] = UInt8((leftSiblingID >> 8) & 0xFF)
        entry[70] = UInt8((leftSiblingID >> 16) & 0xFF)
        entry[71] = UInt8((leftSiblingID >> 24) & 0xFF)

        // Right sibling ID at offset 72-75
        entry[72] = UInt8(rightSiblingID & 0xFF)
        entry[73] = UInt8((rightSiblingID >> 8) & 0xFF)
        entry[74] = UInt8((rightSiblingID >> 16) & 0xFF)
        entry[75] = UInt8((rightSiblingID >> 24) & 0xFF)

        // Child ID at offset 76-79
        entry[76] = UInt8(childID & 0xFF)
        entry[77] = UInt8((childID >> 8) & 0xFF)
        entry[78] = UInt8((childID >> 16) & 0xFF)
        entry[79] = UInt8((childID >> 24) & 0xFF)

        // Start sector at offset 116-119
        entry[116] = UInt8(startSector & 0xFF)
        entry[117] = UInt8((startSector >> 8) & 0xFF)
        entry[118] = UInt8((startSector >> 16) & 0xFF)
        entry[119] = UInt8((startSector >> 24) & 0xFF)

        // Stream size at offset 120-127
        entry[120] = UInt8(streamSize & 0xFF)
        entry[121] = UInt8((streamSize >> 8) & 0xFF)
        entry[122] = UInt8((streamSize >> 16) & 0xFF)
        entry[123] = UInt8((streamSize >> 24) & 0xFF)
        entry[124] = UInt8((streamSize >> 32) & 0xFF)
        entry[125] = UInt8((streamSize >> 40) & 0xFF)
        entry[126] = UInt8((streamSize >> 48) & 0xFF)
        entry[127] = UInt8((streamSize >> 56) & 0xFF)

        return entry
    }

    /// Builds test data with a 512-byte header pad + directory sectors.
    /// The directory sector is at sector 0 (file offset 512).
    private func buildTestData(entries: [Data], fat: [UInt32]) -> Data {
        let sectorSize = 512
        // Header (512 bytes)
        var data = Data(count: sectorSize)

        // Directory sector(s) - pad with empty entries to fill sector
        let entriesPerSector = sectorSize / 128 // 4 entries per 512-byte sector
        var sectorEntries = entries
        while sectorEntries.count % entriesPerSector != 0 {
            sectorEntries.append(Data(count: 128)) // Empty entry (type 0 = unknown)
        }

        for entry in sectorEntries {
            data.append(entry)
        }

        // Pad remaining data if FAT references more sectors
        let totalSectorsNeeded = fat.count
        let currentSectors = sectorEntries.count / entriesPerSector
        if totalSectorsNeeded > currentSectors {
            let paddingBytes = (totalSectorsNeeded - currentSectors) * sectorSize
            data.append(Data(count: paddingBytes))
        }

        return data
    }

    // MARK: - Tests

    func testParsesRootEntryCorrectly() throws {
        let rootEntry = makeDirectoryEntryBytes(
            name: "Root Entry",
            objectType: 5,  // rootStorage
            childID: 1,
            startSector: 2,
            streamSize: 4096
        )

        let fat: [UInt32] = [0xFFFFFFFE] // Sector 0 is end-of-chain
        let data = buildTestData(entries: [rootEntry], fat: fat)
        let reader = InMemoryDataReader(data: data)
        let header = makeHeader(firstDirectorySector: 0)

        let entries = try CFBReader.readDirectoryEntries(header: header, fat: fat, reader: reader)

        // Sector has 4 entries (512/128), first is our root entry
        XCTAssertGreaterThanOrEqual(entries.count, 1)
        let root = entries[0]
        XCTAssertEqual(root.name, "Root Entry")
        XCTAssertEqual(root.objectType, .rootStorage)
        XCTAssertEqual(root.childID, 1)
        XCTAssertEqual(root.startSector, 2)
        XCTAssertEqual(root.streamSize, 4096)
        XCTAssertEqual(root.leftSiblingID, 0xFFFFFFFF)
        XCTAssertEqual(root.rightSiblingID, 0xFFFFFFFF)
    }

    func testParsesMultipleEntries() throws {
        let rootEntry = makeDirectoryEntryBytes(
            name: "Root Entry",
            objectType: 5,
            childID: 1,
            startSector: 0,
            streamSize: 0
        )
        let streamEntry = makeDirectoryEntryBytes(
            name: "__properties_version1.0",
            objectType: 2,  // stream
            startSector: 5,
            streamSize: 256
        )

        let fat: [UInt32] = [0xFFFFFFFE]
        let data = buildTestData(entries: [rootEntry, streamEntry], fat: fat)
        let reader = InMemoryDataReader(data: data)
        let header = makeHeader(firstDirectorySector: 0)

        let entries = try CFBReader.readDirectoryEntries(header: header, fat: fat, reader: reader)

        XCTAssertGreaterThanOrEqual(entries.count, 2)
        XCTAssertEqual(entries[0].name, "Root Entry")
        XCTAssertEqual(entries[0].objectType, .rootStorage)
        XCTAssertEqual(entries[1].name, "__properties_version1.0")
        XCTAssertEqual(entries[1].objectType, .stream)
        XCTAssertEqual(entries[1].startSector, 5)
        XCTAssertEqual(entries[1].streamSize, 256)
    }

    func testFollowsFATChainForMultipleDirectorySectors() throws {
        let sectorSize = 512
        let entriesPerSector = sectorSize / 128 // 4

        // Sector 0: directory sector 1, Sector 1: directory sector 2
        // FAT: sector 0 -> sector 1 -> end
        let fat: [UInt32] = [1, 0xFFFFFFFE]

        // Build 8 entries (fills 2 sectors)
        var entries: [Data] = []
        for i in 0..<(entriesPerSector * 2) {
            entries.append(makeDirectoryEntryBytes(
                name: "Entry\(i)",
                objectType: i == 0 ? 5 : 2,
                startSector: UInt32(i * 10),
                streamSize: UInt64(i * 100)
            ))
        }

        let data = buildTestData(entries: entries, fat: fat)
        let reader = InMemoryDataReader(data: data)
        let header = makeHeader(firstDirectorySector: 0)

        let parsed = try CFBReader.readDirectoryEntries(header: header, fat: fat, reader: reader)

        XCTAssertEqual(parsed.count, 8)
        XCTAssertEqual(parsed[0].name, "Entry0")
        XCTAssertEqual(parsed[0].objectType, .rootStorage)
        XCTAssertEqual(parsed[7].name, "Entry7")
        XCTAssertEqual(parsed[7].objectType, .stream)
        XCTAssertEqual(parsed[7].startSector, 70)
        XCTAssertEqual(parsed[7].streamSize, 700)
    }

    func testDetectsCycleInDirectorySectorChain() {
        // FAT: sector 0 -> sector 1 -> sector 0 (cycle!)
        let fat: [UInt32] = [1, 0]

        let rootEntry = makeDirectoryEntryBytes(name: "Root Entry", objectType: 5)
        let data = buildTestData(entries: [rootEntry, rootEntry, rootEntry, rootEntry,
                                           rootEntry, rootEntry, rootEntry, rootEntry], fat: fat)
        let reader = InMemoryDataReader(data: data)
        let header = makeHeader(firstDirectorySector: 0)

        XCTAssertThrowsError(try CFBReader.readDirectoryEntries(header: header, fat: fat, reader: reader)) { error in
            guard case CFBError.corruptedFile(_, let reason) = error else {
                XCTFail("Expected CFBError.corruptedFile, got \(error)")
                return
            }
            XCTAssertTrue(reason.contains("cycle"), "Expected cycle mention in reason: \(reason)")
        }
    }

    func testThrowsWhenSectorIndexOutOfFATBounds() {
        // FAT has only 1 entry but firstDirectorySector points to sector 5
        let fat: [UInt32] = [0xFFFFFFFE]

        let data = Data(count: 512) // Just header, no sectors
        let reader = InMemoryDataReader(data: data)
        let header = makeHeader(firstDirectorySector: 5)

        XCTAssertThrowsError(try CFBReader.readDirectoryEntries(header: header, fat: fat, reader: reader)) { error in
            guard case CFBError.corruptedFile(let sectorIndex, let reason) = error else {
                XCTFail("Expected CFBError.corruptedFile, got \(error)")
                return
            }
            XCTAssertEqual(sectorIndex, 5)
            XCTAssertTrue(reason.contains("out of FAT bounds"), "Reason: \(reason)")
        }
    }

    func testEmptyNameEntryHandled() throws {
        // Entry with nameSize = 0
        var entry = Data(count: 128)
        entry[64] = 0  // nameSize = 0
        entry[65] = 0
        entry[66] = 2  // stream type

        let fat: [UInt32] = [0xFFFFFFFE]
        let data = buildTestData(entries: [entry], fat: fat)
        let reader = InMemoryDataReader(data: data)
        let header = makeHeader(firstDirectorySector: 0)

        let entries = try CFBReader.readDirectoryEntries(header: header, fat: fat, reader: reader)
        XCTAssertEqual(entries[0].name, "")
        XCTAssertEqual(entries[0].objectType, .stream)
    }

    func testVersion3TruncatesStreamSizeTo32Bits() throws {
        // For v3, only lower 32 bits of stream size should be used
        let entry = makeDirectoryEntryBytes(
            name: "TestStream",
            objectType: 2,
            startSector: 0,
            streamSize: 0x00000001_00000100  // Upper 32 bits set
        )

        let fat: [UInt32] = [0xFFFFFFFE]
        let data = buildTestData(entries: [entry], fat: fat)
        let reader = InMemoryDataReader(data: data)
        let header = makeHeader(firstDirectorySector: 0, majorVersion: 3)

        let entries = try CFBReader.readDirectoryEntries(header: header, fat: fat, reader: reader)
        // Only lower 32 bits: 0x00000100 = 256
        XCTAssertEqual(entries[0].streamSize, 0x00000100)
    }

    func testVersion4UsesFullStreamSize() throws {
        let entry = makeDirectoryEntryBytes(
            name: "TestStream",
            objectType: 2,
            startSector: 0,
            streamSize: 0x00000001_00000100
        )

        let fat: [UInt32] = [0xFFFFFFFE]

        // For v4 with 4096-byte sectors, we need more data
        let sectorSize = 4096
        var v4Data = Data(count: sectorSize) // Header
        // Directory sector - need 4096 bytes (32 entries per sector)
        var dirSector = Data(count: sectorSize)
        // Copy our entry into the first 128 bytes
        dirSector.replaceSubrange(0..<128, with: entry)
        v4Data.append(dirSector)

        let v4Reader = InMemoryDataReader(data: v4Data)
        let v4Header = makeHeader(firstDirectorySector: 0, majorVersion: 4, sectorSizePower: 12)

        let entries = try CFBReader.readDirectoryEntries(header: v4Header, fat: fat, reader: v4Reader)
        XCTAssertEqual(entries[0].streamSize, 0x00000001_00000100)
    }

    func testReturnsEmptyWhenFirstDirectorySectorIsEndOfChain() throws {
        let fat: [UInt32] = [0xFFFFFFFE]
        let data = Data(count: 512)
        let reader = InMemoryDataReader(data: data)
        let header = makeHeader(firstDirectorySector: 0xFFFFFFFE)

        let entries = try CFBReader.readDirectoryEntries(header: header, fat: fat, reader: reader)
        XCTAssertEqual(entries.count, 0)
    }

    func testParsesObjectTypesCorrectly() throws {
        let unknown = makeDirectoryEntryBytes(name: "Unknown", objectType: 0)
        let storage = makeDirectoryEntryBytes(name: "Storage", objectType: 1)
        let stream = makeDirectoryEntryBytes(name: "Stream", objectType: 2)
        let root = makeDirectoryEntryBytes(name: "Root", objectType: 5)

        let fat: [UInt32] = [0xFFFFFFFE]
        let data = buildTestData(entries: [unknown, storage, stream, root], fat: fat)
        let reader = InMemoryDataReader(data: data)
        let header = makeHeader(firstDirectorySector: 0)

        let entries = try CFBReader.readDirectoryEntries(header: header, fat: fat, reader: reader)

        XCTAssertEqual(entries[0].objectType, .unknown)
        XCTAssertEqual(entries[1].objectType, .storage)
        XCTAssertEqual(entries[2].objectType, .stream)
        XCTAssertEqual(entries[3].objectType, .rootStorage)
    }
}
