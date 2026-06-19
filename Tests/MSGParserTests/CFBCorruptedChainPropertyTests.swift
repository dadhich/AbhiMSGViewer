// MSGParserTests - Property-based tests for corrupted sector chain error reporting
// Feature: msg-file-viewer, Property 3: Corrupted Sector Chain Error Reporting

import XCTest
import SwiftCheck
import Foundation
@testable import MSGParser

// MARK: - Constants

/// End-of-chain marker in FAT/mini-FAT chains.
private let endOfChain: UInt32 = 0xFFFFFFFE
/// Free sector marker.
private let freeSector: UInt32 = 0xFFFFFFFF
/// Standard sector size for version 3 CFB files.
private let sectorSize = 512
/// Standard mini-sector size (64 bytes).
private let miniSectorSize = 64
/// Mini-stream cutoff (streams below this use mini-FAT).
private let miniStreamCutoff: UInt32 = 4096

// MARK: - Helpers

/// Creates a minimal CFBHeader for version 3 with specified parameters.
private func makeHeader(
    miniStreamCutoffSize: UInt32 = 4096,
    firstMiniFATSector: UInt32 = 0xFFFFFFFE,
    totalMiniFATSectors: UInt32 = 0
) -> CFBHeader {
    return CFBHeader(
        signature: CFBHeader.expectedSignature,
        minorVersion: 0x003E,
        majorVersion: 3,
        byteOrder: 0xFFFE,
        sectorSizePower: 9,          // 512 bytes
        miniSectorSizePower: 6,       // 64 bytes
        totalFATSectors: 1,
        firstDirectorySector: 0,
        miniStreamCutoffSize: miniStreamCutoffSize,
        firstMiniFATSector: firstMiniFATSector,
        totalMiniFATSectors: totalMiniFATSectors,
        firstDIFATSector: endOfChain,
        totalDIFATSectors: 0,
        difatArray: []
    )
}

/// Builds file data representing a valid CFB with sectors at standard offsets.
/// The data reader contains a 512-byte header pad + one 512-byte block per sector.
private func buildFileData(sectorCount: Int) -> Data {
    // Header (512 bytes) + sectorCount * 512 bytes
    let totalSize = sectorSize + sectorCount * sectorSize
    var data = Data(repeating: 0xAB, count: totalSize)
    // Fill each sector with its index byte pattern for identifiability
    for i in 0..<sectorCount {
        let offset = (i + 1) * sectorSize
        let fillByte = UInt8(i & 0xFF)
        for j in 0..<sectorSize {
            data[offset + j] = fillByte
        }
    }
    return data
}

/// Builds mini-stream container data with the given number of mini-sectors.
private func buildMiniStreamData(miniSectorCount: Int) -> Data {
    let totalSize = miniSectorCount * miniSectorSize
    var data = Data(repeating: 0xCD, count: totalSize)
    // Fill each mini-sector with its index byte pattern
    for i in 0..<miniSectorCount {
        let offset = i * miniSectorSize
        let fillByte = UInt8(i & 0xFF)
        for j in 0..<miniSectorSize {
            data[offset + j] = fillByte
        }
    }
    return data
}

// MARK: - Generators

/// Parameters for a corrupted regular FAT chain test case.
private struct CorruptedFATChainParams: Arbitrary {
    let chainLength: Int        // Number of sectors in the chain (>= 2)
    let corruptIndex: Int       // Index in the chain to corrupt (not the last)
    let invalidSectorID: UInt32 // The invalid sector ID to place at corruptIndex

    static var arbitrary: Gen<CorruptedFATChainParams> {
        return corruptedFATChainGen()
    }
}

/// Parameters for a corrupted mini-FAT chain test case.
private struct CorruptedMiniFATChainParams: Arbitrary {
    let chainLength: Int        // Number of mini-sectors in the chain (>= 2)
    let corruptIndex: Int       // Index in the chain to corrupt (not the last)
    let invalidSectorID: UInt32 // The invalid sector ID to place at corruptIndex

