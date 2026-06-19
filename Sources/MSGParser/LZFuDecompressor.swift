// MSGParser - LZFu Decompression
// Implements Microsoft's LZFu algorithm for decompressing RTF body content
// stored in PidTagRtfCompressed (0x1009)

import Foundation

/// Decompresses LZFu-compressed RTF data as stored in PidTagRtfCompressed.
public struct LZFuDecompressor {
    /// The LZFu signature for compressed data: "LZFu" (little-endian)
    public static let compressedSignature: UInt32 = 0x75465A4C

    /// The signature for uncompressed (raw) RTF data: "MELA" (little-endian)
    public static let uncompressedSignature: UInt32 = 0x414C454D

    /// The standard RTF dictionary initialization string used by LZFu.
    private static let dictionaryInitString: [UInt8] = Array(
        "{\\rtf1\\ansi\\mac\\deff0\\deftab720{\\fonttbl;}{\\f0\\fnil \\froman \\fswiss \\fmodern \\fscript \\fdecor MS Sans SerifSymbolArialTimes New RomanCourier{\\colortbl\\red0\\green0\\blue0\r\n\\par \\pard\\plain\\f0\\fs20\\b\\i\\ul\\ob\\strike\\scaps\\caps\\outl\\shadow\\shad\\cf0\\cb0\\sub\\nosupersub\\super\\nosupersub\\ul\\ulnone".utf8
    )

    /// Dictionary size for LZFu sliding window.
    private static let dictionarySize = 4096

    /// Header size in bytes (compressedSize + uncompressedSize + signature + CRC).
    private static let headerSize = 16

    /// CRC32 lookup table (standard polynomial 0xEDB88320).
    private static let crc32Table: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt32(i)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
            table[i] = crc
        }
        return table
    }()

    /// Computes CRC32 over the given data.
    private static func computeCRC32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ crc32Table[index]
        }
        return crc ^ 0xFFFFFFFF
    }

    /// Decompresses LZFu-encoded RTF data.
    /// - Parameter compressedData: The raw compressed data from PidTagRtfCompressed.
    /// - Returns: The decompressed RTF content as Data.
    /// - Throws: `LZFuError.invalidSignature`, `LZFuError.crcMismatch`,
    ///           `LZFuError.corruptedData`
    public static func decompress(_ compressedData: Data) throws -> Data {
        // Minimum header size check
        guard compressedData.count >= headerSize else {
            throw LZFuError.corruptedData(position: 0)
        }

        // Parse header (all little-endian UInt32 values)
        let compressedSize = compressedData.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self)
        }
        let uncompressedSize = compressedData.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)
        }
        let signature = compressedData.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self)
        }
        let crc = compressedData.withUnsafeBytes {
            $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self)
        }

        // Validate signature
        guard signature == compressedSignature || signature == uncompressedSignature else {
            throw LZFuError.invalidSignature
        }

        // The actual payload data starts after the 16-byte header.
        // compressedSize includes everything after the compressedSize field itself,
        // so the payload length is compressedSize - 12 (subtracting uncompressedSize + signature + CRC).
        let payloadLength = Int(compressedSize) - 12
        guard payloadLength >= 0 else {
            throw LZFuError.corruptedData(position: 0)
        }

        // Validate we have enough data
        guard compressedData.count >= headerSize + payloadLength else {
            throw LZFuError.corruptedData(position: headerSize)
        }

        let payloadData = compressedData.subdata(in: headerSize..<(headerSize + payloadLength))

        // Validate CRC32 (only if non-zero — many real MSG files have CRC=0)
        if crc != 0 {
            let computedCRC = computeCRC32(payloadData)
            if computedCRC != crc {
                throw LZFuError.crcMismatch(expected: crc, computed: computedCRC)
            }
        }

        // Handle uncompressed (MELA) signature
        if signature == uncompressedSignature {
            let resultLength = min(Int(uncompressedSize), payloadData.count)
            return payloadData.prefix(resultLength)
        }

        // LZFu decompression with sliding window
        return try decompressLZFu(payload: payloadData, uncompressedSize: Int(uncompressedSize))
    }

    /// Performs the actual LZFu sliding window decompression.
    private static func decompressLZFu(payload: Data, uncompressedSize: Int) throws -> Data {
        // Initialize 4096-byte dictionary with standard RTF control words
        var dictionary = [UInt8](repeating: 0, count: dictionarySize)
        let initLength = min(dictionaryInitString.count, dictionarySize)
        for i in 0..<initLength {
            dictionary[i] = dictionaryInitString[i]
        }
        var dictWritePos = initLength

        var output = Data()
        output.reserveCapacity(uncompressedSize)

        var pos = 0
        let payloadBytes = [UInt8](payload)
        let payloadCount = payloadBytes.count

        while output.count < uncompressedSize {
            // Read control byte
            guard pos < payloadCount else {
                break
            }
            let controlByte = payloadBytes[pos]
            pos += 1

            // Process each bit in the control byte (LSB first)
            for bitIndex in 0..<8 {
                // Stop if we've reached the desired output size
                if output.count >= uncompressedSize {
                    break
                }

                let bit = (controlByte >> bitIndex) & 1

                if bit == 1 {
                    // Literal byte
                    guard pos < payloadCount else {
                        // Data exhausted
                        return output
                    }
                    let literalByte = payloadBytes[pos]
                    pos += 1

                    output.append(literalByte)
                    dictionary[dictWritePos % dictionarySize] = literalByte
                    dictWritePos += 1
                } else {
                    // Dictionary reference: read 2 bytes
                    guard pos + 1 < payloadCount else {
                        // Data exhausted
                        return output
                    }
                    let byte1 = UInt16(payloadBytes[pos])
                    let byte2 = UInt16(payloadBytes[pos + 1])
                    pos += 2

                    // Upper 12 bits = offset, lower 4 bits + 2 = length
                    let offset = Int((byte1 << 4) | (byte2 >> 4))
                    let length = Int((byte2 & 0x0F)) + 2

                    // Check for end-of-data marker
                    // In LZFu, offset pointing to current write position with length 2
                    // signifies end of compressed data
                    if offset == dictWritePos % dictionarySize {
                        return output
                    }

                    // Copy from dictionary
                    for i in 0..<length {
                        if output.count >= uncompressedSize {
                            break
                        }
                        let dictByte = dictionary[(offset + i) % dictionarySize]
                        output.append(dictByte)
                        dictionary[dictWritePos % dictionarySize] = dictByte
                        dictWritePos += 1
                    }
                }
            }
        }

        return output
    }
}
