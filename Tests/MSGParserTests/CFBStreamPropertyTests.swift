// MSGParserTests - Property-based tests for FAT chain stream reconstruction
// Feature: msg-file-viewer, Property 2: FAT Chain Stream Reconstruction

import XCTest
import SwiftCheck
import Foundation
@testable import MSGParser

/// End-of-chain marker used in FAT/mini-FAT.
private let endOfChain: UInt32 = 0xFFFFFFFE

// MARK: - Generators

/// Generates random byte arrays with size >= 4096 bytes (uses regular FAT path).
/// The size is constrained to a reasonable range for testing.
private func regularStreamBytesGen() -> Gen<[UInt8]> {
    return Gen<[UInt8]>.compose { composer in
        let size = composer.generate(using: Gen<Int>.choose((4096, 8192)))
        return (0..<size).map { _ in composer.generate(using: Gen<UInt8>.choose((0, 255))) }
    }
}

/// Generates random byte arrays with size 1..<4096 bytes (uses mini-FAT path).
/// Minimum size is 1 byte to ensure we have at least one mini-sector.
private func miniStreamBytesGen() -> Gen<[UInt8]> {
    return Gen<[UInt8]>.compose { composer in
        let size = composer.generate(using: Gen<Int>.choose((1, 4095)))
        return (0..<size).map { _ in composer.generate(using: Gen<UInt8>.choose((0, 255))) }
    }
}

// MARK: - Helper Functions

/// Builds a synthetic file Data for regular FAT stream testing.
/// Layout: 512-byte header padding + sectors at (sectorIndex + 1) * 512.
/// The FAT is a simple linear chain: 0 -> 1 -> 2 -> ... -> endOfChain.
///
/// - Parameters:
///   - streamData: The original stream data to split across sectors.
///   - sectorSize: The sector size (512 bytes).
/// - Returns: A tuple of (fileData, fat, directoryEntry, header).
private func buildRegularFATStructure(streamData: Data, sectorSize: Int = 512) -> (Data, [UInt32], DirectoryEntry, CFBHeader) {
    let sectorCount = (streamData.count + sectorSize - 1) / sectorSize

    // Build the FAT: linear chain 0 -> 1 -> 2 -> ... -> endOfChain
    var fat = [UInt32]()
    for i in 0..<sectorCount {
        if i == sectorCount - 1 {
            fat.append(endOfChain)
        } else {
            fat.append(UInt32(i + 1))
        }
    }

    // Build file data: 512-byte header pad + sector data
    // Each sector is placed at offset (sectorIndex + 1) * sectorSize
    var fileData = Data(count: sectorSize) // header padding (sector 0 area is at offset sectorSize)

    for i in 0..<sectorCount {
        let start = i * sectorSize
        let end = min(start + sectorSize, streamData.count)
        var sectorData = Data(streamData[start..<end])
        // Pad last sector to full size if needed
        if sectorData.count < sectorSize {
            sectorData.append(Data(count: sectorSize - sectorData.count))
        }
        fileData.append(sectorData)
    }

    // Create a DirectoryEntry pointing to the first sector
    let entry = DirectoryEntry(
        name: "TestStream",
        objectType: .stream,
        startSector: 0,
        streamSize: UInt64(streamData.count),
        childID: 0xFFFFFFFF,
        leftSiblingID: 0xFFFFFFFF,
        rightSiblingID: 0xFFFFFFFF
    )

    // Create a minimal CFBHeader
    let header = CFBHeader(
        signature: CFBHeader.expectedSignature,
        minorVersion: 0x003E,
        majorVersion: 3,
        byteOrder: 0xFFFE,
        sectorSizePower: 9, // 512 bytes
        miniSectorSizePower: 6, // 64 bytes
        totalFATSectors: 1,
        firstDirectorySector: 0,
        miniStreamCutoffSize: 4096,
        firstMiniFATSector: endOfChain,
        totalMiniFATSectors: 0,
        firstDIFATSector: endOfChain,
        totalDIFATSectors: 0,
        difatArray: []
    )

    return (fileData, fat, entry, header)
}