    static var arbitrary: Gen<CorruptedMiniFATChainParams> {
        return corruptedMiniFATChainGen()
    }
}

/// Generator for corrupted FAT chain parameters.
private func corruptedFATChainGen() -> Gen<CorruptedFATChainParams> {
    return Gen<CorruptedFATChainParams>.compose { composer in
        // Chain length between 2 and 10 sectors
        let chainLength = composer.generate(using: Gen<Int>.choose((2, 10)))
        // Corrupt any sector except the last (so there IS a next lookup that fails)
        let corruptIndex = composer.generate(using: Gen<Int>.choose((0, chainLength - 2)))
        // Invalid sector ID: guaranteed to be out of FAT bounds
        // FAT will have exactly chainLength entries, so anything >= chainLength is invalid
        let offset = composer.generate(using: Gen<UInt32>.choose((1000, 50000)))
        let invalidSectorID = UInt32(chainLength) + offset

        return CorruptedFATChainParams(
            chainLength: chainLength,
            corruptIndex: corruptIndex,
            invalidSectorID: invalidSectorID
        )
    }
}

/// Generator for corrupted mini-FAT chain parameters.
private func corruptedMiniFATChainGen() -> Gen<CorruptedMiniFATChainParams> {
    return Gen<CorruptedMiniFATChainParams>.compose { composer in
        // Chain length between 2 and 10 mini-sectors
        let chainLength = composer.generate(using: Gen<Int>.choose((2, 10)))
        // Corrupt any sector except the last
        let corruptIndex = composer.generate(using: Gen<Int>.choose((0, chainLength - 2)))
        // Invalid sector ID: guaranteed to be out of mini-FAT bounds
        let offset = composer.generate(using: Gen<UInt32>.choose((1000, 50000)))
        let invalidSectorID = UInt32(chainLength) + offset

        return CorruptedMiniFATChainParams(
            chainLength: chainLength,
            corruptIndex: corruptIndex,
            invalidSectorID: invalidSectorID
        )
    }
}

// MARK: - Property Tests

/// **Validates: Requirements 1.6**
final class CFBCorruptedChainPropertyTests: XCTestCase {

    // MARK: - Property 3a: Corrupted regular FAT chain error reporting

    /// **Validates: Requirements 1.6**
    /// Generate valid CFB structures with a stream spread across N sectors (N >= 2).
    /// Corrupt a single FAT entry to an invalid sector index.
    /// Verify that readStream throws CFBError.corruptedFile,
    /// the error description contains "corrupted file",
    /// and the test completes without crash or infinite loop.
    func testCorruptedRegularFATChainReportsError() {
        property("Corrupted regular FAT chain produces corruptedFile error with sector index") <- forAllNoShrink(corruptedFATChainGen()) { (params: CorruptedFATChainParams) in
            // Build a valid FAT chain: 0->1->2->...->endOfChain
            var fat = [UInt32]()
            for i in 0..<params.chainLength {
                if i == params.chainLength - 1 {
                    fat.append(endOfChain)
                } else {
                    fat.append(UInt32(i + 1))
                }
            }

            // Corrupt the FAT entry at corruptIndex to an invalid sector ID
            fat[params.corruptIndex] = params.invalidSectorID

            // The sector that will be read successfully before hitting the corrupted next pointer
            // is sector at corruptIndex. When we follow its FAT entry, we get invalidSectorID.
            // The error should report the invalidSectorID as the sector that's out of bounds.

            // Build file data with enough sectors
            let fileData = buildFileData(sectorCount: params.chainLength)
            let reader = InMemoryDataReader(data: fileData)

            // Create a directory entry pointing to the start of the chain
            let streamSize = UInt64(params.chainLength * sectorSize)
            let entry = DirectoryEntry(
                name: "TestStream",
                objectType: .stream,
                startSector: 0,
                streamSize: streamSize,
                childID: freeSector,
                leftSiblingID: freeSector,
                rightSiblingID: freeSector
            )

            // Use miniStreamCutoffSize = 0 to force all streams through regular FAT path
            let header = makeHeader(miniStreamCutoffSize: 0)

            do {
                _ = try CFBReader.readStream(
                    entry: entry,
                    fat: fat,
                    miniFAT: [],
                    miniStream: Data(),
                    header: header,
                    reader: reader
                )
                // Should have thrown - test fails
                return false
            } catch let error as CFBError {
                switch error {
                case .corruptedFile(let sectorIndex, _):
                    // Verify the error description contains "corrupted file"
                    let desc = error.description
                    let containsCorrupted = desc.contains("corrupted file")
                    // The sectorIndex should be the invalid sector ID that was out of bounds
                    let correctSector = sectorIndex == params.invalidSectorID
                    return containsCorrupted && correctSector
                default:
                    return false
                }
            } catch {
                // Non-CFBError is unexpected
                return false
            }
        }
    }

