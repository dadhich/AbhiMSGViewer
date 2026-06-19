// MSGParserTests - Property-based tests for CFB signature validation
// Feature: msg-file-viewer, Property 1: CFB Signature Validation

import XCTest
import SwiftCheck
import Foundation
@testable import MSGParser

/// The valid CFB/OLE signature bytes as they appear on disk.
/// When loaded as a little-endian UInt64, this equals 0xE11AB1A1E011CFD0.
private let validSignatureBytes: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]

/// Generates a random buffer of at least 512 bytes where the first 8 bytes
/// are guaranteed NOT to be the valid CFB signature.
private func randomNonSignatureBufferGen() -> Gen<[UInt8]> {
    return Gen<[UInt8]>.compose { composer in
        // Generate a buffer of exactly 512 bytes (minimum for header parsing)
        var buffer = (0..<512).map { _ in composer.generate(using: Gen<UInt8>.choose((0, 255))) }

        // Ensure the first 8 bytes do NOT form the valid signature
        let first8 = Array(buffer[0..<8])
        if first8 == validSignatureBytes {
            // Flip one byte to invalidate the signature
            let flipIndex = composer.generate(using: Gen<Int>.choose((0, 7)))
            buffer[flipIndex] = buffer[flipIndex] ^ 0xFF
        }

        return buffer
    }
}

/// Generates a random buffer of at least 512 bytes with the valid signature
/// in the first 8 bytes and majorVersion 3 or 4 at offset 26.
private func validSignatureBufferGen() -> Gen<[UInt8]> {
    return Gen<[UInt8]>.compose { composer in
        // Generate a buffer of exactly 512 bytes with random content
        var buffer = (0..<512).map { _ in composer.generate(using: Gen<UInt8>.choose((0, 255))) }

        // Set the first 8 bytes to the valid signature (little-endian)
        for i in 0..<8 {
            buffer[i] = validSignatureBytes[i]
        }

        // Set majorVersion at offset 26 to either 3 or 4 (UInt16 little-endian)
        let majorVersion: UInt16 = composer.generate(using: Gen<UInt16>.fromElements(of: [3, 4]))
        buffer[26] = UInt8(majorVersion & 0xFF)
        buffer[27] = UInt8((majorVersion >> 8) & 0xFF)

        return buffer
    }
}

/// **Validates: Requirements 1.1, 1.5**
final class CFBSignaturePropertyTests: XCTestCase {

    // MARK: - Property 1: Random bytes without valid signature produce invalidSignature error

    /// **Validates: Requirements 1.1, 1.5**
    /// Generate random byte buffers of at least 512 bytes where the first 8 bytes
    /// do NOT equal the valid signature. Verify that CFBReader.readHeader(from:)
    /// throws CFBError.invalidSignature and the error description contains "invalid file format".
    func testRandomBytesWithoutValidSignatureProduceInvalidSignatureError() {
        property("Random buffers without valid CFB signature produce invalidSignature error") <- forAll(randomNonSignatureBufferGen()) { (bufferData: [UInt8]) in
            let data = Data(bufferData)
            let reader = InMemoryDataReader(data: data)

            do {
                _ = try CFBReader.readHeader(from: reader)
                // If no error is thrown, this is a failure (should have thrown)
                return false
            } catch let error as CFBError {
                switch error {
                case .invalidSignature(_, _):
                    // Verify the error description contains "invalid file format"
                    return error.description.contains("invalid file format")
                default:
                    // Should specifically be invalidSignature, not another CFBError
                    return false
                }
            } catch {
                // Non-CFBError exceptions are unexpected
                return false
            }
        }
    }

    // MARK: - Property 2: Buffers with valid signature do NOT produce invalidSignature error

    /// **Validates: Requirements 1.1, 1.5**
    /// Generate byte buffers of at least 512 bytes with the first 8 bytes set to the valid signature
    /// and majorVersion set to 3 or 4 at offset 26. Verify that CFBReader.readHeader(from:)
    /// does NOT throw CFBError.invalidSignature.
    func testBuffersWithValidSignatureDoNotProduceInvalidSignatureError() {
        property("Buffers with valid CFB signature do not produce invalidSignature error") <- forAll(validSignatureBufferGen()) { (bufferData: [UInt8]) in
            let data = Data(bufferData)
            let reader = InMemoryDataReader(data: data)

            do {
                _ = try CFBReader.readHeader(from: reader)
                // Parsing succeeded - no invalidSignature error, property holds
                return true
            } catch let error as CFBError {
                switch error {
                case .invalidSignature(_, _):
                    // This should NOT happen with a valid signature
                    return false
                default:
                    // Other CFBErrors (unsupportedVersion, etc.) are acceptable
                    return true
                }
            } catch {
                // Other errors (DataReaderError, etc.) are acceptable
                return true
            }
        }
    }
}
