// MSGParserTests - Property-based tests for body content extraction round-trip
// Feature: msg-file-viewer, Property 6: Body Content Extraction Round-Trip

import XCTest
import SwiftCheck
import Foundation
@testable import MSGParser

// MARK: - Generators

/// Generates a non-empty ASCII string suitable for body content.
/// We restrict to printable ASCII to guarantee clean UTF-8 encoding round-trips
/// without introducing charset detection edge cases unrelated to this property.
private func bodyStringGen() -> Gen<String> {
    let charGen = Gen<Character>.fromElements(in: "a"..."z")
    return Gen<[Character]>.compose { composer in
        let length = composer.generate(using: Gen<Int>.choose((1, 100)))
        return (0..<length).map { _ in composer.generate(using: charGen) }
    }.map { String($0) }
}

// MARK: - Tests

/// **Validates: Requirements 3.1, 3.2**
final class BodyExtractionPropertyTests: XCTestCase {

    // MARK: - Property 6: Body Content Extraction Round-Trip (Plain Text)

    /// **Validates: Requirements 3.1**
    /// For any text string encoded as a plain text body property (PidTagBody, PT_UNICODE),
    /// extracting and decoding the body produces a string identical to the original.
    func testPlainTextBodyExtractionRoundTrip() {
        property("Plain text body extraction round-trips correctly") <- forAll(bodyStringGen()) { (text: String) in
            // Create a MAPIProperty with tag .bodyPlainText and value .string(text)
            let property = MAPIProperty(
                tag: MAPIPropertyTag.bodyPlainText,
                value: .string(text)
            )

            // Call extractBody with the property and empty streams
            let body = BodyExtractor.extractBody(
                from: [property],
                streams: [:],
                codePage: nil
            )

            // Verify the plain text matches the original
            return body.plainText == text
        }
    }

    // MARK: - Property 6: Body Content Extraction Round-Trip (HTML)

    /// **Validates: Requirements 3.2**
    /// For any text string encoded as UTF-8 and placed in the HTML body stream,
    /// extracting and decoding the body produces a string identical to the original.
    func testHTMLBodyExtractionRoundTrip() {
        property("HTML body extraction round-trips correctly") <- forAll(bodyStringGen()) { (text: String) in
            // Encode the text as UTF-8 and place in the HTML stream
            guard let htmlData = text.data(using: .utf8) else {
                return false
            }

            let streams: [String: Data] = [
                "__substg1.0_10130102": htmlData
            ]

            // Call extractBody with empty properties and the HTML stream
            let body = BodyExtractor.extractBody(
                from: [],
                streams: streams,
                codePage: nil
            )

            // Verify the HTML content matches the original text
            return body.html == text
        }
    }
}
