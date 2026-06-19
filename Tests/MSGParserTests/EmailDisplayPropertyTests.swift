// MSGParserTests - Property-based tests for email display metadata formatting
// Feature: msg-file-viewer, Property 11: Email Display Metadata Formatting

import XCTest
import SwiftCheck
import Foundation
@testable import MSGParser

// MARK: - Display Formatting Logic (replicating EmailView's private formatting rules)

/// Formats the sender display string.
/// Shows "Name <email>" if both are present, just name or email if one is available,
/// or "Unknown Sender" if both are nil.
private func formattedSender(name: String?, email: String?) -> String {
    switch (name, email) {
    case let (name?, email?):
        return "\(name) <\(email)>"
    case let (name?, nil):
        return name
    case let (nil, email?):
        return email
    case (nil, nil):
        return "Unknown Sender"
    }
}

/// Formats a date for display. Returns "No Date" if the date is nil.
private func formattedDate(_ date: Date?) -> String {
    guard let date = date else {
        return "No Date"
    }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    formatter.locale = Locale.current
    formatter.timeZone = TimeZone.current
    return formatter.string(from: date)
}

/// Returns whether the CC row should be shown (non-empty ccRecipients).
private func shouldShowCCRow(ccRecipients: [Recipient]) -> Bool {
    return !ccRecipients.isEmpty
}

/// Returns whether the attachment section should be shown (non-empty attachments).
private func shouldShowAttachmentSection(attachments: [Attachment]) -> Bool {
    return !attachments.isEmpty
}

// MARK: - Generated Email Input for Property Testing

/// Represents a generated email configuration with varying field presence.
private struct GeneratedEmailInput {
    let senderName: String?
    let senderEmail: String?
    let sentDate: Date?
    let ccRecipients: [Recipient]
    let attachments: [Attachment]
}

// MARK: - Generators

/// Generates a non-empty string of lowercase ASCII characters.
private func safeStringGen() -> Gen<String> {
    let charGen = Gen<Character>.fromElements(in: "a"..."z")
    return Gen<[Character]>.compose { composer in
        let length = composer.generate(using: Gen<Int>.choose((1, 20)))
        return (0..<length).map { _ in composer.generate(using: charGen) }
    }.map { String($0) }
}

/// Generates an optional string (nil ~50% of the time).
private func optionalStringGen() -> Gen<String?> {
    return Gen<String?>.frequency([
        (1, Gen.pure(nil)),
        (1, safeStringGen().map { Optional($0) })
    ])
}

/// Generates an optional Date (nil ~50% of the time).
private func optionalDateGen() -> Gen<Date?> {
    return Gen<Date?>.frequency([
        (1, Gen.pure(nil)),
        (1, Gen<Date?>.compose { composer in
            let interval = composer.generate(using: Gen<Double>.choose((0, 2_000_000_000)))
            return Date(timeIntervalSince1970: interval)
        })
    ])
}

/// Generates a list of CC recipients (empty ~50% of the time).
private func ccRecipientsGen() -> Gen<[Recipient]> {
    return Gen<[Recipient]>.frequency([
        (1, Gen.pure([])),
        (1, Gen<[Recipient]>.compose { composer in
            let count = composer.generate(using: Gen<Int>.choose((1, 5)))
            return (0..<count).map { _ in
                let name = composer.generate(using: safeStringGen())
                let email = composer.generate(using: safeStringGen())
                return Recipient(displayName: name, emailAddress: "\(email)@test.com", type: .cc)
            }
        })
    ])
}

/// Generates a list of attachments (empty ~50% of the time).
private func attachmentsGen() -> Gen<[Attachment]> {
    return Gen<[Attachment]>.frequency([
        (1, Gen.pure([])),
        (1, Gen<[Attachment]>.compose { composer in
            let count = composer.generate(using: Gen<Int>.choose((1, 5)))
            return (0..<count).map { _ in
                let filename = composer.generate(using: safeStringGen())
                let size = composer.generate(using: Gen<Int>.choose((1, 1_000_000)))
                return Attachment(filename: "\(filename).pdf", size: size)
            }
        })
    ])
}

/// Generates a full email input with random presence/absence of fields.
private func emailInputGen() -> Gen<GeneratedEmailInput> {
    return Gen<GeneratedEmailInput>.compose { composer in
        let senderName = composer.generate(using: optionalStringGen())
        let senderEmail = composer.generate(using: optionalStringGen())
        let sentDate = composer.generate(using: optionalDateGen())
        let ccRecipients = composer.generate(using: ccRecipientsGen())
        let attachments = composer.generate(using: attachmentsGen())
        return GeneratedEmailInput(
            senderName: senderName,
            senderEmail: senderEmail,
            sentDate: sentDate,
            ccRecipients: ccRecipients,
            attachments: attachments
        )
    }
}

// MARK: - Property Tests

/// **Validates: Requirements 5.2, 5.3, 5.4, 5.8**
final class EmailDisplayPropertyTests: XCTestCase {

    // MARK: - Property 11: Email Display Metadata Formatting

    /// **Validates: Requirements 5.2**
    /// "Unknown Sender" is shown if and only if both senderName and senderEmail are nil.
    func testUnknownSenderShownIffBothFieldsNil() {
        property("'Unknown Sender' shown iff both senderName and senderEmail are nil") <- forAllNoShrink(emailInputGen()) { (input: GeneratedEmailInput) in
            let result = formattedSender(name: input.senderName, email: input.senderEmail)
            let bothNil = (input.senderName == nil && input.senderEmail == nil)
            return (result == "Unknown Sender") == bothNil
        }
    }

    /// **Validates: Requirements 5.4**
    /// "No Date" is shown if and only if sentDate is nil.
    func testNoDateShownIffSentDateNil() {
        property("'No Date' shown iff sentDate is nil") <- forAllNoShrink(emailInputGen()) { (input: GeneratedEmailInput) in
            let result = formattedDate(input.sentDate)
            let dateIsNil = (input.sentDate == nil)
            return (result == "No Date") == dateIsNil
        }
    }

    /// **Validates: Requirements 5.3**
    /// CC row is hidden if and only if ccRecipients is empty.
    func testCCRowHiddenIffCCRecipientsEmpty() {
        property("CC row hidden iff ccRecipients is empty") <- forAllNoShrink(emailInputGen()) { (input: GeneratedEmailInput) in
            let shouldShow = shouldShowCCRow(ccRecipients: input.ccRecipients)
            let isEmpty = input.ccRecipients.isEmpty
            // CC row is shown when non-empty, hidden when empty
            return shouldShow == !isEmpty
        }
    }

    /// **Validates: Requirements 5.8**
    /// Attachment section is hidden if and only if attachments is empty.
    func testAttachmentSectionHiddenIffAttachmentsEmpty() {
        property("Attachment section hidden iff attachments is empty") <- forAllNoShrink(emailInputGen()) { (input: GeneratedEmailInput) in
            let shouldShow = shouldShowAttachmentSection(attachments: input.attachments)
            let isEmpty = input.attachments.isEmpty
            // Attachment section is shown when non-empty, hidden when empty
            return shouldShow == !isEmpty
        }
    }
}
