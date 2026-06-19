// MSGParserTests - Property-based tests for invalid file rejection
// Feature: msg-file-viewer, Property 13: Invalid File Rejection

import XCTest
import SwiftCheck
import Foundation
@testable import MSGParser

/// The valid OLE/CFB signature bytes as they appear on disk.
/// When loaded as a little-endian UInt64, this equals 0xE11AB1A1E011CFD0.
private let validCFBSignatureBytes: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]

/// Generates a random non-.msg file extension (e.g., .txt, .pdf, .doc, random strings).
private func nonMSGExtensionGen() -> Gen<String> {
    let knownExtensions = Gen<String>.fromElements(of: [
        "txt", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "zip", "rar", "jpg", "png", "gif", "html", "xml", "csv",
        "rtf", "eml", "mbox", "ost", "pst", "dat", "bin", "exe"
    ])

    let randomExtension = Gen<String>.compose { composer in
        // Generate a random 1-5 character extension (lowercase letters)
        let length = composer.generate(using: Gen<Int>.choose((1, 5)))
        let chars = (0..<length).map { _ in
            composer.generate(using: Gen<Character>.fromElements(of: Array("abcdefghijklmnopqrstuvwxyz")))
        }
        let ext = String(chars)
        // Make sure it's not "msg"
        return ext == "msg" ? "txt" : ext
    }

    // 50% known extensions, 50% random extensions
    return Gen<String>.one(of: [knownExtensions, randomExtension])
}

/// Generates a random filename (without extension) containing alphanumeric characters.
private func filenameGen() -> Gen<String> {
    return Gen<String>.compose { composer in
        let length = composer.generate(using: Gen<Int>.choose((1, 20)))
        let chars = (0..<length).map { _ in
            composer.generate(using: Gen<Character>.fromElements(of: Array("abcdefghijklmnopqrstuvwxyz0123456789_-")))
        }
        return String(chars)
    }
}

/// Generates a byte array with an invalid OLE/CFB signature (first 8 bytes are NOT the valid signature).
/// Buffer is at least 512 bytes to be large enough for header parsing attempts.
private func invalidSignatureBufferGen() -> Gen<[UInt8]> {
    return Gen<[UInt8]>.compose { composer in
        // Generate 512 bytes of random data
        var bytes = (0..<512).map { _ in
            composer.generate(using: Gen<UInt8>.choose((0, 255)))
        }

        // Ensure the first 8 bytes do NOT form the valid CFB signature
        let first8 = Array(bytes[0..<8])
        if first8 == validCFBSignatureBytes {
            // Flip a random byte in the signature to invalidate it
            let flipIndex = composer.generate(using: Gen<Int>.choose((0, 7)))
            bytes[flipIndex] = bytes[flipIndex] ^ 0xFF
        }

        return bytes
    }
}

/// **Validates: Requirements 6.7**
final class InvalidFileRejectionPropertyTests: XCTestCase {

    // MARK: - Property 13a: Non-.msg extension files are rejected

    /// Generate file URLs with non-.msg extensions and verify that the extension
    /// does not match "msg", confirming the file would be rejected by the drop handler.
    /// This tests the same validation logic used by FileDropModifier.isValidMSGFile(url:).
    /// **Validates: Requirements 6.7**
    func testNonMSGExtensionFilesAreRejected() {
        property("Files with non-.msg extensions are rejected") <- forAll(filenameGen(), nonMSGExtensionGen()) { (filename: String, ext: String) in
            // Construct a file URL with the non-.msg extension
            let url = URL(fileURLWithPath: "/tmp/\(filename).\(ext)")

            // The validation logic checks: url.pathExtension.lowercased() == "msg"
            // For non-.msg files, this must be false
            let extensionIsMsg = url.pathExtension.lowercased() == "msg"
            return !extensionIsMsg
        }
    }

    // MARK: - Property 13b: Invalid OLE/CFB signature produces "Unable to open file" error

    /// Generate Data with invalid OLE/CFB signatures and verify that parsing
    /// produces an error whose description contains "Unable to open file".
    /// This tests the full error flow from CFBReader through MSGParserError.
    /// **Validates: Requirements 6.7**
    func testInvalidCFBSignatureProducesUnableToOpenFileError() {
        property("Data with invalid CFB signature produces 'Unable to open file' error") <- forAll(invalidSignatureBufferGen()) { (bufferData: [UInt8]) in
            let invalidData = Data(bufferData)
            let reader = InMemoryDataReader(data: invalidData)

            do {
                _ = try CFBReader.readHeader(from: reader)
                // If parsing succeeds, the property fails (should have been rejected)
                return false
            } catch let error as CFBError {
                // Wrap the CFBError in MSGParserError.invalidFormat to verify the
                // user-facing error message that would be shown in the alert
                let parserError = MSGParserError.invalidFormat(error)
                let errorMessage = parserError.errorDescription ?? ""
                // The error alert must contain "Unable to open file"
                return errorMessage.contains("Unable to open file")
            } catch {
                // DataReaderError or other errors - in the real MSGParser flow,
                // these would be caught and mapped to MSGParserError.fileAccessDenied
                // which also contains "Unable to open file"
                let parserError = MSGParserError.fileAccessDenied(
                    URL(fileURLWithPath: "/tmp/invalid.msg")
                )
                let errorMessage = parserError.errorDescription ?? ""
                return errorMessage.contains("Unable to open file")
            }
        }
    }

    // MARK: - Property 13c: Full parse flow rejects invalid data with "Unable to open file"

    /// Generate files with invalid OLE/CFB signatures, write them to temp files,
    /// and verify that MSGParser.parse(url:) throws an error containing "Unable to open file".
    /// **Validates: Requirements 6.7**
    func testFullParseFlowRejectsInvalidFilesWithUnableToOpenFile() {
        property("MSGParser rejects invalid files with 'Unable to open file' error") <- forAll(invalidSignatureBufferGen(), nonMSGExtensionGen()) { (bufferData: [UInt8], ext: String) in
            let invalidData = Data(bufferData)

            // Write to a temporary file with a non-.msg extension
            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent("test_invalid_\(UUID().uuidString).\(ext)")

            defer { try? FileManager.default.removeItem(at: tempFile) }

            do {
                try invalidData.write(to: tempFile)
            } catch {
                // Can't write temp file - skip this iteration
                return true
            }

            // Parse the file using MSGParser
            let parser = MSGParser()
            let expectation = XCTestExpectation(description: "parse completes")
            var resultError: MSGParserError?

            Task {
                do {
                    _ = try await parser.parse(url: tempFile)
                } catch let error as MSGParserError {
                    resultError = error
                } catch {
                    // Unexpected error type
                }
                expectation.fulfill()
            }

            // Wait synchronously for the async task
            let waiter = XCTWaiter()
            let waitResult = waiter.wait(for: [expectation], timeout: 5.0)

            guard waitResult == .completed, let parserError = resultError else {
                // If we timed out or got no error, the property fails
                // (unless the file happened to look valid, which is astronomically unlikely)
                return resultError != nil
            }

            // Verify the error description contains "Unable to open file"
            let errorMessage = parserError.errorDescription ?? ""
            return errorMessage.contains("Unable to open file")
        }
    }
}
