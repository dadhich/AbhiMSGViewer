# Implementation Plan: MSG File Viewer

## Overview

A native macOS application (Swift/SwiftUI) that reads Microsoft Outlook .msg files entirely offline. Implementation follows the layered architecture: Parsing Layer → Domain Layer → Presentation Layer → System Layer, with property-based tests validating correctness at each boundary.

## Tasks

- [x] 1. Set up project structure and core interfaces
  - [x] 1.1 Create Swift Package and Xcode project structure
    - Create the Xcode project with SwiftUI App lifecycle
    - Add Swift Package for parsing logic (MSGParser library target and test target)
    - Add SwiftCheck dependency (`https://github.com/typelift/SwiftCheck`) to the test target
    - Configure deployment target for macOS 13+
    - Create directory structure: `Sources/MSGParser/`, `Sources/MSGFileViewer/`, `Tests/MSGParserTests/`
    - _Requirements: 7.1, 7.2, 7.5_

  - [x] 1.2 Define core protocols and data types
    - Create `DataReader` protocol with `count`, `readBytes(at:length:)`, and `readInteger<T>(at:)` methods
    - Create `DataReaderError` enum with `outOfBounds` case
    - Create all CFB structures: `CFBHeader`, `DirectoryEntry`, `ObjectType`
    - Create all MAPI structures: `MAPIPropertyTag` (with all static constants), `MAPIProperty`, `MAPIPropertyValue`
    - Create domain models: `Email`, `Recipient`, `RecipientType`, `EmailBody`, `BodyFormat`, `Attachment`
    - Create error types: `CFBError`, `LZFuError`, `MSGParserError`
    - _Requirements: 1.1, 1.5, 1.6, 2.1, 2.3, 2.4, 4.1, 4.2, 4.3_

  - [x] 1.3 Configure app sandbox entitlements and Info.plist
    - Create entitlements file with `com.apple.security.app-sandbox` = true
    - Set `com.apple.security.network.client` = false (deny network)
    - Set `com.apple.security.files.user-selected.read-write` = true
    - Add UTType declaration in Info.plist for `.msg` files (UTI: `com.microsoft.outlook-message`)
    - Declare exported/imported type identifiers with `public.filename-extension` = "msg"
    - _Requirements: 6.1, 7.1, 7.2, 7.5_

- [x] 2. Implement DataReader protocol and backends
  - [x] 2.1 Implement InMemoryDataReader
    - Create `InMemoryDataReader` conforming to `DataReader`
    - Store raw `Data` and implement bounds-checked reads
    - Implement little-endian integer reading via `readInteger<T>(at:)`
    - Throw `DataReaderError.outOfBounds` for invalid ranges
    - _Requirements: 1.1, 1.2_

  - [x] 2.2 Implement MappedDataReader (memory-mapped I/O)
    - Create `MappedDataReader` conforming to `DataReader`
    - Use `mmap` (or `Data(contentsOf:options: .mappedIfSafe)`) for files > 1 MB
    - Implement same bounds-checked read semantics as InMemoryDataReader
    - Add factory method that selects InMemory vs Mapped based on file size threshold (1 MB)
    - _Requirements: 1.7, 8.1, 8.4_

