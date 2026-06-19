// MSGParserTests - Property-based tests for LZFu decompression round-trip
// Feature: msg-file-viewer, Property 7: LZFu Decompression Round-Trip

import XCTest
import SwiftCheck
import Foundation
@testable import MSGParser

// MARK: - CRC32 Helper (mirrors the implementation in LZFuDecompressor)

private let crc32Table: [UInt32] = {
    var table = [UInt32](repeating: 0, count: 256)
    for i in 0..<256 {
        var crc = UInt32(i)
        for _ in 0..<8 {
            if crc & 1 != 0 {
                crc = (crc >> 1) ^ 0xEDB88320
            } else {
                crc >>= 1
            }
        }
        table[i] = crc
    }
    return table
}()

private func computeCRC32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFFFFFF
    for byte in data {
        let index = Int((crc ^ UInt32(byte)) & 0xFF)
        crc = (crc >> 8) ^ crc32Table[index]
    }
    return crc ^ 0xFFFFFFFF
}

// MARK: - MELA (Uncompressed) Packet Builder

/// Builds a valid MELA (uncompressed) LZFu packet from raw data bytes.
/// Format: [compressedSize:UInt32][uncompressedSize:UInt32][signature:UInt32][crc:UInt32][raw data]
/// Where compressedSize = payloadLength + 12 (covers uncompressedSize + signature + crc).
private func buildMELAPacket(from bytes: [UInt8]) -> Data {
    let payload = Data(bytes)
    let uncompressedSize = UInt32(bytes.count)
    let signature: UInt32 = 0x414C454D  // "MELA" little-endian
    let crc = computeCRC32(payload)
    // compressedSize includes: uncompressedSize(4) + signature(4) + crc(4) + payload
    let compressedSize = UInt32(12 + payload.count)

    var packet = Data()
    packet.append(contentsOf: withUnsafeBytes(of: compressedSize.littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: uncompressedSize.littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: signature.littleEndian) { Array($0) })
    packet.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
    packet.append(payload)
    return packet
}

// MARK: - Generators

/// Generates random RTF-like content of varying lengths (8-500 bytes).
/// Produces content starting with `{\rtf1` to mimic real RTF data.
private func rtfContentGen() -> Gen<[UInt8]> {
    return Gen<[UInt8]>.compose { composer in
        let length = composer.generate(using: Gen<Int>.choose((8, 500)))
        let prefix = Array("{\\rtf1 ".utf8)
        var bytes = prefix
        for _ in prefix.count..<length {
            // Generate printable ASCII characters (32-126)
            let byte = composer.generate(using: Gen<UInt8>.choose((32, 126)))
            bytes.append(byte)
        }
        bytes.append(contentsOf: Array("}".utf8))
        return bytes
    }
}

/// Generates arbitrary binary content of varying lengths (1-1000 bytes).
private func arbitraryBytesGen() -> Gen<[UInt8]> {
    return Gen<[UInt8]>.compose { composer in
        let length = composer.generate(using: Gen<Int>.choose((1, 1000)))
        return (0..<length).map { _ in composer.generate(using: Gen<UInt8>.choose((0, 255))) }
    }
}

/// Generates non-empty byte content (1-500 bytes) with no zero bytes,
/// ensuring a non-zero CRC for CRC mismatch testing.
private func nonEmptyBytesGen() -> Gen<[UInt8]> {
    return Gen<[UInt8]>.compose { composer in
        let length = composer.generate(using: Gen<Int>.choose((1, 500)))
        return (0..<length).map { _ in composer.generate(using: Gen<UInt8>.choose((1, 255))) }
    }
}

// MARK: - Property Tests

/// **Validates: Requirements 3.3**
final class LZFuPropertyTests: XCTestCase {

    // MARK: - Property 7: LZFu Decompression Round-Trip (MELA path)

