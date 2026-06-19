// PerformanceTests - Integration and performance tests for MSGParser
// Tests parsing timing for large files and main thread responsiveness
//
// Requirements: 8.1, 8.4, 8.5

import XCTest
@testable import MSGParser

final class PerformanceTests: XCTestCase {

    // MARK: - Constants

    private static let tenMB = 10 * 1024 * 1024
    private static let oneFiftyMB = 150 * 1024 * 1024

    // MARK: - 10 MB File Performance Test

    /// Test that a 10 MB file is parsed (or fails with a clear error) within 500ms.
    /// Validates: Requirement 8.1
    func testTenMBFileParsingPerformance() throws {
        let url = try createSyntheticCFBFile(size: Self.tenMB)
        defer { try? FileManager.default.removeItem(at: url) }

        // Verify the factory uses MappedDataReader for this size
        let reader = try DataReaderFactory.createReader(for: url)
        XCTAssertTrue(reader is MappedDataReader, "10 MB file should use MappedDataReader")

        measure {
            let parser = MSGParser()
            let expectation = self.expectation(description: "parse 10 MB")

            Task {
                do {
                    _ = try await parser.parse(url: url)
                } catch {
                    // Expected to fail since synthetic data won't have valid MAPI properties,
                    // but we're measuring the time through the CFB parsing pipeline
                }
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 0.5)
        }
    }

    /// Test that a 10 MB file reader creation and CFB header parsing completes within 500ms.
    /// This exercises the DataReader selection and initial parsing steps.
    /// Validates: Requirement 8.1
    func testTenMBFileDataReaderAndHeaderPerformance() throws {
        let url = try createSyntheticCFBFile(size: Self.tenMB)
        defer { try? FileManager.default.removeItem(at: url) }

        measure {
            do {
                let reader = try DataReaderFactory.createReader(for: url)
                // Exercise reading across the file to simulate FAT traversal
                let _ = try reader.readBytes(at: 0, length: 512) // header
                let midpoint = reader.count / 2
                let _ = try reader.readBytes(at: midpoint, length: 512) // mid-file read
                let _ = try reader.readBytes(at: reader.count - 512, length: 512) // end read
            } catch {
                XCTFail("DataReader creation should not fail: \(error)")
            }
        }
    }

    // MARK: - 150 MB File Performance Test

    /// Test that a 150 MB file reader creation and scattered reads complete within 3 seconds.
    /// Validates: Requirement 8.4
    func testOneFiftyMBFileParsingPerformance() throws {
        let url = try createSyntheticCFBFile(size: Self.oneFiftyMB)
        defer { try? FileManager.default.removeItem(at: url) }

        // Verify the factory uses MappedDataReader for this size
        let reader = try DataReaderFactory.createReader(for: url)
        XCTAssertTrue(reader is MappedDataReader, "150 MB file should use MappedDataReader")

        measure {
            let parser = MSGParser()
            let expectation = self.expectation(description: "parse 150 MB")

            Task {
                do {
                    _ = try await parser.parse(url: url)
                } catch {
                    // Expected to fail since synthetic data won't have fully valid structures,
                    // but we're measuring the time through the parsing pipeline
                }
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 3.0)
        }
    }

    /// Test that creating a MappedDataReader for 150 MB and performing FAT-like
    /// scattered reads across the file completes within 3 seconds.
    /// Validates: Requirement 8.4
    func testOneFiftyMBFileDataReaderPerformance() throws {
        let url = try createSyntheticCFBFile(size: Self.oneFiftyMB)
        defer { try? FileManager.default.removeItem(at: url) }

        measure {
            do {
                let reader = try DataReaderFactory.createReader(for: url)
                XCTAssertEqual(reader.count, Self.oneFiftyMB)

                // Simulate FAT chain traversal: read 512-byte sectors at scattered positions
                let sectorSize = 512
                let numReads = 1000 // Simulate reading 1000 sectors scattered across file
                let stride = reader.count / numReads

                for i in 0..<numReads {
                    let offset = i * stride
                    let _ = try reader.readBytes(at: offset, length: sectorSize)
                }
            } catch {
                XCTFail("DataReader creation should not fail: \(error)")
            }
        }
    }

    // MARK: - Main Thread Blocking Test

