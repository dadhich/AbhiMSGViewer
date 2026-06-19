// MSGParser - MappedDataReader
// DataReader implementation backed by memory-mapped file I/O

import Foundation

/// A DataReader implementation that reads from a memory-mapped file.
/// Uses `Data(contentsOf:options: .mappedIfSafe)` to let the kernel page in data on demand.
/// Suitable for files > 1 MB where loading the entire file into heap would be expensive.
public final class MappedDataReader: DataReader {
    private let data: Data

    /// Creates a memory-mapped reader for the file at the given URL.
    /// - Parameter url: The file URL to memory-map.
    /// - Throws: An error if the file cannot be read or mapped.
    public init(url: URL) throws {
        self.data = try Data(contentsOf: url, options: .mappedIfSafe)
    }

    /// Total number of bytes available.
    public var count: Int {
        data.count
    }

    /// Reads `length` bytes starting at `offset`.
    /// - Parameters:
    ///   - offset: The byte offset to start reading from.
    ///   - length: The number of bytes to read.
    /// - Returns: A `Data` value containing the requested bytes.
    /// - Throws: `DataReaderError.outOfBounds` if the range exceeds available data.
    public func readBytes(at offset: Int, length: Int) throws -> Data {
        guard offset >= 0, length >= 0, offset + length <= data.count else {
            throw DataReaderError.outOfBounds(
                offset: offset,
                length: length,
                available: data.count
            )
        }
        return data[offset ..< offset + length]
    }
}

// MARK: - DataReader Factory

/// Factory for creating the appropriate DataReader backend based on file size.
public struct DataReaderFactory {
    /// The file size threshold (in bytes) above which memory-mapped I/O is used.
    /// Files ≤ this size use InMemoryDataReader; files > this size use MappedDataReader.
    public static let memorySizeThreshold: Int = 1_048_576 // 1 MB

    /// Creates a DataReader for the file at the given URL.
    ///
    /// Selects the backend based on file size:
    /// - Files ≤ 1 MB: Uses `InMemoryDataReader` (loaded entirely into memory)
    /// - Files > 1 MB: Uses `MappedDataReader` (memory-mapped I/O)
    ///
    /// - Parameter url: The file URL to read.
    /// - Returns: A `DataReader` appropriate for the file's size.
    /// - Throws: An error if the file cannot be accessed or read.
    public static func createReader(for url: URL) throws -> DataReader {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes[.size] as? Int) ?? 0

        if fileSize > memorySizeThreshold {
            return try MappedDataReader(url: url)
        } else {
            let data = try Data(contentsOf: url)
            return InMemoryDataReader(data: data)
        }
    }
}
