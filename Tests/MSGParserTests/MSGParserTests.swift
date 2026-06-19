// MSGParserTests - Property-based and unit tests for the MSGParser library

import XCTest
import SwiftCheck
@testable import MSGParser

final class MSGParserTests: XCTestCase {

    func testMSGParserModuleImports() {
        // Verify the MSGParser module is importable and basic types are accessible
        let email = Email()
        XCTAssertNil(email.subject)
        XCTAssertNil(email.senderName)
        XCTAssertNil(email.senderEmail)
        XCTAssertTrue(email.toRecipients.isEmpty)
        XCTAssertTrue(email.ccRecipients.isEmpty)
        XCTAssertNil(email.sentDate)
        XCTAssertEqual(email.body.preferredFormat, .none)
        XCTAssertTrue(email.attachments.isEmpty)
    }

    func testBodyFormatPriority() {
        // HTML takes priority over plain text and RTF
        let bodyWithAll = EmailBody(plainText: "text", html: "<p>html</p>", rtf: Data([0x7B]))
        XCTAssertEqual(bodyWithAll.preferredFormat, .html)

        // Plain text is second priority
        let bodyTextOnly = EmailBody(plainText: "text", html: nil, rtf: Data([0x7B]))
        XCTAssertEqual(bodyTextOnly.preferredFormat, .plainText)

        // RTF is third priority
        let bodyRtfOnly = EmailBody(plainText: nil, html: nil, rtf: Data([0x7B]))
        XCTAssertEqual(bodyRtfOnly.preferredFormat, .rtf)

        // No content
        let bodyEmpty = EmailBody()
        XCTAssertEqual(bodyEmpty.preferredFormat, .none)
    }

    func testAttachmentFormattedSize() {
        let attachment = Attachment(filename: "test.pdf", size: 1024)
        XCTAssertFalse(attachment.formattedSize.isEmpty)
    }

    func testRecipientTypes() {
        let toRecipient = Recipient(displayName: "Alice", emailAddress: "alice@example.com", type: .to)
        XCTAssertEqual(toRecipient.type.rawValue, 1)

        let ccRecipient = Recipient(displayName: "Bob", emailAddress: "bob@example.com", type: .cc)
        XCTAssertEqual(ccRecipient.type.rawValue, 2)

        let bccRecipient = Recipient(displayName: "Charlie", emailAddress: "charlie@example.com", type: .bcc)
        XCTAssertEqual(bccRecipient.type.rawValue, 3)
    }
}