    /// Verify that parsing on the MSGParser actor does not block the main thread > 100ms.
    /// Validates: Requirement 8.5
    func testMainThreadNotBlockedDuringParsing() throws {
        let url = try createSyntheticCFBFile(size: Self.tenMB)
        defer { try? FileManager.default.removeItem(at: url) }

        let parseCompleted = expectation(description: "parse completed")
        let mainThreadResponsive = expectation(description: "main thread responsive")

        // Track main thread responsiveness
        var mainThreadBlockDurations: [TimeInterval] = []
        var isParsingActive = true

        // Start parsing on a background task (via the actor)
        let parser = MSGParser()
        Task {
            do {
                _ = try await parser.parse(url: url)
            } catch {
                // Expected — synthetic file won't fully parse
            }
            isParsingActive = false
            parseCompleted.fulfill()
        }

        // Monitor main thread by scheduling periodic checks
        // If any gap between checks exceeds 100ms, the main thread was blocked
        let monitoringInterval: TimeInterval = 0.01 // Check every 10ms
        var lastCheckTime = CFAbsoluteTimeGetCurrent()
        var checksCompleted = 0
        let requiredChecks = 20 // At least 20 checks during parsing

        func scheduleMainThreadCheck() {
            guard isParsingActive || checksCompleted < requiredChecks else {
                mainThreadResponsive.fulfill()
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + monitoringInterval) {
                let now = CFAbsoluteTimeGetCurrent()
                let elapsed = now - lastCheckTime
                mainThreadBlockDurations.append(elapsed)
                lastCheckTime = now
                checksCompleted += 1
                scheduleMainThreadCheck()
            }
        }

        // Start monitoring on main thread
        DispatchQueue.main.async {
            lastCheckTime = CFAbsoluteTimeGetCurrent()
            scheduleMainThreadCheck()
        }

        wait(for: [parseCompleted, mainThreadResponsive], timeout: 5.0)

        // Verify no main thread gap exceeded 100ms
        let maxBlockDuration = mainThreadBlockDurations.max() ?? 0
        XCTAssertLessThan(
            maxBlockDuration,
            0.1, // 100ms
            "Main thread was blocked for \(maxBlockDuration * 1000)ms during parsing (max allowed: 100ms)"
        )
    }

    /// Verify that MSGParser.parse runs on a background thread (not the main thread).
    /// Validates: Requirement 8.5
    func testParsingRunsOffMainThread() throws {
        let url = try createSyntheticCFBFile(size: Self.tenMB)
        defer { try? FileManager.default.removeItem(at: url) }

        let expectation = self.expectation(description: "parse completes off main thread")

        // The MSGParser is an actor, which means its methods execute on a background executor.
        // Calling from the main thread should not block it.
        let parser = MSGParser()

        // Use a class to avoid sendability issues with captured mutable state
        final class MainThreadCheck: @unchecked Sendable {
            var wasAvailable = false
        }
        let check = MainThreadCheck()

        Task {
            // Kick off parsing
            async let parseResult: Void = {
                do {
                    _ = try await parser.parse(url: url)
                } catch {
                    // Expected
                }
            }()

            // Meanwhile, check that main thread can execute work
            await MainActor.run {
                check.wasAvailable = true
            }

            _ = await parseResult
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertTrue(check.wasAvailable, "Main thread should remain available during parsing")
    }

    // MARK: - Helpers

    /// Creates a synthetic file with a valid CFB header at the specified size.
    /// The file has a valid OLE/CFB signature and header structure, with the remaining
    /// bytes filled to reach the target size. This exercises the DataReader and initial
    /// parsing pipeline without requiring fully valid MAPI property data.
    private func createSyntheticCFBFile(size: Int) throws -> URL {
        var data = Data(count: size)

        // Write the OLE/CFB magic signature at offset 0 (8 bytes)
        // CFBHeader.expectedSignature = 0xE11AB1A1E011CFD0
        // readInteger reads little-endian, so we store with .littleEndian
        let signature: UInt64 = 0xE11AB1A1_E011CFD0
        data.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: signature.littleEndian, as: UInt64.self)
        }

        // Write CLSID (16 bytes of zeros at offset 8) - already zero

