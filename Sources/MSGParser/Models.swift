// MSGParser - Domain models
// Placeholder for Email, Recipient, Attachment, and related types

import Foundation

/// The fully parsed email representation.
public struct Email {
    public let subject: String?
    public let senderName: String?
    public let senderEmail: String?
    public let toRecipients: [Recipient]
    public let ccRecipients: [Recipient]
    public let sentDate: Date?
    public let body: EmailBody
    public let attachments: [Attachment]

    public init(
        subject: String? = nil,
        senderName: String? = nil,
        senderEmail: String? = nil,
        toRecipients: [Recipient] = [],
        ccRecipients: [Recipient] = [],
        sentDate: Date? = nil,
        body: EmailBody = EmailBody(),
        attachments: [Attachment] = []
    ) {
        self.subject = subject
        self.senderName = senderName
        self.senderEmail = senderEmail
        self.toRecipients = toRecipients
        self.ccRecipients = ccRecipients
        self.sentDate = sentDate
        self.body = body
        self.attachments = attachments
    }
}

/// Represents an email recipient.
public struct Recipient {
    public let displayName: String?
    public let emailAddress: String?
    public let type: RecipientType

    public init(displayName: String? = nil, emailAddress: String? = nil, type: RecipientType) {
        self.displayName = displayName
        self.emailAddress = emailAddress
        self.type = type
    }
}

/// Recipient type corresponding to MAPI recipient types.
public enum RecipientType: Int32 {
    case to = 1     // MAPI_TO
    case cc = 2     // MAPI_CC
    case bcc = 3    // MAPI_BCC
}

/// Available body content for an email.
public struct EmailBody {
    public let plainText: String?
    public let html: String?
    public let rtf: Data?

    public init(plainText: String? = nil, html: String? = nil, rtf: Data? = nil) {
        self.plainText = plainText
        self.html = html
        self.rtf = rtf
    }

    /// Returns the preferred body format based on availability.
    public var preferredFormat: BodyFormat {
        if html != nil { return .html }
        if plainText != nil { return .plainText }
        if rtf != nil { return .rtf }
        return .none
    }
}

/// Body format enumeration.
public enum BodyFormat: String, CaseIterable {
    case html = "HTML"
    case plainText = "Plain Text"
    case rtf = "RTF"
    case none = "No Content"
}

/// An email attachment.
public struct Attachment: Identifiable {
    public let id: UUID
    public let filename: String
    public let size: Int
    public let mimeType: String?
    public let data: Data?
    public let isCorrupted: Bool

    public init(
        id: UUID = UUID(),
        filename: String,
        size: Int,
        mimeType: String? = nil,
        data: Data? = nil,
        isCorrupted: Bool = false
    ) {
        self.id = id
        self.filename = filename
        self.size = size
        self.mimeType = mimeType
        self.data = data
        self.isCorrupted = isCorrupted
    }

    /// Human-readable size string.
    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
