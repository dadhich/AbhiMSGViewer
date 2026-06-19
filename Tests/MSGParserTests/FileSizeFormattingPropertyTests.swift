// MSGParserTests - Property-based tests for file size formatting
// Feature: msg-file-viewer, Property 10: File Size Formatting

import XCTest
import SwiftCheck
import Foundation
@testable import MSGParser

/// **Validates: Requirements 4.5**
final class FileSizeFormattingPropertyTests: XCTestCase {

    // MARK: - Property 10: File Size Formatting

    /// Verifies that formattedSize produces a non-empty string containing a numeric value
    /// and an appropriate unit for any non-negative byte count.
    /// **Validates: Requirements 4.5**
    func testFormattedSizeIsNonEmptyWithNumericAndUnit() {
        // Generate non-negative integers in range 0 to ~10 GB
        let byteSizeGen = Gen<Int>.choose((0, 10_737_418_240))

        property("Formatted size is non-empty, contains a digit, and has an appropriate unit") <- forAll(byteSizeGen) { (byteCount: Int) in
            let attachment = Attachment(
                filename: "test.bin",
                size: byteCount
            )

            let formatted = attachment.formattedSize

            // 1. Must be non-empty
            guard !formatted.isEmpty else { return false }

            // 2. Must contain at least one digit (numeric value)
            let containsDigit = formatted.contains(where: { $0.isNumber })
            guard containsDigit else { return false }

            // 3. Must contain an appropriate unit string
            let validUnits = ["bytes", "KB", "MB", "GB"]
            let containsUnit = validUnits.contains(where: { formatted.contains($0) })
            guard containsUnit else { return false }

            return true
        }
    }
}
