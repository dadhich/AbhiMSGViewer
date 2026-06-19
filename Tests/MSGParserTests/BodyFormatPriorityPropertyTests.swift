// MSGParserTests - Property-based tests for body format priority selection
// Feature: msg-file-viewer, Property 8: Body Format Priority Selection

import XCTest
import SwiftCheck
import Foundation
@testable import MSGParser

// MARK: - Generators

/// Generates a random Bool with equal probability.
private func boolGen() -> Gen<Bool> {
    return Gen<Bool>.frequency([
        (1, Gen.pure(true)),
        (1, Gen.pure(false))
    ])
}

/// Generates a random non-empty plain text string (1-100 characters).
private func plainTextGen() -> Gen<String> {
    return Gen<String>.compose { composer in
        let length = composer.generate(using: Gen<Int>.choose((1, 100)))
        let chars = (0..<length).map { _ -> Character in
            let code = composer.generate(using: Gen<UInt8>.choose((32, 126)))
            return Character(UnicodeScalar(code))
        }
        return String(chars)
    }
}

/// Generates a random non-empty HTML string.
private func htmlGen() -> Gen<String> {
    return Gen<String>.compose { composer in
        let length = composer.generate(using: Gen<Int>.choose((1, 100)))
        let chars = (0..<length).map { _ -> Character in
            let code = composer.generate(using: Gen<UInt8>.choose((32, 126)))
            return Character(UnicodeScalar(code))
        }
        let body = String(chars)
        return "<html><body>\(body)</body></html>"
    }
}

/// Generates random non-empty RTF data (1-100 bytes).
private func rtfDataGen() -> Gen<Data> {
    return Gen<Data>.compose { composer in
        let length = composer.generate(using: Gen<Int>.choose((1, 100)))
        let bytes = (0..<length).map { _ in composer.generate(using: Gen<UInt8>.choose((0, 255))) }
        return Data(bytes)
    }
}

/// Represents a generated body format combination for property testing.
private struct BodyFormatInput {
    let hasHtml: Bool
    let hasPlainText: Bool
    let hasRtf: Bool
    let htmlContent: String?
    let plainTextContent: String?
    let rtfContent: Data?

    /// The expected preferred format based on priority rules.
    var expectedFormat: BodyFormat {
        if hasHtml { return .html }
        if hasPlainText { return .plainText }
        if hasRtf { return .rtf }
        return .none
    }

    /// Constructs an EmailBody from the generated input.
    var emailBody: EmailBody {
        return EmailBody(plainText: plainTextContent, html: htmlContent, rtf: rtfContent)
    }
}

/// Generates all combinations of present/absent body formats with content.
private func bodyFormatInputGen() -> Gen<BodyFormatInput> {
    return Gen<BodyFormatInput>.compose { composer in
        let hasHtml = composer.generate(using: boolGen())
        let hasPlainText = composer.generate(using: boolGen())
        let hasRtf = composer.generate(using: boolGen())

        let htmlContent: String? = hasHtml ? composer.generate(using: htmlGen()) : nil
        let plainTextContent: String? = hasPlainText ? composer.generate(using: plainTextGen()) : nil
        let rtfContent: Data? = hasRtf ? composer.generate(using: rtfDataGen()) : nil

        return BodyFormatInput(
            hasHtml: hasHtml,
            hasPlainText: hasPlainText,
            hasRtf: hasRtf,
            htmlContent: htmlContent,
            plainTextContent: plainTextContent,
            rtfContent: rtfContent
        )
    }
}

// MARK: - Property Tests

/// **Validates: Requirements 3.4, 3.7**
final class BodyFormatPriorityPropertyTests: XCTestCase {

    // MARK: - Property 8: Body Format Priority Selection

