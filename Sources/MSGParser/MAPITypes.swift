// MSGParser - MAPI (Messaging Application Programming Interface) data structures
// Defines property tags, property values, and property containers

import Foundation

/// A MAPI property tag consisting of a property ID and a property type.
public struct MAPIPropertyTag: Hashable {
    /// The MAPI property identifier (upper 16 bits of the tag).
    public let id: UInt16
    /// The MAPI property type (lower 16 bits of the tag).
    public let type: UInt16

    public init(id: UInt16, type: UInt16) {
        self.id = id
        self.type = type
    }

    /// The combined 32-bit tag value (type in lower 16 bits, id in upper 16 bits).
    public var rawTag: UInt32 {
        (UInt32(id) << 16) | UInt32(type)
    }
}

// MARK: - Well-Known Property Tags

extension MAPIPropertyTag {
    // Subject
    /// PidTagSubject as Unicode (PT_UNICODE)
    public static let subjectUnicode = MAPIPropertyTag(id: 0x0037, type: 0x001F)
    /// PidTagSubject as ANSI (PT_STRING8)
    public static let subjectAnsi = MAPIPropertyTag(id: 0x0037, type: 0x001E)

    // Sender
    /// PidTagSenderName (PT_UNICODE)
    public static let senderName = MAPIPropertyTag(id: 0x0C1A, type: 0x001F)
    /// PidTagSenderEmailAddress (PT_UNICODE)
    public static let senderEmail = MAPIPropertyTag(id: 0x0C1F, type: 0x001F)

    // Date
    /// PidTagClientSubmitTime (PT_SYSTIME)
    public static let clientSubmitTime = MAPIPropertyTag(id: 0x0039, type: 0x0040)

    // Body
    /// PidTagBody - plain text body (PT_UNICODE)
    public static let bodyPlainText = MAPIPropertyTag(id: 0x1000, type: 0x001F)
    /// PidTagHtml - HTML body (PT_BINARY)
    public static let bodyHtml = MAPIPropertyTag(id: 0x1013, type: 0x0102)
    /// PidTagRtfCompressed - compressed RTF body (PT_BINARY)
    public static let bodyRtfCompressed = MAPIPropertyTag(id: 0x1009, type: 0x0102)

    // Encoding
    /// PidTagInternetCodepage (PT_LONG)
    public static let internetCodePage = MAPIPropertyTag(id: 0x3FDE, type: 0x0003)

    // Attachment properties
    /// PidTagAttachLongFilename (PT_UNICODE)
    public static let attachLongFilename = MAPIPropertyTag(id: 0x3707, type: 0x001F)
    /// PidTagAttachFilename (PT_UNICODE)
    public static let attachFilename = MAPIPropertyTag(id: 0x3704, type: 0x001F)
    /// PidTagAttachDataBinary (PT_BINARY)
    public static let attachDataBinary = MAPIPropertyTag(id: 0x3701, type: 0x0102)
    /// PidTagAttachSize (PT_LONG)
    public static let attachSize = MAPIPropertyTag(id: 0x0E20, type: 0x0003)
    /// PidTagAttachMimeTag (PT_UNICODE)
    public static let attachMimeTag = MAPIPropertyTag(id: 0x370E, type: 0x001F)

    // Recipient properties
    /// PidTagDisplayName (PT_UNICODE)
    public static let displayName = MAPIPropertyTag(id: 0x3001, type: 0x001F)
    /// PidTagEmailAddress (PT_UNICODE)
    public static let emailAddress = MAPIPropertyTag(id: 0x3003, type: 0x001F)
    /// PidTagRecipientType (PT_LONG)
    public static let recipientType = MAPIPropertyTag(id: 0x0C15, type: 0x0003)
}

// MARK: - MAPI Property Types (PT_*)

extension MAPIPropertyTag {
    /// PT_UNICODE - Unicode string (UTF-16LE)
    public static let typeUnicode: UInt16 = 0x001F
    /// PT_STRING8 - ANSI string (code-page encoded)
    public static let typeString8: UInt16 = 0x001E
    /// PT_BINARY - Binary data
    public static let typeBinary: UInt16 = 0x0102
    /// PT_LONG - 32-bit integer
    public static let typeLong: UInt16 = 0x0003
    /// PT_I8 - 64-bit integer
    public static let typeI8: UInt16 = 0x0014
    /// PT_SYSTIME - FILETIME (64-bit, 100ns intervals since 1601-01-01)
    public static let typeSysTime: UInt16 = 0x0040
    /// PT_BOOLEAN - Boolean (16-bit)
    public static let typeBoolean: UInt16 = 0x000B
}

/// Typed MAPI property values.
public enum MAPIPropertyValue: Equatable {
    /// A Unicode or ANSI string value.
    case string(String)
    /// Raw binary data.
    case binary(Data)
    /// A 32-bit integer value.
    case int32(Int32)
    /// A 64-bit integer value.
    case int64(Int64)
    /// A date/time value (converted from FILETIME).
    case time(Date)
    /// A boolean value.
    case boolean(Bool)
}

/// A parsed MAPI property with its tag and value.
public struct MAPIProperty: Equatable {
    /// The property tag identifying this property.
    public let tag: MAPIPropertyTag
    /// The typed value of the property.
    public let value: MAPIPropertyValue

    public init(tag: MAPIPropertyTag, value: MAPIPropertyValue) {
        self.tag = tag
        self.value = value
    }
}