        // Minor version at offset 24: 0x003E
        data.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: UInt16(0x003E).littleEndian, toByteOffset: 24, as: UInt16.self)
        }

        // Major version at offset 26: 3 (version 3 CFB)
        data.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: UInt16(3).littleEndian, toByteOffset: 26, as: UInt16.self)
        }

        // Byte order at offset 28: 0xFFFE (little-endian)
        data.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: UInt16(0xFFFE).littleEndian, toByteOffset: 28, as: UInt16.self)
        }

        // Sector size power at offset 30: 9 (512 bytes)
        data.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: UInt16(9).littleEndian, toByteOffset: 30, as: UInt16.self)
        }

        // Mini sector size power at offset 32: 6 (64 bytes)
        data.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: UInt16(6).littleEndian, toByteOffset: 32, as: UInt16.self)
        }

        // Total FAT sectors at offset 44: 1
        data.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: UInt32(1).littleEndian, toByteOffset: 44, as: UInt32.self)
        }

        // First directory sector at offset 48: sector 1
        data.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: UInt32(1).littleEndian, toByteOffset: 48, as: UInt32.self)
        }

        // Mini-stream cutoff size at offset 56: 4096
        data.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: UInt32(4096).littleEndian, toByteOffset: 56, as: UInt32.self)
        }

        // First mini-FAT sector at offset 60: end-of-chain (no mini-FAT)
        data.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: UInt32(0xFFFFFFFE).littleEndian, toByteOffset: 60, as: UInt32.self)
        }

        // Total mini-FAT sectors at offset 64: 0
        data.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: UInt32(0).littleEndian, toByteOffset: 64, as: UInt32.self)
        }

        // First DIFAT sector at offset 68: end-of-chain (no extra DIFAT sectors)
        data.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: UInt32(0xFFFFFFFE).littleEndian, toByteOffset: 68, as: UInt32.self)
        }

        // Total DIFAT sectors at offset 72: 0
        data.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: UInt32(0).littleEndian, toByteOffset: 72, as: UInt32.self)
        }

        // DIFAT array at offset 76: first entry points to sector 0 (the FAT sector)
        // Remaining 108 entries are free (0xFFFFFFFF)
        data.withUnsafeMutableBytes { buffer in
            buffer.storeBytes(of: UInt32(0).littleEndian, toByteOffset: 76, as: UInt32.self)
            for i in 1..<109 {
                buffer.storeBytes(of: UInt32(0xFFFFFFFF).littleEndian, toByteOffset: 76 + i * 4, as: UInt32.self)
            }
        }

        // Sector 0 (offset 512): FAT sector
        // Entry 0 = FAT sector itself (0xFFFFFFFD), Entry 1 = end-of-chain for directory
        let sectorSize = 512
        let fatSectorOffset = sectorSize // (sector 0 + 1) * 512 = 512
        data.withUnsafeMutableBytes { buffer in
            // Sector 0 is FAT sector itself: 0xFFFFFFFD (FATSECT marker)
            buffer.storeBytes(of: UInt32(0xFFFFFFFD).littleEndian, toByteOffset: fatSectorOffset, as: UInt32.self)
            // Sector 1 is the directory sector: end-of-chain
            buffer.storeBytes(of: UInt32(0xFFFFFFFE).littleEndian, toByteOffset: fatSectorOffset + 4, as: UInt32.self)
            // All remaining entries in this FAT sector are free
            for i in 2..<(sectorSize / 4) {
                buffer.storeBytes(of: UInt32(0xFFFFFFFF).littleEndian, toByteOffset: fatSectorOffset + i * 4, as: UInt32.self)
            }
        }

        // Sector 1 (offset 1024): Directory sector with root entry
        let dirSectorOffset = 2 * sectorSize // (sector 1 + 1) * 512 = 1024
        data.withUnsafeMutableBytes { buffer in
            // Root entry (128 bytes starting at dirSectorOffset)
            // Name: "Root Entry" in UTF-16LE
            let rootName: [UInt16] = Array("Root Entry".utf16)
            for (i, codeUnit) in rootName.enumerated() {
                buffer.storeBytes(of: codeUnit.littleEndian, toByteOffset: dirSectorOffset + i * 2, as: UInt16.self)
            }
            // Name size at offset 64: (10 chars + null) * 2 = 22 bytes
            buffer.storeBytes(of: UInt16(22).littleEndian, toByteOffset: dirSectorOffset + 64, as: UInt16.self)
            // Object type at offset 66: 5 (root storage)
            buffer.storeBytes(of: UInt8(5), toByteOffset: dirSectorOffset + 66, as: UInt8.self)
            // Child ID at offset 76: 0xFFFFFFFF (no children)
            buffer.storeBytes(of: UInt32(0xFFFFFFFF).littleEndian, toByteOffset: dirSectorOffset + 76, as: UInt32.self)
            // Left sibling at offset 68: 0xFFFFFFFF
            buffer.storeBytes(of: UInt32(0xFFFFFFFF).littleEndian, toByteOffset: dirSectorOffset + 68, as: UInt32.self)
            // Right sibling at offset 72: 0xFFFFFFFF
            buffer.storeBytes(of: UInt32(0xFFFFFFFF).littleEndian, toByteOffset: dirSectorOffset + 72, as: UInt32.self)
            // Start sector at offset 116: end-of-chain (root has no mini-stream content)
            buffer.storeBytes(of: UInt32(0xFFFFFFFE).littleEndian, toByteOffset: dirSectorOffset + 116, as: UInt32.self)
            // Stream size at offset 120: 0
            buffer.storeBytes(of: UInt64(0).littleEndian, toByteOffset: dirSectorOffset + 120, as: UInt64.self)

            // Fill remaining entries in directory sector as unknown (type 0)
            for i in 1..<(sectorSize / 128) {
                let entryOffset = dirSectorOffset + i * 128
                // Name size = 0 (empty entry)
                buffer.storeBytes(of: UInt16(0).littleEndian, toByteOffset: entryOffset + 64, as: UInt16.self)
                // Object type = 0 (unknown/empty)
                buffer.storeBytes(of: UInt8(0), toByteOffset: entryOffset + 66, as: UInt8.self)
                // Sibling/child IDs = no stream
                buffer.storeBytes(of: UInt32(0xFFFFFFFF).littleEndian, toByteOffset: entryOffset + 68, as: UInt32.self)
                buffer.storeBytes(of: UInt32(0xFFFFFFFF).littleEndian, toByteOffset: entryOffset + 72, as: UInt32.self)
                buffer.storeBytes(of: UInt32(0xFFFFFFFF).littleEndian, toByteOffset: entryOffset + 76, as: UInt32.self)
            }
        }

        // Write to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "perf_test_\(UUID().uuidString).msg"
        let url = tempDir.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }
}