- [x] 3. Implement CFBReader (OLE/CFB parser)
  - [x] 3.1 Implement CFB header parsing and signature validation
    - Implement `CFBReader.readHeader(from:)` to parse the 512-byte header
    - Validate magic signature bytes (0xD0CF11E0A1B11AE1)
    - Extract sector size power, mini sector size power, FAT sector count, directory sector, DIFAT info
    - Parse the first 109 DIFAT entries from the header
    - Return `CFBError.invalidSignature` for invalid magic bytes
    - Return `CFBError.unsupportedVersion` for versions other than 3 or 4
    - _Requirements: 1.1, 1.5_

  - [x] 3.2 Write property test for CFB signature validation
    - **Property 1: CFB Signature Validation**
    - Generate random byte buffers of at least 8 bytes; verify parser accepts only valid signature
    - Generate buffers with valid signature; verify parser does not return signature error
    - Minimum 100 iterations
    - **Validates: Requirements 1.1, 1.5**

  - [x] 3.3 Implement FAT building including DIFAT chain
    - Implement `CFBReader.buildFAT(header:reader:)` to read all FAT sectors
    - Follow DIFAT sector chain for files with more than 109 FAT sectors
    - Include cycle detection: break after max possible sectors (file size / sector size)
    - _Requirements: 1.2, 1.3_

  - [x] 3.4 Implement mini-FAT building
    - Implement `CFBReader.buildMiniFAT(header:fat:reader:)` to read mini-FAT sectors
    - Follow the mini-FAT sector chain from the header's firstMiniFATSector
    - _Requirements: 1.4_

  - [x] 3.5 Implement directory entry parsing
    - Implement `CFBReader.readDirectoryEntries(header:fat:reader:)` to read all 128-byte directory entries
    - Parse entry name (UTF-16LE), object type, start sector, stream size, child/sibling IDs
    - Follow the directory sector chain via FAT
    - _Requirements: 1.2_

  - [x] 3.6 Implement stream reading (FAT and mini-FAT chains)
    - Implement `CFBReader.readStream(entry:fat:miniFAT:miniStream:header:reader:)` 
    - Use mini-FAT for streams < miniStreamCutoffSize (4096)
    - Use regular FAT for larger streams
    - Follow chain until end-of-chain marker (0xFFFFFFFE)
    - Return `CFBError.corruptedFile` with sector index for invalid chains
    - _Requirements: 1.2, 1.3, 1.4, 1.6_

  - [x] 3.7 Write property test for FAT chain stream reconstruction
    - **Property 2: FAT Chain Stream Reconstruction**
    - Generate valid CFB structures with streams spread across N sectors
    - Verify byte-for-byte reconstruction for both regular FAT and mini-FAT paths
    - Minimum 100 iterations
    - **Validates: Requirements 1.2, 1.3, 1.4**

  - [x] 3.8 Write property test for corrupted sector chain error reporting
    - **Property 3: Corrupted Sector Chain Error Reporting**
    - Generate valid CFB files, corrupt a single sector in FAT chain to invalid index
    - Verify error contains "corrupted file" and the corrupted sector index
    - Verify no crash or infinite loop
    - Minimum 100 iterations
    - **Validates: Requirements 1.6**

