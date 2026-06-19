# Requirements Document

## Introduction

A native macOS application for reading Microsoft Outlook .msg files completely offline. The application parses the OLE/CFB (Compound File Binary Format) directly using Swift, extracts email metadata, body content, and attachments, and presents them in a clean SwiftUI interface. The app requires zero network connectivity and prioritizes fast startup and file parsing performance.

## Glossary

- **MSG_File**: A Microsoft Outlook email message file using the .msg extension, stored in OLE/CFB binary format
- **OLE_CFB**: Object Linking and Embedding Compound File Binary Format — the binary container format used by .msg files to store structured email data as a hierarchy of storages and streams
- **Viewer**: The native macOS SwiftUI application that opens and displays .msg file contents
- **Parser**: The Swift module responsible for reading OLE/CFB binary data and extracting email properties from the .msg file
- **Email_Metadata**: The structured information about an email including subject, sender, recipients, and date
- **Attachment**: A file embedded within the .msg file, stored as a sub-storage in the OLE/CFB hierarchy
- **Property_Stream**: A binary stream within the OLE/CFB structure containing MAPI properties that encode email fields
- **FAT**: File Allocation Table — the sector chain table in OLE/CFB format used to locate data across sectors
- **Directory_Entry**: A record in the OLE/CFB directory stream describing a storage or stream node in the file hierarchy

## Requirements

### Requirement 1: Parse OLE/CFB File Structure

**User Story:** As a user, I want the app to read .msg files directly, so that I can view Outlook emails without needing Microsoft Outlook or any server.

#### Acceptance Criteria

1. WHEN a valid .msg file is opened, THE Parser SHALL read the OLE/CFB header and validate the file signature (0xD0CF11E0A1B11AE1)
2. WHEN the OLE/CFB header is valid, THE Parser SHALL parse the FAT and directory entries to locate all storages and streams
3. WHEN a .msg file uses FAT sector chains, THE Parser SHALL follow the chain including DIFAT sectors to read complete stream data across multiple sectors for files exceeding 109 FAT sectors
4. WHEN a .msg file uses mini-stream for small data (less than 4096 bytes), THE Parser SHALL read data from the mini-stream container
5. IF a file does not have a valid OLE/CFB signature, THEN THE Parser SHALL return an error containing the text "invalid file format" and the expected signature bytes
6. IF a file is corrupted or has invalid sector chains, THEN THE Parser SHALL return an error containing the text "corrupted file" and the specific sector index where the failure occurred, without crashing
7. THE Parser SHALL support .msg files up to 150 MB in size

### Requirement 2: Extract Email Metadata

**User Story:** As a user, I want to see the email subject, sender, recipients, and date, so that I can identify the email contents at a glance.

#### Acceptance Criteria

1. WHEN a .msg file is successfully parsed, THE Parser SHALL extract the email subject from the MAPI property PidTagSubject (0x0037) as a Unicode string (PT_UNICODE 0x001F) or ANSI string (PT_STRING8 0x001E)
2. WHEN a .msg file is successfully parsed, THE Parser SHALL extract the sender display name from PidTagSenderName (0x0C1A) and sender email address from PidTagSenderEmailAddress (0x0C1F)
3. WHEN a .msg file is successfully parsed, THE Parser SHALL extract To recipients from the recipient sub-storages with recipient type MAPI_TO (1), reading each recipient's display name (PidTagDisplayName, 0x3001) and email address (PidTagEmailAddress, 0x3003)
4. WHEN a .msg file is successfully parsed, THE Parser SHALL extract CC recipients from the recipient sub-storages with recipient type MAPI_CC (2), reading each recipient's display name (PidTagDisplayName, 0x3001) and email address (PidTagEmailAddress, 0x3003)
5. WHEN a .msg file is successfully parsed, THE Parser SHALL extract the sent date from PidTagClientSubmitTime (0x0039) and represent it as a UTC timestamp
6. IF a metadata property is missing from the .msg file, THEN THE Parser SHALL return a nil value for that field and continue extracting remaining properties without failing
7. WHEN a .msg file contains string properties encoded as ANSI (PT_STRING8 0x001E), THE Parser SHALL decode them using the code page specified in PidTagInternetCodepage (0x3FDE), defaulting to UTF-8 if no code page is specified
8. IF the recipient sub-storages contain more than 1000 recipients of a single type, THEN THE Parser SHALL extract all recipients without truncation

### Requirement 3: Extract Email Body

**User Story:** As a user, I want to read the email body content, so that I can understand the message without opening Outlook.

#### Acceptance Criteria

1. WHEN a .msg file contains a plain text body (PidTagBody, 0x1000), THE Parser SHALL extract and decode the plain text content using the encoding specified in PidTagInternetCodepage (0x3FDE), defaulting to UTF-8 if unspecified
2. WHEN a .msg file contains an HTML body (PidTagHtml, 0x1013), THE Parser SHALL extract and decode the HTML content using the encoding specified in the HTML charset meta tag or PidTagInternetCodepage, defaulting to UTF-8 if unspecified
3. WHEN a .msg file contains an RTF body (PidTagRtfCompressed, 0x1009), THE Parser SHALL extract and decompress the RTF content using the LZFu decompression algorithm
4. WHEN multiple body formats are present, THE Viewer SHALL display them in priority order: HTML first, then plain text, then RTF, with a toggle to switch between available formats
5. IF no body content is present in the .msg file, THEN THE Viewer SHALL display a message indicating the email has no body content
6. WHEN an RTF body is displayed, THE Viewer SHALL render it using NSAttributedString with RTF document type
7. IF extraction of a body format fails due to encoding or decompression errors, THEN THE Parser SHALL skip that format and attempt the next available format without crashing

