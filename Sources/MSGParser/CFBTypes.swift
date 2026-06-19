// MSGParser - CFB (Compound File Binary Format) data structures
// Defines the header, directory entry, and object type for OLE/CFB parsing

import Foundation

/// OLE/CFB file header (first 512 bytes of the file).
public struct CFBHeader {
    /// Must be 0xE11AB1A1E011CFD0 (on-disk bytes: D0 CF 11 E0 A1 B1 1A E1)
    public let signature: UInt64
    /// Minor version of the file format
    public let minorVersion: UInt16
    /// Major version: 3 (sector size 512) or 4 (sector size 4096)
    public let majorVersion: UInt16
    /// Byte order identifier (0xFFFE = little-endian)
    public let byteOrder: UInt16
    /// Power of 2 for sector size (9 = 512 bytes, 12 = 4096 bytes)
    public let sectorSizePower: UInt16
    /// Power of 2 for mini sector size (6 = 64 bytes)
    public let miniSectorSizePower: UInt16
    /// Total number of FAT sectors
    public let totalFATSectors: UInt32
    /// Sector ID of first directory sector
    public let firstDirectorySector: UInt32
    /// Minimum stream size that uses regular FAT (4096 bytes)
    public let miniStreamCutoffSize: UInt32
    /// Sector ID of first mini-FAT sector
    public let firstMiniFATSector: UInt32
    /// Total number of mini-FAT sectors
    public let totalMiniFATSectors: UInt32
    /// Sector ID of first DIFAT sector (0xFFFFFFFE if none)
    public let firstDIFATSector: UInt32
    /// Total number of DIFAT sectors
    public let totalDIFATSectors: UInt32
    /// First 109 DIFAT entries stored in the header
    public let difatArray: [UInt32]

    /// The expected OLE/CFB magic signature (little-endian representation of on-disk bytes D0 CF 11 E0 A1 B1 1A E1).
    public static let expectedSignature: UInt64 = 0xE11AB1A1_E011CFD0

    /// Computed sector size in bytes.
    public var sectorSize: Int {
        1 << Int(sectorSizePower)
    }

    /// Computed mini sector size in bytes.
    public var miniSectorSize: Int {
        1 << Int(miniSectorSizePower)
    }

    public init(
        signature: UInt64,
        minorVersion: UInt16,
        majorVersion: UInt16,
        byteOrder: UInt16,
        sectorSizePower: UInt16,
        miniSectorSizePower: UInt16,
        totalFATSectors: UInt32,
        firstDirectorySector: UInt32,
        miniStreamCutoffSize: UInt32,
        firstMiniFATSector: UInt32,
        totalMiniFATSectors: UInt32,
        firstDIFATSector: UInt32,
        totalDIFATSectors: UInt32,
        difatArray: [UInt32]
    ) {
        self.signature = signature
        self.minorVersion = minorVersion
        self.majorVersion = majorVersion
        self.byteOrder = byteOrder
        self.sectorSizePower = sectorSizePower
        self.miniSectorSizePower = miniSectorSizePower
        self.totalFATSectors = totalFATSectors
        self.firstDirectorySector = firstDirectorySector
        self.miniStreamCutoffSize = miniStreamCutoffSize
        self.firstMiniFATSector = firstMiniFATSector
        self.totalMiniFATSectors = totalMiniFATSectors
        self.firstDIFATSector = firstDIFATSector
        self.totalDIFATSectors = totalDIFATSectors
        self.difatArray = difatArray
    }
}

/// Object type for a directory entry in the CFB structure.
public enum ObjectType: UInt8 {
    case unknown = 0
    case storage = 1
    case stream = 2
    case rootStorage = 5
}

/// A directory entry in the CFB structure (128 bytes each).
public struct DirectoryEntry {
    /// Name of the entry (decoded from UTF-16LE)
    public let name: String
    /// Type of directory object
    public let objectType: ObjectType
    /// Starting sector of the entry's stream data
    public let startSector: UInt32
    /// Size of the stream in bytes
    public let streamSize: UInt64
    /// Directory ID of the child node
    public let childID: UInt32
    /// Directory ID of the left sibling
    public let leftSiblingID: UInt32
    /// Directory ID of the right sibling
    public let rightSiblingID: UInt32

    public init(
        name: String,
        objectType: ObjectType,
        startSector: UInt32,
        streamSize: UInt64,
        childID: UInt32,
        leftSiblingID: UInt32,
        rightSiblingID: UInt32
    ) {
        self.name = name
        self.objectType = objectType
        self.startSector = startSector
        self.streamSize = streamSize
        self.childID = childID
        self.leftSiblingID = leftSiblingID
        self.rightSiblingID = rightSiblingID
    }
}