    /// **Validates: Requirements 3.4, 3.7**
    /// For any combination of present/absent body formats (HTML, plain text, RTF),
    /// the preferred format SHALL be the highest-priority format that is present
    /// (HTML > plain text > RTF). If no formats are present, preferredFormat is .none.
    func testPreferredFormatSelectsHighestPriorityPresent() {
        property("preferredFormat selects highest-priority present format (HTML > plainText > RTF)") <- forAllNoShrink(bodyFormatInputGen()) { (input: BodyFormatInput) in
            let body = input.emailBody
            return body.preferredFormat == input.expectedFormat
        }
    }

    /// **Validates: Requirements 3.4, 3.7**
    /// When HTML is present, preferredFormat SHALL always be .html regardless
    /// of whether plain text or RTF are also present.
    func testHtmlAlwaysTakesPriorityWhenPresent() {
        property("HTML always takes priority when present") <- forAllNoShrink(htmlGen(), boolGen(), boolGen()) { (htmlContent: String, hasPlainText: Bool, hasRtf: Bool) in
            let plainText: String? = hasPlainText ? "some text" : nil
            let rtf: Data? = hasRtf ? Data([0x01, 0x02, 0x03]) : nil

            let body = EmailBody(plainText: plainText, html: htmlContent, rtf: rtf)
            return body.preferredFormat == .html
        }
    }

    /// **Validates: Requirements 3.4, 3.7**
    /// When HTML is absent but plain text is present, preferredFormat SHALL be .plainText
    /// regardless of whether RTF is also present.
    func testPlainTextTakesPriorityOverRtfWhenHtmlAbsent() {
        property("Plain text takes priority over RTF when HTML is absent") <- forAllNoShrink(plainTextGen(), boolGen()) { (textContent: String, hasRtf: Bool) in
            let rtf: Data? = hasRtf ? Data([0x01, 0x02, 0x03]) : nil

            let body = EmailBody(plainText: textContent, html: nil, rtf: rtf)
            return body.preferredFormat == .plainText
        }
    }

    /// **Validates: Requirements 3.4, 3.7**
    /// When only RTF is present (no HTML, no plain text), preferredFormat SHALL be .rtf.
    func testRtfSelectedWhenOnlyFormatPresent() {
        property("RTF selected when it is the only format present") <- forAllNoShrink(rtfDataGen()) { (rtfContent: Data) in
            let body = EmailBody(plainText: nil, html: nil, rtf: rtfContent)
            return body.preferredFormat == .rtf
        }
    }

    /// **Validates: Requirements 3.4, 3.7**
    /// When no body formats are present, preferredFormat SHALL be .none.
    func testNoneWhenNoFormatsPresent() {
        let body = EmailBody(plainText: nil, html: nil, rtf: nil)
        XCTAssertEqual(body.preferredFormat, .none)
    }

    /// **Validates: Requirements 3.4, 3.7**
    /// For all 8 possible combinations of present/absent (2^3 for 3 formats),
    /// the preferredFormat SHALL match the expected priority selection.
    func testAllEightCombinationsExhaustive() {
        // Exhaustively test all 8 combinations
        let combinations: [(Bool, Bool, Bool, BodyFormat)] = [
            (false, false, false, .none),
            (false, false, true,  .rtf),
            (false, true,  false, .plainText),
            (false, true,  true,  .plainText),
            (true,  false, false, .html),
            (true,  false, true,  .html),
            (true,  true,  false, .html),
            (true,  true,  true,  .html),
        ]

        for (hasHtml, hasPlainText, hasRtf, expected) in combinations {
            let html: String? = hasHtml ? "<html>x</html>" : nil
            let plainText: String? = hasPlainText ? "x" : nil
            let rtf: Data? = hasRtf ? Data([0x01]) : nil

            let body = EmailBody(plainText: plainText, html: html, rtf: rtf)
            XCTAssertEqual(body.preferredFormat, expected,
                "Failed for html=\(hasHtml), plainText=\(hasPlainText), rtf=\(hasRtf): expected \(expected), got \(body.preferredFormat)")
        }
    }
}
