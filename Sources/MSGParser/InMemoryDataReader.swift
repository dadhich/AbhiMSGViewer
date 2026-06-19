// MSGParser - InMemoryDataReader
// DataReader implementation backed by an in-memory Data buffer

import Foundation

/// A DataReader implementation that reads from an in-memory `Data` buffer.
/// Suitable for files ≤ 1 MB or for testing purposes.
public final class InMemoryDataReader: DataReader {
    private let data: Data

    /// Creates a reader backed by the given data.
    /// - Parameter data: The raw bytes to read from.
    public init(data: Data) {
        self.data = data
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
