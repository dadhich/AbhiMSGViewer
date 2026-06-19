// MSGParser - DataReader protocol
// Abstraction over raw data access for both in-memory and memory-mapped backends

import Foundation

/// Errors thrown by DataReader implementations.
public enum DataReaderError: Error, Equatable {
    /// The requested byte range exceeds the available data.
    case outOfBounds(offset: Int, length: Int, available: Int)
}

/// Protocol for reading binary data from a source.
/// Enables both in-memory and memory-mapped backends.
public protocol DataReader {
    /// Total number of bytes available.
    var count: Int { get }

    /// Reads `length` bytes starting at `offset`.
    /// - Parameters:
    ///   - offset: The byte offset to start reading from.
    ///   - length: The number of bytes to read.
    /// - Returns: A `Data` value containing the requested bytes.
    /// - Throws: `DataReaderError.outOfBounds` if the range exceeds available data.
    func readBytes(at offset: Int, length: Int) throws -> Data

    /// Reads a fixed-width integer at the given offset (little-endian).
    /// - Parameter offset: The byte offset to read from.
    /// - Returns: The integer value decoded from little-endian bytes.
    /// - Throws: `DataReaderError.outOfBounds` if there aren't enough bytes.
    func readInteger<T: FixedWidthInteger>(at offset: Int) throws -> T
}

// MARK: - Default implementation for readInteger

extension DataReader {
    /// Default implementation that reads the appropriate number of bytes
    /// and interprets them as a little-endian integer.
    public func readInteger<T: FixedWidthInteger>(at offset: Int) throws -> T {
        let size = MemoryLayout<T>.size
        let bytes = try readBytes(at: offset, length: size)
        return bytes.withUnsafeBytes { buffer in
            T(littleEndian: buffer.loadUnaligned(as: T.self))
        }
    }
}