- [x] 4. Checkpoint - Ensure parsing layer tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Implement MAPIPropertyExtractor
  - [x] 5.1 Implement property stream parsing
    - Implement `MAPIPropertyExtractor.extractProperties(from:codePage:)` 
    - Parse property stream header and iterate property entries
    - Handle PT_UNICODE (0x001F), PT_STRING8 (0x001E), PT_BINARY (0x0102), PT_LONG (0x0003), PT_I8 (0x0014), PT_SYSTIME (0x0040), PT_BOOLEAN (0x000B) types
    - Convert FILETIME to Date for PT_SYSTIME properties
    - Decode ANSI strings using code page from PidTagInternetCodepage, defaulting to UTF-8
    - Skip unrecognized property types without failing
    - _Requirements: 2.1, 2.2, 2.5, 2.6, 2.7_

  - [x] 5.2 Write property test for MAPI property extraction round-trip
    - **Property 4: MAPI Property Extraction Round-Trip**
    - Generate sets of MAPI properties (subject, sender name, sender email, sent date) encoded into valid property streams
    - Verify extracted values are identical to originals
    - Verify missing properties produce nil without affecting extraction of others
    - Minimum 100 iterations
    - **Validates: Requirements 2.1, 2.2, 2.5, 2.6, 2.7**

  - [x] 5.3 Implement recipient extraction
    - Implement `MAPIPropertyExtractor.extractRecipients(from:rootStreams:)`
    - Iterate recipient sub-storages (`__recip_version2.0_#XXXXXXXX`)
    - Extract display name, email address, and recipient type from each sub-storage
    - Classify recipients as TO (1), CC (2), or BCC (3)
    - Handle 1000+ recipients without truncation
    - _Requirements: 2.3, 2.4, 2.8_

  - [x] 5.4 Write property test for recipient extraction completeness
    - **Property 5: Recipient Extraction Completeness**
    - Generate N recipients (TO and CC types) encoded into recipient sub-storages
    - Verify exactly N recipients returned with correct types and preserved names/emails
    - Minimum 100 iterations
    - **Validates: Requirements 2.3, 2.4, 2.8**

  - [x] 5.5 Implement attachment extraction
    - Implement `MAPIPropertyExtractor.extractAttachments(from:rootStreams:)`
    - Iterate attachment sub-storages (`__attach_version2.0_#XXXXXXXX`)
    - Extract filename (prefer PidTagAttachLongFilename, fallback to PidTagAttachFilename)
    - Extract binary data from PidTagAttachDataBinary
    - Extract size from PidTagAttachSize or compute from data length
    - Extract MIME type from PidTagAttachMimeTag if present
    - Mark attachment as corrupted if binary data extraction fails
    - _Requirements: 4.1, 4.2, 4.3, 4.6, 4.7_

  - [x] 5.6 Write property test for attachment extraction round-trip
    - **Property 9: Attachment Extraction Round-Trip**
    - Generate attachments with filename, binary data, optional MIME type
    - Verify filename preference (long > short), data identity, correct size, matching MIME type
    - Verify corrupted binary data produces isCorrupted = true with nil data
    - Minimum 100 iterations
    - **Validates: Requirements 4.1, 4.2, 4.3, 4.6, 4.7**

- [x] 6. Implement LZFuDecompressor
  - [x] 6.1 Implement LZFu decompression algorithm
    - Implement `LZFuDecompressor.decompress(_:)` 
    - Parse LZFu header: compressed size, uncompressed size, signature, CRC
    - Handle compressed signature (0x75465A4C "LZFu") and uncompressed signature (0x414C454D "MELA")
    - Implement sliding window decompression with 4096-byte dictionary pre-initialized with RTF control words
    - Validate CRC32 and return `LZFuError.crcMismatch` on failure
    - Return `LZFuError.corruptedData` for malformed input
    - Return raw data (skipping header) for uncompressed signature
    - _Requirements: 3.3_

  - [x] 6.2 Write property test for LZFu decompression round-trip
    - **Property 7: LZFu Decompression Round-Trip**
    - Generate valid RTF content, compress with LZFu, then decompress
    - Verify output is byte-for-byte identical to original
    - Minimum 100 iterations
    - **Validates: Requirements 3.3**

- [x] 7. Implement body content extraction and format priority
  - [x] 7.1 Implement body extraction logic
    - Extract plain text body from PidTagBody with encoding from PidTagInternetCodepage
    - Extract HTML body from PidTagHtml with encoding from charset meta tag or PidTagInternetCodepage
    - Extract RTF body from PidTagRtfCompressed, decompress via LZFuDecompressor
    - Construct `EmailBody` with all available formats
    - If one format fails, continue extracting others (no crash on partial failure)
    - _Requirements: 3.1, 3.2, 3.3, 3.7_

  - [x] 7.2 Write property test for body content extraction round-trip
    - **Property 6: Body Content Extraction Round-Trip**
    - Generate text strings encoded as plain text or HTML body properties with given encoding
    - Verify extracting and decoding produces identical strings
    - Minimum 100 iterations
    - **Validates: Requirements 3.1, 3.2**

  - [x] 7.3 Write property test for body format priority selection
    - **Property 8: Body Format Priority Selection**
    - Generate all combinations of present/absent body formats
    - Verify preferred format is highest-priority present format (HTML > plain text > RTF)
    - Minimum 100 iterations
    - **Validates: Requirements 3.4, 3.7**

