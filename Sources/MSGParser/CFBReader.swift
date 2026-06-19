// MSGParser - CFB Reader
// Parses the Compound File Binary Format header and validates structure

import Foundation

/// Reads and parses CFB (Compound File Binary Format) structures from raw data.
public struct CFBReader {

    // MARK: - Constants

    /// End-of-chain marker in FAT/DIFAT chains.
    private static let endOfChain: UInt32 = 0xFFFFFFFE
    /// Free sector marker.
    private static let freeSector: UInt32 = 0xFFFFFFFF

    // MARK: - FAT Building

    /// Builds the complete File Allocation Table by reading all FAT sectors.
    /// Follows the DIFAT chain for files with more than 109 FAT sectors.
    ///
    /// - Parameters:
    ///   - header: The parsed CFB header.
    ///   - reader: The data reader for the file.
    /// - Returns: An array of UInt32 values representing the complete FAT.
    /// - Throws: `CFBError.corruptedFile` if a DIFAT chain cycle is detected.
    public static func buildFAT(header: CFBHeader, reader: DataReader) throws -> [UInt32] {
        let sectorSize = header.sectorSize
        var fat = [UInt32]()

        // Step 1: Read FAT sectors referenced by the first 109 DIFAT entries in the header
        for entry in header.difatArray {
            if entry == freeSector || entry == endOfChain {
                continue
            }
            let offset = (Int(entry) + 1) * sectorSize
            let sectorData = try reader.readBytes(at: offset, length: sectorSize)
            let entriesPerSector = sectorSize / 4
            for i in 0..<entriesPerSector {
                let value: UInt32 = sectorData.withUnsafeBytes { buffer in
                    buffer.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)
                }
                fat.append(UInt32(littleEndian: value))
            }
        }

