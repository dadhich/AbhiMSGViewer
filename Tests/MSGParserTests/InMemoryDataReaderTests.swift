// InMemoryDataReaderTests - Unit tests for InMemoryDataReader

import XCTest
@testable import MSGParser

final class InMemoryDataReaderTests: XCTestCase {

    // MARK: - count

    func testCountReturnsDataLength() {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let reader = InMemoryDataReader(data: data)
        XCTAssertEqual(reader.count, 4)
    }

    func testCountReturnsZeroForEmptyData() {
        let reader = InMemoryDataReader(data: Data())
        XCTAssertEqual(reader.count, 0)
    }

    // MARK: - readBytes

    func testReadBytesReturnsCorrectSlice() throws {
        let data = Data([0x0A, 0x0B, 0x0C, 0x0D, 0x0E])
        let reader = InMemoryDataReader(data: data)

        let result = try reader.readBytes(at: 1, length: 3)
        XCTAssertEqual(result, Data([0x0B, 0x0C, 0x0D]))
    }

    func testReadBytesAtStartOfData() throws {
        let data = Data([0x01, 0x02, 0x03])
        let reader = InMemoryDataReader(data: data)

        let result = try reader.readBytes(at: 0, length: 3)
        XCTAssertEqual(result, Data([0x01, 0x02, 0x03]))
    }

    func testReadBytesZeroLengthSucceeds() throws {
        let data = Data([0x01, 0x02, 0x03])
        let reader = InMemoryDataReader(data: data)

        let result = try reader.readBytes(at: 2, length: 0)
        XCTAssertEqual(result, Data())
    }

    func testReadBytesThrowsOutOfBoundsWhenOffsetExceedsCount() {
        let data = Data([0x01, 0x02])
        let reader = InMemoryDataReader(data: data)

        XCTAssertThrowsError(try reader.readBytes(at: 3, length: 1)) { error in
            guard case DataReaderError.outOfBounds(let offset, let length, let available) = error else {
                XCTFail("Expected DataReaderError.outOfBounds, got \(error)")
                return
            }
            XCTAssertEqual(offset, 3)
            XCTAssertEqual(length, 1)
            XCTAssertEqual(available, 2)
        }
    }

    func testReadBytesThrowsOutOfBoundsWhenLengthExceedsAvailable() {
        let data = Data([0x01, 0x02, 0x03])
        let reader = InMemoryDataReader(data: data)

        XCTAssertThrowsError(try reader.readBytes(at: 1, length: 5)) { error in
            guard case DataReaderError.outOfBounds(let offset, let length, let available) = error else {
                XCTFail("Expected DataReaderError.outOfBounds, got \(error)")
                return
            }
            XCTAssertEqual(offset, 1)
            XCTAssertEqual(length, 5)
            XCTAssertEqual(available, 3)
        }
    }

    func testReadBytesThrowsOutOfBoundsOnEmptyData() {
        let reader = InMemoryDataReader(data: Data())

        XCTAssertThrowsError(try reader.readBytes(at: 0, length: 1)) { error in
            guard case DataReaderError.outOfBounds(let offset, let length, let available) = error else {
                XCTFail("Expected DataReaderError.outOfBounds, got \(error)")
                return
            }
            XCTAssertEqual(offset, 0)
            XCTAssertEqual(length, 1)
            XCTAssertEqual(available, 0)
        }
    }

    func testReadBytesThrowsForNegativeOffset() {
        let data = Data([0x01, 0x02, 0x03])
        let reader = InMemoryDataReader(data: data)

        XCTAssertThrowsError(try reader.readBytes(at: -1, length: 1)) { error in
            guard case DataReaderError.outOfBounds = error else {
                XCTFail("Expected DataReaderError.outOfBounds, got \(error)")
                return
            }
        }
    }

    // MARK: - readInteger (default implementation via extension)

    func testReadUInt16LittleEndian() throws {
        // 0x0201 in little-endian is [0x01, 0x02]
        let data = Data([0x01, 0x02])
        let reader = InMemoryDataReader(data: data)

        let value: UInt16 = try reader.readInteger(at: 0)
        XCTAssertEqual(value, 0x0201)
    }

    func testReadUInt32LittleEndian() throws {
        // 0x04030201 in little-endian is [0x01, 0x02, 0x03, 0x04]
        let data = Data([0x01, 0x02, 0x03, 0x04])
        let reader = InMemoryDataReader(data: data)

        let value: UInt32 = try reader.readInteger(at: 0)
        XCTAssertEqual(value, 0x04030201)
    }

    func testReadUInt64LittleEndian() throws {
        // 0x0807060504030201 in little-endian
        let data = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        let reader = InMemoryDataReader(data: data)

        let value: UInt64 = try reader.readInteger(at: 0)
        XCTAssertEqual(value, 0x0807060504030201)
    }

    func testReadIntegerAtOffset() throws {
        let data = Data([0xFF, 0xFF, 0x01, 0x02, 0x03, 0x04])
        let reader = InMemoryDataReader(data: data)

        let value: UInt32 = try reader.readInteger(at: 2)
        XCTAssertEqual(value, 0x04030201)
    }

    func testReadIntegerThrowsWhenInsufficientBytes() {
        let data = Data([0x01, 0x02, 0x03])
        let reader = InMemoryDataReader(data: data)

        XCTAssertThrowsError(try {
            let _: UInt32 = try reader.readInteger(at: 1)
        }()) { error in
            guard case DataReaderError.outOfBounds = error else {
                XCTFail("Expected DataReaderError.outOfBounds, got \(error)")
                return
            }
        }
    }

    func testReadInt16LittleEndian() throws {
        // -1 as Int16 in little-endian is [0xFF, 0xFF]
        let data = Data([0xFF, 0xFF])
        let reader = InMemoryDataReader(data: data)

        let value: Int16 = try reader.readInteger(at: 0)
        XCTAssertEqual(value, -1)
    }
}