/// Builds a synthetic mini-stream structure for mini-FAT stream testing.
/// The miniStream is constructed by concatenating mini-sectors.
/// The miniFAT is a simple linear chain: 0 -> 1 -> 2 -> ... -> endOfChain.
///
/// - Parameters:
///   - streamData: The original stream data to split across mini-sectors.
///   - miniSectorSize: The mini-sector size (64 bytes).
/// - Returns: A tuple of (miniStream, miniFAT, directoryEntry, header).
private func buildMiniFATStructure(streamData: Data, miniSectorSize: Int = 64) -> (Data, [UInt32], DirectoryEntry, CFBHeader) {
    let miniSectorCount = (streamData.count + miniSectorSize - 1) / miniSectorSize

    // Build the mini-FAT: linear chain 0 -> 1 -> 2 -> ... -> endOfChain
    var miniFAT = [UInt32]()
    for i in 0..<miniSectorCount {
        if i == miniSectorCount - 1 {
            miniFAT.append(endOfChain)
        } else {
            miniFAT.append(UInt32(i + 1))
        }
    }

    // Build miniStream by concatenating mini-sectors (padding last one if needed)
    var miniStream = Data()
    for i in 0..<miniSectorCount {
        let start = i * miniSectorSize
        let end = min(start + miniSectorSize, streamData.count)
        var sectorData = Data(streamData[start..<end])
        // Pad last mini-sector to full size if needed
        if sectorData.count < miniSectorSize {
            sectorData.append(Data(count: miniSectorSize - sectorData.count))
        }
        miniStream.append(sectorData)
    }

    // Create a DirectoryEntry pointing to the first mini-sector
    let entry = DirectoryEntry(
        name: "TestMiniStream",
        objectType: .stream,
        startSector: 0,
        streamSize: UInt64(streamData.count),
        childID: 0xFFFFFFFF,
        leftSiblingID: 0xFFFFFFFF,
        rightSiblingID: 0xFFFFFFFF
    )

    // Create a CFBHeader with miniStreamCutoffSize = 4096
    let header = CFBHeader(
        signature: CFBHeader.expectedSignature,
        minorVersion: 0x003E,
        majorVersion: 3,
        byteOrder: 0xFFFE,
        sectorSizePower: 9, // 512 bytes
        miniSectorSizePower: 6, // 64 bytes
        totalFATSectors: 1,
        firstDirectorySector: 0,
        miniStreamCutoffSize: 4096,
        firstMiniFATSector: 0,
        totalMiniFATSectors: 1,
        firstDIFATSector: endOfChain,
        totalDIFATSectors: 0,
        difatArray: []
    )

    return (miniStream, miniFAT, entry, header)
}

// MARK: - Property Tests

/// **Validates: Requirements 1.2, 1.3, 1.4**
final class CFBStreamPropertyTests: XCTestCase {

    // MARK: - Property 2a: Regular FAT Stream Reconstruction

    /// **Validates: Requirements 1.2, 1.3, 1.4**
    /// Generate random stream data >= 4096 bytes, split into 512-byte sectors,
    /// build a FAT chain, and verify readStream reconstructs the exact original data.
    func testRegularFATStreamReconstructionProperty() {
        property("Regular FAT stream reconstruction produces byte-for-byte identical data") <- forAll(regularStreamBytesGen()) { (bytes: [UInt8]) in
            let streamData = Data(bytes)
            let sectorSize = 512
            let (fileData, fat, entry, header) = buildRegularFATStructure(streamData: streamData, sectorSize: sectorSize)

            let reader = InMemoryDataReader(data: fileData)

            do {
                let reconstructed = try CFBReader.readStream(
                    entry: entry,
                    fat: fat,
                    miniFAT: [],
                    miniStream: Data(),
                    header: header,
                    reader: reader
                )
                return reconstructed == streamData
            } catch {
                return false
            }
        }
    }

    // MARK: - Property 2b: Mini-FAT Stream Reconstruction

    /// **Validates: Requirements 1.2, 1.3, 1.4**
    /// Generate random stream data < 4096 bytes, split into 64-byte mini-sectors,
    /// build a mini-FAT chain, and verify readStream reconstructs the exact original data.
    func testMiniFATStreamReconstructionProperty() {
        property("Mini-FAT stream reconstruction produces byte-for-byte identical data") <- forAll(miniStreamBytesGen()) { (bytes: [UInt8]) in
            let streamData = Data(bytes)
            let miniSectorSize = 64
            let (miniStream, miniFAT, entry, header) = buildMiniFATStructure(streamData: streamData, miniSectorSize: miniSectorSize)

            // For mini-stream path, the reader isn't used to read sector data directly,
            // but we still need a valid reader (miniStream data is passed separately).
            // Create a minimal reader with enough data to satisfy the reader.count check.
            let dummyFileData = Data(count: 512)
            let reader = InMemoryDataReader(data: dummyFileData)

            do {
                let reconstructed = try CFBReader.readStream(
                    entry: entry,
                    fat: [],
                    miniFAT: miniFAT,
                    miniStream: miniStream,
                    header: header,
                    reader: reader
                )
                return reconstructed == streamData
            } catch {
                return false
            }
        }
    }
}