    /// **Validates: Requirements 3.3**
    /// For any valid RTF content, packing it as a MELA (uncompressed) packet
    /// and then decompressing with LZFuDecompressor.decompress SHALL produce
    /// output byte-for-byte identical to the original RTF data.
    func testMELARoundTripPreservesOriginalData() {
        property("MELA round-trip: decompress(buildMELAPacket(data)) == data") <- forAll(rtfContentGen()) { (bytes: [UInt8]) in
            let packet = buildMELAPacket(from: bytes)
            do {
                let decompressed = try LZFuDecompressor.decompress(packet)
                return decompressed == Data(bytes)
            } catch {
                return false
            }
        }
    }

    /// **Validates: Requirements 3.3**
    /// For any arbitrary binary content (not just RTF), the MELA uncompressed path
    /// SHALL produce output identical to the original data. This tests the round-trip
    /// property with a wider variety of inputs including binary data with null bytes.
    func testMELARoundTripWithArbitraryData() {
        property("MELA round-trip with arbitrary binary data preserves content") <- forAll(arbitraryBytesGen()) { (bytes: [UInt8]) in
            let packet = buildMELAPacket(from: bytes)
            do {
                let decompressed = try LZFuDecompressor.decompress(packet)
                return decompressed == Data(bytes)
            } catch {
                return false
            }
        }
    }

    // MARK: - Invalid Signature Detection

    /// **Validates: Requirements 3.3**
    /// For any data with an invalid signature (not LZFu and not MELA),
    /// LZFuDecompressor.decompress SHALL throw LZFuError.invalidSignature.
    func testInvalidSignatureThrowsError() {
        property("Invalid signature throws LZFuError.invalidSignature") <- forAll(arbitraryBytesGen()) { (bytes: [UInt8]) in
            // Build a packet with an invalid signature
            let payload = Data(bytes)
            let invalidSignature: UInt32 = 0xDEADBEEF
            let uncompressedSize = UInt32(bytes.count)
            let crc = computeCRC32(payload)
            let compressedSize = UInt32(12 + payload.count)

            var packet = Data()
            packet.append(contentsOf: withUnsafeBytes(of: compressedSize.littleEndian) { Array($0) })
            packet.append(contentsOf: withUnsafeBytes(of: uncompressedSize.littleEndian) { Array($0) })
            packet.append(contentsOf: withUnsafeBytes(of: invalidSignature.littleEndian) { Array($0) })
            packet.append(contentsOf: withUnsafeBytes(of: crc.littleEndian) { Array($0) })
            packet.append(payload)

            do {
                _ = try LZFuDecompressor.decompress(packet)
                return false  // Should have thrown
            } catch let error as LZFuError {
                switch error {
                case .invalidSignature:
                    return true
                default:
                    return false
                }
            } catch {
                return false
            }
        }
    }

    // MARK: - CRC Mismatch Detection

    /// **Validates: Requirements 3.3**
    /// For any valid MELA packet where the CRC field is corrupted (flipped),
    /// LZFuDecompressor.decompress SHALL throw LZFuError.crcMismatch.
    func testCRCMismatchThrowsError() {
        property("Corrupted CRC throws LZFuError.crcMismatch") <- forAll(nonEmptyBytesGen()) { (bytes: [UInt8]) in
            let payload = Data(bytes)
            let uncompressedSize = UInt32(bytes.count)
            let signature: UInt32 = 0x414C454D  // MELA
            let correctCRC = computeCRC32(payload)
            // Flip all bits to ensure the CRC is different and non-zero
            let corruptedCRC = correctCRC ^ 0xFFFFFFFF
            let compressedSize = UInt32(12 + payload.count)

            var packet = Data()
            packet.append(contentsOf: withUnsafeBytes(of: compressedSize.littleEndian) { Array($0) })
            packet.append(contentsOf: withUnsafeBytes(of: uncompressedSize.littleEndian) { Array($0) })
            packet.append(contentsOf: withUnsafeBytes(of: signature.littleEndian) { Array($0) })
            packet.append(contentsOf: withUnsafeBytes(of: corruptedCRC.littleEndian) { Array($0) })
            packet.append(payload)

            do {
                _ = try LZFuDecompressor.decompress(packet)
                return false  // Should have thrown
            } catch let error as LZFuError {
                switch error {
                case .crcMismatch(_, _):
                    return true
                default:
                    return false
                }
            } catch {
                return false
            }
        }
    }
}