- [x] 8. Implement MSGParser actor (orchestration)
  - [x] 8.1 Implement MSGParser.parse(url:) orchestration
    - Create `MSGParser` as an actor for background execution
    - Select DataReader backend based on file size (InMemory ≤ 1 MB, Mapped > 1 MB)
    - Call CFBReader to parse header, build FAT, mini-FAT, read directory entries
    - Extract root storage mini-stream for mini-FAT stream reads
    - Call MAPIPropertyExtractor for properties, recipients, attachments
    - Call body extraction logic (including LZFu decompression for RTF)
    - Assemble and return `Email` domain model
    - Map internal errors to `MSGParserError` cases for the UI layer
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.7, 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 4.1, 4.2, 8.1, 8.4_

- [x] 9. Checkpoint - Ensure domain layer tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 10. Implement SwiftUI presentation layer
  - [x] 10.1 Implement EmailViewModel
    - Create `@MainActor` class conforming to `ObservableObject`
    - Add `@Published` properties: `email: Email?`, `isLoading: Bool`, `error: MSGParserError?`, `selectedBodyFormat: BodyFormat`
    - Implement `openFile(url:)` — set loading state, call MSGParser on background, update published properties
    - Implement `saveAttachment(_:)` — present NSSavePanel, write attachment data
    - Show loading indicator within 200ms of file open action
    - _Requirements: 8.3, 8.5_

  - [x] 10.2 Implement OfflineWebView (NSViewRepresentable)
    - Create `OfflineWebView` struct conforming to `NSViewRepresentable`
    - Configure WKWebView with `allowsContentJavaScript = false`
    - Create `BlockingSchemeHandler` (WKURLSchemeHandler) that fails all loads
    - Create `Coordinator` as `WKNavigationDelegate` that cancels all navigation
    - Load HTML via `loadHTMLString(_:baseURL: nil)`
    - _Requirements: 5.6, 7.3_

  - [x] 10.3 Implement EmailView and metadata section
    - Create `EmailView` as main view showing email content
    - Display subject as `.title` font
    - Display sender name and email, or "Unknown Sender" if both nil
    - Display To recipients row with "To:" label
    - Display CC recipients row with "CC:" label (hidden if empty)
    - Display sent date in user's locale/timezone, or "No Date" if nil
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

  - [x] 10.4 Implement body content view with format toggle
    - Create body content section below metadata in a scrollable area
    - Show OfflineWebView for HTML body
    - Show Text view for plain text body
    - Use NSAttributedString with `.rtf` document type for RTF body
    - Add format toggle (Picker) when multiple formats available
    - Display "No body content" message when no formats present
    - _Requirements: 3.4, 3.5, 3.6, 5.5_

  - [x] 10.5 Implement attachment list view
    - Create attachment section with list of attachments (filename + formatted size)
    - Add save button per attachment triggering `saveAttachment` on view model
    - Show error indicator for corrupted attachments
    - Hide entire section when attachments array is empty
    - _Requirements: 4.4, 4.5, 4.6, 5.7, 5.8_

  - [x] 10.6 Write property test for email display metadata formatting
    - **Property 11: Email Display Metadata Formatting**
    - Generate Email values with varying field presence
    - Verify "Unknown Sender" shown iff both senderName and senderEmail are nil
    - Verify "No Date" shown iff sentDate is nil
    - Verify CC row hidden iff ccRecipients is empty
    - Verify attachment section hidden iff attachments is empty
    - Minimum 100 iterations
    - **Validates: Requirements 5.2, 5.3, 5.4, 5.8**

  - [x] 10.7 Write property test for file size formatting
    - **Property 10: File Size Formatting**
    - Generate non-negative integer byte counts
    - Verify formatter produces non-empty string with numeric value and appropriate units
    - Minimum 100 iterations
    - **Validates: Requirements 4.5**