### Requirement 4: Extract and List Attachments

**User Story:** As a user, I want to see and save email attachments, so that I can access files that were sent with the email.

#### Acceptance Criteria

1. WHEN a .msg file contains attachments, THE Parser SHALL extract each attachment's filename from PidTagAttachLongFilename (0x3707), falling back to PidTagAttachFilename (0x3704) if the long filename is absent
2. WHEN a .msg file contains attachments, THE Parser SHALL extract each attachment's binary data from PidTagAttachDataBinary (0x3701)
3. WHEN a .msg file contains attachments, THE Parser SHALL extract each attachment's size from PidTagAttachSize (0x0E20), or compute the size from the binary data length if the property is absent
4. WHEN a user requests to save an attachment, THE Viewer SHALL present a save dialog defaulting to the attachment's original filename and write the attachment binary data to the selected location
5. THE Viewer SHALL display a list of all attachments showing filename and human-readable size (bytes, KB, MB) for each attachment
6. IF an attachment's binary data cannot be extracted due to corruption, THEN THE Parser SHALL mark that attachment as unreadable and THE Viewer SHALL display it in the list with an error indicator
7. WHEN an attachment has a MIME type specified in PidTagAttachMimeTag (0x370E), THE Parser SHALL extract and associate it with the attachment for display purposes

### Requirement 5: Display Email in SwiftUI Interface

**User Story:** As a user, I want a clean native macOS interface to view the email, so that I have a familiar and responsive reading experience.

#### Acceptance Criteria

1. WHEN a parsed email is displayed, THE Viewer SHALL render the email subject as a header using a title-level font size that is visually larger than the body text
2. WHEN a parsed email is displayed, THE Viewer SHALL display the sender display name and email address below the subject, or display "Unknown Sender" if both the sender name and email address are absent
3. WHEN a parsed email is displayed, THE Viewer SHALL display To recipients and CC recipients in separate labeled rows (prefixed with "To:" and "CC:" respectively) below the sender, omitting the CC row if no CC recipients are present
4. WHEN a parsed email is displayed, THE Viewer SHALL display the sent date formatted using the user's system locale and timezone settings, or display "No Date" if the sent date is absent
5. WHEN a parsed email is displayed, THE Viewer SHALL display the email body in a vertically scrollable content area positioned below the metadata section
6. WHEN an HTML body is displayed, THE Viewer SHALL render the HTML using a WebView configured with no network access enabled and no JavaScript execution
7. WHEN a parsed email contains one or more attachments, THE Viewer SHALL display the attachment list in a dedicated section showing each attachment's filename and size, with a save button per attachment
8. IF the parsed email contains no attachments, THEN THE Viewer SHALL hide the attachment section entirely

### Requirement 6: File Opening and Drag-and-Drop Support

**User Story:** As a user, I want to open .msg files by double-clicking or dragging them onto the app, so that I can access emails quickly and naturally.

#### Acceptance Criteria

1. THE Viewer SHALL register as a handler for the .msg file extension in the macOS system via UTType declaration in Info.plist
2. WHEN a .msg file is double-clicked in Finder, THE Viewer SHALL open and display the file contents
3. WHEN a .msg file is dragged onto the application window, THE Viewer SHALL display a visual drop indicator and open the file upon release
4. WHEN a .msg file is dragged onto the application dock icon, THE Viewer SHALL open and display the file contents
5. THE Viewer SHALL provide a File > Open menu item that presents an open dialog filtered to .msg files
6. WHEN multiple .msg files are opened, THE Viewer SHALL display each file in a separate window, up to a maximum of 20 simultaneous windows; if the same file is already open, the existing window SHALL be brought to front instead of opening a duplicate
7. IF a non-.msg file or an invalid file is opened or dropped, THEN THE Viewer SHALL display an alert with the message "Unable to open file" and a description of the error
8. WHEN a file is dragged over the application window, THE Viewer SHALL display a highlighted drop zone border to indicate the area accepts drops

### Requirement 7: Offline-Only Operation

**User Story:** As a user, I want the app to work completely offline with no data leaving my machine, so that I can trust my email data remains private.

#### Acceptance Criteria

1. THE Viewer SHALL operate without any network connections — no HTTP requests, no analytics, no telemetry
2. THE Viewer SHALL not include any networking frameworks or capabilities in the application sandbox
3. WHEN rendering HTML email bodies, THE Viewer SHALL disable all network access in the WebView to prevent loading of remote images or resources
4. THE Viewer SHALL not require any user account, license server, or online activation
5. THE Viewer SHALL declare the com.apple.security.network.client entitlement as false (denied) in the app sandbox configuration

### Requirement 8: Performance

**User Story:** As a user, I want the app to open and display emails quickly, so that I can read messages without waiting.

#### Acceptance Criteria

1. WHEN a .msg file of 10 MB or less is opened, THE Parser SHALL complete parsing within 500 milliseconds on Apple Silicon hardware
2. THE Viewer SHALL display the application window within 1 second of launch
3. WHEN a .msg file is opened, THE Viewer SHALL show a loading indicator within 200 milliseconds of the file open action initiating, and SHALL continue displaying it until parsing completes
4. WHEN a .msg file larger than 10 MB and up to 150 MB is opened, THE Parser SHALL complete parsing within 3 seconds on Apple Silicon hardware
5. WHILE the Parser is processing a .msg file, THE Viewer SHALL remain interactive with no main-thread blocking exceeding 100 milliseconds, allowing the user to resize, move, or close the window
