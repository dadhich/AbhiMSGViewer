// MSGParser - Core parsing library for Microsoft Outlook .msg files
// Implements OLE/CFB binary format parsing and MAPI property extraction

import Foundation

/// Parses a .msg file and returns a structured Email model.
/// Runs on a background executor to avoid blocking the main thread.
public actor MSGParser {
    public init() {}

    // MARK: - Constants

    /// Sentinel value indicating no sibling/child in the directory tree.
    private static let noStream: UInt32 = 0xFFFFFFFF

    /// Prefix for recipient sub-storage names.
    private static let recipientPrefix = "__recip_version"

    /// Prefix for attachment sub-storage names.
    private static let attachmentPrefix = "__attach_version"

    // MARK: - Public API

    /// Parses the .msg file at the given URL.
    /// - Returns: A fully populated `Email` value.
    /// - Throws: `MSGParserError` with a descriptive message on failure.
    public func parse(url: URL) async throws -> Email {
        // Step 1: Create the appropriate DataReader based on file size
        let reader: DataReader
        do {
            reader = try DataReaderFactory.createReader(for: url)
        } catch {
            throw MSGParserError.fileAccessDenied(url)
        }

        // Step 2: Parse CFB header
        let header: CFBHeader
        do {
            header = try CFBReader.readHeader(from: reader)
        } catch let error as CFBError {
            throw MSGParserError.invalidFormat(error)
        }

        // Step 3: Build FAT
        let fat: [UInt32]
        do {
            fat = try CFBReader.buildFAT(header: header, reader: reader)
        } catch let error as CFBError {
            throw MSGParserError.invalidFormat(error)
        }

        // Step 4: Build mini-FAT
        let miniFAT: [UInt32]
        do {
            miniFAT = try CFBReader.buildMiniFAT(header: header, fat: fat, reader: reader)
        } catch let error as CFBError {
            throw MSGParserError.invalidFormat(error)
        }

        // Step 5: Parse directory entries
        let entries: [DirectoryEntry]
        do {
            entries = try CFBReader.readDirectoryEntries(header: header, fat: fat, reader: reader)
        } catch let error as CFBError {
            throw MSGParserError.invalidFormat(error)
        }

        // Step 6: Find root entry (objectType == .rootStorage, usually index 0)
        guard let rootEntry = entries.first(where: { $0.objectType == .rootStorage }) else {
            throw MSGParserError.invalidFormat(
                CFBError.corruptedFile(sectorIndex: 0, reason: "no root storage entry found")
            )
        }

        // Step 7: Read root's mini-stream container using regular FAT
        // The root entry's stream IS the mini-stream container
        let miniStream: Data
        do {
            miniStream = try CFBReader.readStream(
                entry: rootEntry,
                fat: fat,
                miniFAT: [], // Not needed for reading the root stream (uses regular FAT because root stream >= cutoff)
                miniStream: Data(),
                header: header,
                reader: reader
            )
        } catch let error as CFBError {
            throw MSGParserError.invalidFormat(error)
        }

        // Step 8: Collect children of root storage via directory tree traversal
        let rootChildIndices = collectChildren(of: rootEntry, entries: entries)

        // Step 9: Build streams dictionary for root storage
        let rootStreams: [String: Data]
        do {
            rootStreams = try buildStreamsDictionary(
                childIndices: rootChildIndices,
                entries: entries,
                fat: fat,
                miniFAT: miniFAT,
                miniStream: miniStream,
                header: header,
                reader: reader
            )
        } catch let error as CFBError {
            throw MSGParserError.invalidFormat(error)
        }

        // Step 10: Find recipient sub-storages and build their stream dictionaries
        let recipientStreamsList: [[String: Data]]
        do {
            recipientStreamsList = try buildSubStorageStreamsList(
                prefix: Self.recipientPrefix,
                parentChildIndices: rootChildIndices,
                entries: entries,
                fat: fat,
                miniFAT: miniFAT,
                miniStream: miniStream,
                header: header,
                reader: reader
            )
        } catch let error as CFBError {
            throw MSGParserError.invalidFormat(error)
        }

        // Step 11: Find attachment sub-storages and build their stream dictionaries
        let attachmentStreamsList: [[String: Data]]
        do {
            attachmentStreamsList = try buildSubStorageStreamsList(
                prefix: Self.attachmentPrefix,
                parentChildIndices: rootChildIndices,
                entries: entries,
                fat: fat,
                miniFAT: miniFAT,
                miniStream: miniStream,
                header: header,
                reader: reader
            )
        } catch let error as CFBError {
            throw MSGParserError.invalidFormat(error)
        }

        // Step 12: Extract root properties
        let properties: [MAPIProperty]
        do {
            properties = try MAPIPropertyExtractor.extractProperties(
                from: rootStreams,
                codePage: nil,
                isRootStorage: true
            )
        } catch let error as MSGParserError {
            throw error
        } catch {
            throw MSGParserError.propertyExtractionFailed(error.localizedDescription)
        }

        // Step 13: Find code page from properties (PidTagInternetCodepage, id=0x3FDE)
        let codePage: UInt32? = findCodePage(in: properties)

        // Step 14: Extract recipients
        let recipients: [Recipient]
        do {
            recipients = try MAPIPropertyExtractor.extractRecipients(
                from: recipientStreamsList,
                codePage: codePage
            )
        } catch let error as MSGParserError {
            throw error
        } catch {
            throw MSGParserError.propertyExtractionFailed("recipient extraction failed: \(error.localizedDescription)")
        }

        // Step 15: Extract attachments
        let attachments: [Attachment]
        do {
            attachments = try MAPIPropertyExtractor.extractAttachments(
                from: attachmentStreamsList,
                codePage: codePage
            )
        } catch let error as MSGParserError {
            throw error
        } catch {
            throw MSGParserError.propertyExtractionFailed("attachment extraction failed: \(error.localizedDescription)")
        }

        // Step 16: Extract body content (plain text, HTML, RTF)
        let body = BodyExtractor.extractBody(
            from: properties,
            streams: rootStreams,
            codePage: codePage
        )

        // Step 17: Extract envelope fields from properties
        let subject = findStringProperty(in: properties, id: MAPIPropertyTag.subjectUnicode.id, type: MAPIPropertyTag.subjectUnicode.type)
            ?? findStringProperty(in: properties, id: MAPIPropertyTag.subjectAnsi.id, type: MAPIPropertyTag.subjectAnsi.type)
        let senderName = findStringProperty(in: properties, id: MAPIPropertyTag.senderName.id, type: MAPIPropertyTag.senderName.type)
            ?? findStringProperty(in: properties, id: 0x0042, type: MAPIPropertyTag.typeUnicode)  // PR_SENT_REPRESENTING_NAME
        let senderEmail = findStringProperty(in: properties, id: MAPIPropertyTag.senderEmail.id, type: MAPIPropertyTag.senderEmail.type)
            ?? findStringProperty(in: properties, id: 0x5D01, type: MAPIPropertyTag.typeUnicode)  // PR_SENDER_SMTP_ADDRESS
            ?? findStringProperty(in: properties, id: 0x0065, type: MAPIPropertyTag.typeUnicode)  // PR_SENT_REPRESENTING_EMAIL_ADDRESS
        let sentDate = findDateProperty(in: properties, id: MAPIPropertyTag.clientSubmitTime.id, type: MAPIPropertyTag.clientSubmitTime.type)

        // Step 18: Separate recipients into TO and CC lists
        let toRecipients = recipients.filter { $0.type == .to }
        let ccRecipients = recipients.filter { $0.type == .cc }

        // Step 19: Assemble Email model and return
        return Email(
            subject: subject,
            senderName: senderName,
            senderEmail: senderEmail,
            toRecipients: toRecipients,
            ccRecipients: ccRecipients,
            sentDate: sentDate,
            body: body,
            attachments: attachments
        )
    }

    // MARK: - Directory Tree Traversal

    /// Collects all child entry indices of a storage entry by traversing its red-black tree.
    ///
    /// The CFB directory uses a red-black tree structure. Each storage has a `childID`
    /// pointing to the root of its children tree. Each child has `leftSiblingID` and
    /// `rightSiblingID` forming the tree.
    ///
    /// - Parameters:
    ///   - storage: The parent storage directory entry.
    ///   - entries: All directory entries.
    /// - Returns: An array of indices into `entries` representing all children of the storage.
    private func collectChildren(of storage: DirectoryEntry, entries: [DirectoryEntry]) -> [Int] {
        guard storage.childID != Self.noStream else {
            return []
        }
        var result = [Int]()
        var visited = Set<UInt32>()
        traverseTree(nodeID: storage.childID, entries: entries, visited: &visited, result: &result)
        return result
    }

    /// Recursively traverses the red-black tree of directory entries.
    ///
    /// - Parameters:
    ///   - nodeID: The current node's directory entry index.
    ///   - entries: All directory entries.
    ///   - visited: Set of already visited node IDs (cycle detection).
    ///   - result: Accumulates the indices of all nodes in the tree.
    private func traverseTree(
        nodeID: UInt32,
        entries: [DirectoryEntry],
        visited: inout Set<UInt32>,
        result: inout [Int]
    ) {
        guard nodeID != Self.noStream else { return }
        guard Int(nodeID) < entries.count else { return }
        guard !visited.contains(nodeID) else { return }

        visited.insert(nodeID)

        let entry = entries[Int(nodeID)]

        // Traverse left subtree
        traverseTree(nodeID: entry.leftSiblingID, entries: entries, visited: &visited, result: &result)

        // Visit current node
        result.append(Int(nodeID))

        // Traverse right subtree
        traverseTree(nodeID: entry.rightSiblingID, entries: entries, visited: &visited, result: &result)
    }

    // MARK: - Stream Dictionary Building

    /// Builds a `[String: Data]` dictionary mapping stream names to their data
    /// for all stream-type entries in the given child indices.
    ///
    /// - Parameters:
    ///   - childIndices: Indices of child entries to include.
    ///   - entries: All directory entries.
    ///   - fat: The complete FAT.
    ///   - miniFAT: The mini-FAT.
    ///   - miniStream: The mini-stream container data.
    ///   - header: The parsed CFB header.
    ///   - reader: The data reader.
    /// - Returns: A dictionary mapping entry names to their stream data.
    /// - Throws: `CFBError` if reading a stream fails.
    private func buildStreamsDictionary(
        childIndices: [Int],
        entries: [DirectoryEntry],
        fat: [UInt32],
        miniFAT: [UInt32],
        miniStream: Data,
        header: CFBHeader,
        reader: DataReader
    ) throws -> [String: Data] {
        var streams = [String: Data]()

        for index in childIndices {
            let entry = entries[index]
            guard entry.objectType == .stream else { continue }

            let data = try CFBReader.readStream(
                entry: entry,
                fat: fat,
                miniFAT: miniFAT,
                miniStream: miniStream,
                header: header,
                reader: reader
            )
            streams[entry.name] = data
        }

        return streams
    }

    /// Builds an array of stream dictionaries for sub-storages matching a given name prefix.
    ///
    /// Used for recipient and attachment sub-storages.
    ///
    /// - Parameters:
    ///   - prefix: The name prefix to match (e.g., "__recip_version2.0_#" or "__attach_version2.0_#").
    ///   - parentChildIndices: Indices of the parent storage's children.
    ///   - entries: All directory entries.
    ///   - fat: The complete FAT.
    ///   - miniFAT: The mini-FAT.
    ///   - miniStream: The mini-stream container data.
    ///   - header: The parsed CFB header.
    ///   - reader: The data reader.
    /// - Returns: An array of stream dictionaries, one per matching sub-storage.
    /// - Throws: `CFBError` if reading a stream fails.
    private func buildSubStorageStreamsList(
        prefix: String,
        parentChildIndices: [Int],
        entries: [DirectoryEntry],
        fat: [UInt32],
        miniFAT: [UInt32],
        miniStream: Data,
        header: CFBHeader,
        reader: DataReader
    ) throws -> [[String: Data]] {
        // Find all sub-storages matching the prefix
        let matchingIndices = parentChildIndices.filter { index in
            let entry = entries[index]
            return entry.objectType == .storage && entry.name.hasPrefix(prefix)
        }

        // Sort by name to ensure consistent ordering
        let sortedIndices = matchingIndices.sorted { a, b in
            entries[a].name < entries[b].name
        }

        var result = [[String: Data]]()
        result.reserveCapacity(sortedIndices.count)

        for storageIndex in sortedIndices {
            let storageEntry = entries[storageIndex]
            let childIndices = collectChildren(of: storageEntry, entries: entries)
            let streams = try buildStreamsDictionary(
                childIndices: childIndices,
                entries: entries,
                fat: fat,
                miniFAT: miniFAT,
                miniStream: miniStream,
                header: header,
                reader: reader
            )
            result.append(streams)
        }

        return result
    }

    // MARK: - Property Lookup Helpers

    /// Finds the code page value from PidTagInternetCodepage in the properties.
    private func findCodePage(in properties: [MAPIProperty]) -> UInt32? {
        for property in properties {
            if property.tag.id == MAPIPropertyTag.internetCodePage.id
                && property.tag.type == MAPIPropertyTag.internetCodePage.type {
                if case .int32(let value) = property.value {
                    return UInt32(bitPattern: value)
                }
            }
        }
        return nil
    }

    /// Finds a string property value by tag ID (ignoring type to handle both STRING8 and UNICODE variants).
    private func findStringProperty(in properties: [MAPIProperty], id: UInt16, type: UInt16) -> String? {
        for property in properties {
            if property.tag.id == id {
                if case .string(let value) = property.value {
                    return value.isEmpty ? nil : value
                }
            }
        }
        return nil
    }

    /// Finds a date property value by tag ID (ignoring type to handle variant property types).
    private func findDateProperty(in properties: [MAPIProperty], id: UInt16, type: UInt16) -> Date? {
        for property in properties {
            if property.tag.id == id {
                if case .time(let date) = property.value {
                    return date
                }
            }
        }
        return nil
    }
}