- [x] 11. Implement file handling and system integration
  - [x] 11.1 Implement drag-and-drop support
    - Create `FileDropModifier` ViewModifier with `onDrop(of: [.fileURL])`
    - Validate dropped file has `.msg` extension or UTType
    - Show visual drop indicator (highlighted border) when file is targeted
    - Invoke file open on successful drop
    - _Requirements: 6.3, 6.7, 6.8_

  - [x] 11.2 Implement multi-window document management
    - Create custom `NSDocumentController` subclass or window management logic
    - Track open windows by file path for deduplication
    - Limit to maximum 20 simultaneous windows
    - Bring existing window to front if same file opened again
    - Show alert when window limit reached
    - Implement File > Open menu item with .msg file filter
    - Handle file open from Finder double-click and dock icon drop
    - _Requirements: 6.2, 6.4, 6.5, 6.6_

  - [x] 11.3 Write property test for window deduplication and limit
    - **Property 12: Window Deduplication and Limit**
    - Generate sequences of file open requests with duplicate paths
    - Verify window count never exceeds 20
    - Verify duplicate path reuses existing window
    - Minimum 100 iterations
    - **Validates: Requirements 6.6**

  - [x] 11.4 Write property test for invalid file rejection
    - **Property 13: Invalid File Rejection**
    - Generate files with non-.msg extension or invalid OLE/CFB signature
    - Verify error alert contains "Unable to open file"
    - Minimum 100 iterations
    - **Validates: Requirements 6.7**

- [x] 12. Checkpoint - Ensure presentation and system layer tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 13. Integration, performance, and final wiring
  - [x] 13.1 Wire App entry point and window lifecycle
    - Create `@main` App struct with `WindowGroup` or `DocumentGroup`
    - Wire `EmailViewModel` to `EmailView`
    - Connect file open events (Finder, dock, menu) to EmailViewModel.openFile
    - Connect drag-and-drop to EmailViewModel.openFile
    - Ensure each document opens in its own window
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 8.2_

  - [x] 13.2 Write integration tests with reference .msg files
    - Parse known small, medium, and large .msg files end-to-end
    - Verify full Email model fields against expected values
    - Verify memory-mapped path used for files > 1 MB
    - _Requirements: 1.7, 8.1_

  - [x] 13.3 Write performance tests
    - Test 10 MB file parses in < 500ms on Apple Silicon
    - Test 150 MB file parses in < 3 seconds on Apple Silicon
    - Verify main thread not blocked > 100ms during parsing
    - _Requirements: 8.1, 8.4, 8.5_

- [x] 14. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation at layer boundaries
- Property tests validate universal correctness properties from the design document (13 properties total)
- Unit tests validate specific examples and edge cases
- SwiftCheck is used for property-based testing with custom generators
- The architecture follows Parsing → Domain → Presentation → System layer order
- All parsing runs on a background actor; UI updates occur on @MainActor

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "1.3"] },
    { "id": 2, "tasks": ["2.1", "2.2"] },
    { "id": 3, "tasks": ["3.1"] },
    { "id": 4, "tasks": ["3.2", "3.3", "3.4", "3.5"] },
    { "id": 5, "tasks": ["3.6"] },
    { "id": 6, "tasks": ["3.7", "3.8"] },
    { "id": 7, "tasks": ["5.1"] },
    { "id": 8, "tasks": ["5.2", "5.3", "5.5", "6.1"] },
    { "id": 9, "tasks": ["5.4", "5.6", "6.2"] },
    { "id": 10, "tasks": ["7.1"] },
    { "id": 11, "tasks": ["7.2", "7.3"] },
    { "id": 12, "tasks": ["8.1"] },
    { "id": 13, "tasks": ["10.1", "10.2"] },
    { "id": 14, "tasks": ["10.3", "10.4", "10.5"] },
    { "id": 15, "tasks": ["10.6", "10.7", "11.1", "11.2"] },
    { "id": 16, "tasks": ["11.3", "11.4"] },
    { "id": 17, "tasks": ["13.1"] },
    { "id": 18, "tasks": ["13.2", "13.3"] }
  ]
}
```