    // MARK: - Property 3b: Corrupted mini-FAT chain error reporting

    /// **Validates: Requirements 1.6**
    /// Generate valid CFB structures with a mini-stream spread across N mini-sectors (N >= 2).
    /// Corrupt a single mini-FAT entry to an invalid sector index.
    /// Verify that readStream throws CFBError.corruptedFile,
    /// the error description contains "corrupted file",
    /// and the test completes without crash or infinite loop.
    func testCorruptedMiniFATChainReportsError() {
        property("Corrupted mini-FAT chain produces corruptedFile error with sector index") <- forAllNoShrink(corruptedMiniFATChainGen()) { (params: CorruptedMiniFATChainParams) in
            // Build a valid mini-FAT chain: 0->1->2->...->endOfChain
            var miniFAT = [UInt32]()
            for i in 0..<params.chainLength {
                if i == params.chainLength - 1 {
                    miniFAT.append(endOfChain)
                } else {
                    miniFAT.append(UInt32(i + 1))
                }
            }

            // Corrupt the mini-FAT entry at corruptIndex to an invalid sector ID
            miniFAT[params.corruptIndex] = params.invalidSectorID

            // Build mini-stream container data with enough mini-sectors
            let miniStreamData = buildMiniStreamData(miniSectorCount: params.chainLength)

            // Stream size must be < 4096 to use mini-FAT path
            let streamSize = UInt64(params.chainLength * miniSectorSize)
            // Ensure stream size is less than cutoff
            guard streamSize < UInt64(miniStreamCutoff) else {
                // If the generated stream is >= 4096, it won't use mini-FAT.
                // With chainLength <= 10 and miniSectorSize = 64, max is 640 < 4096, so this is safe.
                return true
            }

            let entry = DirectoryEntry(
                name: "MiniTestStream",
                objectType: .stream,
                startSector: 0,
                streamSize: streamSize,
                childID: freeSector,
                leftSiblingID: freeSector,
                rightSiblingID: freeSector
            )

            let header = makeHeader()
            // Use a minimal file data (just header) since mini-stream reads from miniStream container
            let fileData = Data(repeating: 0, count: sectorSize)
            let reader = InMemoryDataReader(data: fileData)

            do {
                _ = try CFBReader.readStream(
                    entry: entry,
                    fat: [],
                    miniFAT: miniFAT,
                    miniStream: miniStreamData,
                    header: header,
                    reader: reader
                )
                // Should have thrown - test fails
                return false
            } catch let error as CFBError {
                switch error {
                case .corruptedFile(let sectorIndex, _):
                    // Verify the error description contains "corrupted file"
                    let desc = error.description
                    let containsCorrupted = desc.contains("corrupted file")
                    // The sectorIndex should be the invalid sector ID that was out of bounds
                    let correctSector = sectorIndex == params.invalidSectorID
                    return containsCorrupted && correctSector
                default:
                    return false
                }
            } catch {
                // Non-CFBError is unexpected
                return false
            }
        }
    }
}