        // Step 2: Follow DIFAT chain if there are more than 109 FAT sectors
        if header.totalDIFATSectors > 0 {
            var currentDIFATSector = header.firstDIFATSector
            let maxIterations = reader.count / sectorSize
            var visited = Set<UInt32>()

            while currentDIFATSector != endOfChain && currentDIFATSector != freeSector {
                // Cycle detection
                guard !visited.contains(currentDIFATSector) else {
                    throw CFBError.corruptedFile(
                        sectorIndex: currentDIFATSector,
                        reason: "DIFAT chain cycle detected"
                    )
                }
                visited.insert(currentDIFATSector)

                if visited.count > maxIterations {
                    throw CFBError.corruptedFile(
                        sectorIndex: currentDIFATSector,
                        reason: "DIFAT chain cycle detected"
                    )
                }

                // Read the DIFAT sector
                let difatOffset = (Int(currentDIFATSector) + 1) * sectorSize
                let difatData = try reader.readBytes(at: difatOffset, length: sectorSize)

                // Each DIFAT sector has (sectorSize/4 - 1) FAT sector IDs
                // and the last UInt32 is the pointer to the next DIFAT sector
                let entriesInDIFATSector = sectorSize / 4 - 1

                for i in 0..<entriesInDIFATSector {
                    let fatSectorID: UInt32 = difatData.withUnsafeBytes { buffer in
                        buffer.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)
                    }
                    let fatSectorIDLE = UInt32(littleEndian: fatSectorID)

                    if fatSectorIDLE == freeSector || fatSectorIDLE == endOfChain {
                        continue
                    }

                    // Read the FAT sector
                    let fatSectorOffset = (Int(fatSectorIDLE) + 1) * sectorSize
                    let fatSectorData = try reader.readBytes(at: fatSectorOffset, length: sectorSize)
                    let entriesPerSector = sectorSize / 4
                    for j in 0..<entriesPerSector {
                        let value: UInt32 = fatSectorData.withUnsafeBytes { buffer in
                            buffer.loadUnaligned(fromByteOffset: j * 4, as: UInt32.self)
                        }
                        fat.append(UInt32(littleEndian: value))
                    }
                }

                // Read the next DIFAT sector pointer (last 4 bytes)
                let nextPointer: UInt32 = difatData.withUnsafeBytes { buffer in
                    buffer.loadUnaligned(fromByteOffset: entriesInDIFATSector * 4, as: UInt32.self)
                }
                currentDIFATSector = UInt32(littleEndian: nextPointer)
            }
        }

        return fat
    }

    // MARK: - Header Parsing

    /// Parses the 512-byte CFB header from the given data reader.
    ///
    /// - Parameter reader: A `DataReader` positioned at the start of the CFB file.
    /// - Returns: A validated `CFBHeader` containing all parsed fields.
    /// - Throws: `CFBError.invalidSignature` if the magic bytes don't match,
    ///           `CFBError.unsupportedVersion` if the major version is not 3 or 4.
    public static func readHeader(from reader: DataReader) throws -> CFBHeader {
        // Read and validate the 8-byte magic signature at offset 0
        let signature: UInt64 = try reader.readInteger(at: 0)
        guard signature == CFBHeader.expectedSignature else {
            // Display signatures in file byte order (big-endian) for human readability
            let expected = String(format: "0x%016llX", CFBHeader.expectedSignature.bigEndian)
            let found = String(format: "0x%016llX", signature.bigEndian)
            throw CFBError.invalidSignature(expected: expected, found: found)
        }

        // Read version fields
        let minorVersion: UInt16 = try reader.readInteger(at: 24)
        let majorVersion: UInt16 = try reader.readInteger(at: 26)

        // Validate major version (only 3 and 4 are supported)
        guard majorVersion == 3 || majorVersion == 4 else {
            throw CFBError.unsupportedVersion(majorVersion)
        }

        // Read byte order
        let byteOrder: UInt16 = try reader.readInteger(at: 28)

        // Read sector size powers
        let sectorSizePower: UInt16 = try reader.readInteger(at: 30)
        let miniSectorSizePower: UInt16 = try reader.readInteger(at: 32)

        // Read FAT and directory information
        let totalFATSectors: UInt32 = try reader.readInteger(at: 44)
        let firstDirectorySector: UInt32 = try reader.readInteger(at: 48)

        // Read mini-stream fields
        let miniStreamCutoffSize: UInt32 = try reader.readInteger(at: 56)
        let firstMiniFATSector: UInt32 = try reader.readInteger(at: 60)
        let totalMiniFATSectors: UInt32 = try reader.readInteger(at: 64)

        // Read DIFAT fields
        let firstDIFATSector: UInt32 = try reader.readInteger(at: 68)
        let totalDIFATSectors: UInt32 = try reader.readInteger(at: 72)

        // Parse the first 109 DIFAT entries starting at offset 76
        var difatArray = [UInt32]()
        difatArray.reserveCapacity(109)
        for i in 0..<109 {
            let offset = 76 + (i * 4)
            let entry: UInt32 = try reader.readInteger(at: offset)
            difatArray.append(entry)
        }

        return CFBHeader(
            signature: signature,
            minorVersion: minorVersion,
            majorVersion: majorVersion,
            byteOrder: byteOrder,
            sectorSizePower: sectorSizePower,
            miniSectorSizePower: miniSectorSizePower,
            totalFATSectors: totalFATSectors,
            firstDirectorySector: firstDirectorySector,
            miniStreamCutoffSize: miniStreamCutoffSize,
            firstMiniFATSector: firstMiniFATSector,
            totalMiniFATSectors: totalMiniFATSectors,
            firstDIFATSector: firstDIFATSector,
            totalDIFATSectors: totalDIFATSectors,
            difatArray: difatArray
        )
    }

    // MARK: - Directory Entry Parsing

    /// Parses all directory entries from the directory sector chain.
    ///
    /// Each directory entry is 128 bytes. The method follows the directory sector chain
    /// via the FAT starting at `header.firstDirectorySector`.
    ///
    /// - Parameters:
    ///   - header: The parsed CFB header.
    ///   - fat: The complete FAT array (built by buildFAT).
    ///   - reader: The data reader for the file.
    /// - Returns: An array of `DirectoryEntry` values parsed from the directory stream.
    /// - Throws: `CFBError.corruptedFile` if the directory chain is invalid or a cycle is detected.
    public static func readDirectoryEntries(header: CFBHeader, fat: [UInt32], reader: DataReader) throws -> [DirectoryEntry] {
        let sectorSize = header.sectorSize
        let entriesPerSector = sectorSize / 128
        let maxSectors = reader.count / sectorSize

        var entries = [DirectoryEntry]()
        var currentSector = header.firstDirectorySector
        var visited = Set<UInt32>()

        while currentSector != endOfChain && currentSector != freeSector {
            // Cycle detection
            guard !visited.contains(currentSector) else {
                throw CFBError.corruptedFile(
                    sectorIndex: currentSector,
                    reason: "directory sector chain cycle detected"
                )
            }
            visited.insert(currentSector)

            if visited.count > maxSectors {
                throw CFBError.corruptedFile(
                    sectorIndex: currentSector,
                    reason: "directory sector chain cycle detected"
                )
            }

            // Validate sector index is within FAT bounds
            guard Int(currentSector) < fat.count else {
                throw CFBError.corruptedFile(
                    sectorIndex: currentSector,
                    reason: "directory sector index out of FAT bounds"
                )
            }

            // Calculate file offset: (sectorID + 1) * sectorSize
            let sectorOffset = (Int(currentSector) + 1) * sectorSize

            // Read the entire sector
            let sectorData = try reader.readBytes(at: sectorOffset, length: sectorSize)

            // Parse each 128-byte directory entry in this sector
            for i in 0..<entriesPerSector {
                let entryOffset = i * 128

                // Bytes 64-65: Name size in bytes (including null terminator)
                let nameSize: UInt16 = sectorData.withUnsafeBytes { buffer in
                    UInt16(littleEndian: buffer.loadUnaligned(fromByteOffset: entryOffset + 64, as: UInt16.self))
                }

                // Bytes 0-63: Entry name in UTF-16LE
                let name: String
                if nameSize > 2 {
                    // nameSize includes the null terminator (2 bytes for UTF-16), so subtract 2
                    let nameBytesCount = min(Int(nameSize) - 2, 64)
                    let nameData = sectorData[sectorData.startIndex + entryOffset ..< sectorData.startIndex + entryOffset + nameBytesCount]
                    name = String(data: nameData, encoding: .utf16LittleEndian) ?? ""
                } else {
                    name = ""
                }

                // Byte 66: Object type
                let objectTypeByte: UInt8 = sectorData.withUnsafeBytes { buffer in
                    buffer.loadUnaligned(fromByteOffset: entryOffset + 66, as: UInt8.self)
                }
                let objectType = ObjectType(rawValue: objectTypeByte) ?? .unknown

                // Bytes 68-71: Left sibling ID (UInt32)
                let leftSiblingID: UInt32 = sectorData.withUnsafeBytes { buffer in
                    UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: entryOffset + 68, as: UInt32.self))
                }

                // Bytes 72-75: Right sibling ID (UInt32)
                let rightSiblingID: UInt32 = sectorData.withUnsafeBytes { buffer in
                    UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: entryOffset + 72, as: UInt32.self))
                }

                // Bytes 76-79: Child ID (UInt32)
                let childID: UInt32 = sectorData.withUnsafeBytes { buffer in
                    UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: entryOffset + 76, as: UInt32.self))
                }

                // Bytes 116-119: Start sector (UInt32)
                let startSector: UInt32 = sectorData.withUnsafeBytes { buffer in
                    UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: entryOffset + 116, as: UInt32.self))
                }

                // Bytes 120-127: Stream size (UInt64)
                let streamSizeRaw: UInt64 = sectorData.withUnsafeBytes { buffer in
                    UInt64(littleEndian: buffer.loadUnaligned(fromByteOffset: entryOffset + 120, as: UInt64.self))
                }
                // For version 3, only lower 32 bits are used
                let streamSize: UInt64
                if header.majorVersion == 3 {
                    streamSize = streamSizeRaw & 0xFFFFFFFF
                } else {
                    streamSize = streamSizeRaw
                }

                let entry = DirectoryEntry(
                    name: name,
                    objectType: objectType,
                    startSector: startSector,
                    streamSize: streamSize,
                    childID: childID,
                    leftSiblingID: leftSiblingID,
                    rightSiblingID: rightSiblingID
                )
                entries.append(entry)
            }

            // Follow the FAT chain to the next directory sector
            currentSector = fat[Int(currentSector)]
        }

        return entries
    }

    // MARK: - Stream Reading

    /// Reads a stream's complete data by following its FAT or mini-FAT chain.
    ///
    /// For streams smaller than `header.miniStreamCutoffSize` (4096 bytes), the mini-FAT
    /// is used and data is read from the miniStream container. For larger streams, the
    /// regular FAT is used and data is read directly from the file sectors.
    ///
    /// - Parameters:
    ///   - entry: The directory entry describing the stream.
    ///   - fat: The complete FAT array.
    ///   - miniFAT: The mini-FAT array for small streams.
    ///   - miniStream: The mini-stream container data (root entry's stream).
    ///   - header: The parsed CFB header.
    ///   - reader: The data reader for the file.
    /// - Returns: The complete stream data trimmed to the entry's stream size.
    /// - Throws: `CFBError.corruptedFile` if the chain is invalid or contains cycles.
    public static func readStream(
        entry: DirectoryEntry,
        fat: [UInt32],
        miniFAT: [UInt32],
        miniStream: Data,
        header: CFBHeader,
        reader: DataReader
    ) throws -> Data {
        let streamSize = Int(entry.streamSize)

        // Empty stream
        if streamSize == 0 {
            return Data()
        }

        let useMiniStream = entry.streamSize < UInt64(header.miniStreamCutoffSize)

        if useMiniStream {
            return try readMiniStream(
                startSector: entry.startSector,
                streamSize: streamSize,
                miniFAT: miniFAT,
                miniStream: miniStream,
                miniSectorSize: header.miniSectorSize
            )
        } else {
            return try readRegularStream(
                startSector: entry.startSector,
                streamSize: streamSize,
                fat: fat,
                sectorSize: header.sectorSize,
                reader: reader
            )
        }
    }

    /// Reads a stream using the regular FAT for large streams (>= miniStreamCutoffSize).
    private static func readRegularStream(
        startSector: UInt32,
        streamSize: Int,
        fat: [UInt32],
        sectorSize: Int,
        reader: DataReader
    ) throws -> Data {
        var result = Data()
        result.reserveCapacity(streamSize)

        var currentSector = startSector
        // Cycle detection: max iterations based on how many sectors we could possibly need
        let maxIterations = (streamSize + sectorSize - 1) / sectorSize + 1
        var iterations = 0

        while currentSector != endOfChain {
            iterations += 1
            if iterations > maxIterations {
                throw CFBError.corruptedFile(
                    sectorIndex: currentSector,
                    reason: "FAT chain cycle detected or chain too long"
                )
            }

            // Validate sector index is within FAT bounds
            guard Int(currentSector) < fat.count else {
                throw CFBError.corruptedFile(
                    sectorIndex: currentSector,
                    reason: "sector index out of FAT bounds"
                )
            }

            // Calculate file offset: (sectorIndex + 1) * sectorSize
            let fileOffset = (Int(currentSector) + 1) * sectorSize
            let sectorData = try reader.readBytes(at: fileOffset, length: sectorSize)
            result.append(sectorData)

            // Follow the FAT chain to the next sector
            currentSector = fat[Int(currentSector)]
        }

        // Trim to actual stream size
        if result.count > streamSize {
            result = result.prefix(streamSize)
        }

        return result
    }

    /// Reads a stream using the mini-FAT for small streams (< miniStreamCutoffSize).
    private static func readMiniStream(
        startSector: UInt32,
        streamSize: Int,
        miniFAT: [UInt32],
        miniStream: Data,
        miniSectorSize: Int
    ) throws -> Data {
        var result = Data()
        result.reserveCapacity(streamSize)

        var currentSector = startSector
        // Cycle detection: max iterations based on how many mini-sectors we could possibly need
        let maxIterations = (streamSize + miniSectorSize - 1) / miniSectorSize + 1
        var iterations = 0

        while currentSector != endOfChain {
            iterations += 1
            if iterations > maxIterations {
                throw CFBError.corruptedFile(
                    sectorIndex: currentSector,
                    reason: "mini-FAT chain cycle detected or chain too long"
                )
            }

            // Validate sector index is within mini-FAT bounds
            guard Int(currentSector) < miniFAT.count else {
                throw CFBError.corruptedFile(
                    sectorIndex: currentSector,
                    reason: "sector index out of mini-FAT bounds"
                )
            }

            // Calculate offset into miniStream: sectorIndex * miniSectorSize
            let miniOffset = Int(currentSector) * miniSectorSize
            let endOffset = miniOffset + miniSectorSize

            // Validate the offset is within the miniStream data
            guard endOffset <= miniStream.count else {
                throw CFBError.corruptedFile(
                    sectorIndex: currentSector,
                    reason: "mini-stream offset exceeds mini-stream container size"
                )
            }

            let sectorData = miniStream[miniStream.startIndex + miniOffset ..< miniStream.startIndex + endOffset]
            result.append(sectorData)

            // Follow the mini-FAT chain to the next sector
            currentSector = miniFAT[Int(currentSector)]
        }

        // Trim to actual stream size
        if result.count > streamSize {
            result = result.prefix(streamSize)
        }

        return result
    }

    // MARK: - Mini-FAT Building

    /// Builds the mini-FAT by reading all mini-FAT sectors following the chain from the header.
    ///
    /// - Parameters:
    ///   - header: The parsed CFB header.
    ///   - fat: The complete FAT array (built by buildFAT).
    ///   - reader: The data reader for the file.
    /// - Returns: An array of UInt32 values representing the mini-FAT.
    /// - Throws: `CFBError.corruptedFile` if the chain is invalid.
    public static func buildMiniFAT(header: CFBHeader, fat: [UInt32], reader: DataReader) throws -> [UInt32] {
        let endOfChain: UInt32 = 0xFFFFFFFE

        // If there are no mini-FAT sectors, return empty
        if header.totalMiniFATSectors == 0 || header.firstMiniFATSector == endOfChain {
            return []
        }

        let sectorSize = header.sectorSize
        let entriesPerSector = sectorSize / 4
        let maxSectors = max(Int(header.totalMiniFATSectors), reader.count / sectorSize)

        var miniFAT = [UInt32]()
        var currentSector = header.firstMiniFATSector
        var visitedCount = 0

        while currentSector != endOfChain {
            // Cycle detection
            visitedCount += 1
            if visitedCount > maxSectors {
                throw CFBError.corruptedFile(
                    sectorIndex: currentSector,
                    reason: "mini-FAT chain cycle detected"
                )
            }

            // Validate sector index is within FAT bounds
            guard Int(currentSector) < fat.count else {
                throw CFBError.corruptedFile(
                    sectorIndex: currentSector,
                    reason: "mini-FAT sector index out of FAT bounds"
                )
            }

            // Calculate file offset for this sector: (sectorID + 1) * sectorSize
            let fileOffset = (Int(currentSector) + 1) * sectorSize

            // Read the sector data
            let sectorData = try reader.readBytes(at: fileOffset, length: sectorSize)

            // Parse each 4-byte chunk as a UInt32 (little-endian)
            for i in 0..<entriesPerSector {
                let entryOffset = i * 4
                let value = sectorData.withUnsafeBytes { buffer in
                    buffer.load(fromByteOffset: entryOffset, as: UInt32.self)
                }
                miniFAT.append(UInt32(littleEndian: value))
            }

            // Follow the FAT chain to the next mini-FAT sector
            currentSector = fat[Int(currentSector)]
        }

        return miniFAT
    }
}
