// MappedDataReaderTests - Unit tests for MappedDataReader and DataReaderFactory

import XCTest
@testable import MSGParser

final class MappedDataReaderTests: XCTestCase {

    // MARK: - MappedDataReader Tests

    func testMappedDataReaderCount() throws {
        let url = try createTempFile(size: 256)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try MappedDataReader(url: url)
        XCTAssertEqual(reader.count, 256)
    }

    func testMappedDataReaderReadBytes() throws {
        let testData = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
        let url = try createTempFile(with: testData)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try MappedDataReader(url: url)
        let result = try reader.readBytes(at: 2, length: 4)
        XCTAssertEqual(result, Data([0x02, 0x03, 0x04, 0x05]))
    }

    func testMappedDataReaderReadBytesAtStart() throws {
        let testData = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let url = try createTempFile(with: testData)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try MappedDataReader(url: url)
        let result = try reader.readBytes(at: 0, length: 2)
        XCTAssertEqual(result, Data([0xAA, 0xBB]))
    }

    func testMappedDataReaderReadBytesAtEnd() throws {
        let testData = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let url = try createTempFile(with: testData)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try MappedDataReader(url: url)
        let result = try reader.readBytes(at: 2, length: 2)
        XCTAssertEqual(result, Data([0xCC, 0xDD]))
    }

    func testMappedDataReaderOutOfBoundsOffset() throws {
        let testData = Data([0x01, 0x02, 0x03, 0x04])
        let url = try createTempFile(with: testData)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try MappedDataReader(url: url)
        XCTAssertThrowsError(try reader.readBytes(at: 5, length: 1)) { error in
            guard case DataReaderError.outOfBounds(let offset, let length, let available) = error else {
                XCTFail("Expected DataReaderError.outOfBounds, got \(error)")
                return
            }
            XCTAssertEqual(offset, 5)
            XCTAssertEqual(length, 1)
            XCTAssertEqual(available, 4)
        }
    }

    func testMappedDataReaderOutOfBoundsLength() throws {
        let testData = Data([0x01, 0x02, 0x03, 0x04])
        let url = try createTempFile(with: testData)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try MappedDataReader(url: url)
        XCTAssertThrowsError(try reader.readBytes(at: 2, length: 5)) { error in
            guard case DataReaderError.outOfBounds(let offset, let length, let available) = error else {
                XCTFail("Expected DataReaderError.outOfBounds, got \(error)")
                return
            }
            XCTAssertEqual(offset, 2)
            XCTAssertEqual(length, 5)
            XCTAssertEqual(available, 4)
        }
    }

    func testMappedDataReaderNegativeOffset() throws {
        let testData = Data([0x01, 0x02, 0x03, 0x04])
        let url = try createTempFile(with: testData)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try MappedDataReader(url: url)
        XCTAssertThrowsError(try reader.readBytes(at: -1, length: 1)) { error in
            guard case DataReaderError.outOfBounds = error else {
                XCTFail("Expected DataReaderError.outOfBounds, got \(error)")
                return
            }
        }
    }

    func testMappedDataReaderReadInteger() throws {
        // Little-endian UInt32: 0x04030201
        let testData = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08])
        let url = try createTempFile(with: testData)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try MappedDataReader(url: url)
        let value: UInt32 = try reader.readInteger(at: 0)
        XCTAssertEqual(value, 0x04030201)
    }

    func testMappedDataReaderReadIntegerAtOffset() throws {
        let testData = Data([0x00, 0x00, 0xFF, 0x00])
        let url = try createTempFile(with: testData)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try MappedDataReader(url: url)
        let value: UInt16 = try reader.readInteger(at: 2)
        XCTAssertEqual(value, 0x00FF)
    }

    func testMappedDataReaderReadIntegerOutOfBounds() throws {
        let testData = Data([0x01, 0x02, 0x03])
        let url = try createTempFile(with: testData)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try MappedDataReader(url: url)
        XCTAssertThrowsError(try reader.readInteger(at: 2) as UInt32) { error in
            guard case DataReaderError.outOfBounds = error else {
                XCTFail("Expected DataReaderError.outOfBounds, got \(error)")
                return
            }
        }
    }

    func testMappedDataReaderZeroLengthRead() throws {
        let testData = Data([0x01, 0x02, 0x03, 0x04])
        let url = try createTempFile(with: testData)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try MappedDataReader(url: url)
        let result = try reader.readBytes(at: 0, length: 0)
        XCTAssertEqual(result.count, 0)
    }

    // MARK: - DataReaderFactory Tests

    func testFactoryReturnsInMemoryReaderForSmallFile() throws {
        // Create a file smaller than 1 MB threshold
        let url = try createTempFile(size: 512)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try DataReaderFactory.createReader(for: url)
        XCTAssertTrue(reader is InMemoryDataReader)
        XCTAssertEqual(reader.count, 512)
    }

    func testFactoryReturnsInMemoryReaderAtThreshold() throws {
        // Create a file exactly at 1 MB threshold (should use InMemory)
        let url = try createTempFile(size: DataReaderFactory.memorySizeThreshold)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try DataReaderFactory.createReader(for: url)
        XCTAssertTrue(reader is InMemoryDataReader)
        XCTAssertEqual(reader.count, DataReaderFactory.memorySizeThreshold)
    }

    func testFactoryReturnsMappedReaderAboveThreshold() throws {
        // Create a file just above 1 MB threshold
        let size = DataReaderFactory.memorySizeThreshold + 1
        let url = try createTempFile(size: size)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try DataReaderFactory.createReader(for: url)
        XCTAssertTrue(reader is MappedDataReader)
        XCTAssertEqual(reader.count, size)
    }

    func testFactoryReaderProducesCorrectData() throws {
        let testData = Data(repeating: 0xAB, count: 100)
        let url = try createTempFile(with: testData)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try DataReaderFactory.createReader(for: url)
        let result = try reader.readBytes(at: 0, length: 100)
        XCTAssertEqual(result, testData)
    }

    func testFactoryThresholdConstant() {
        XCTAssertEqual(DataReaderFactory.memorySizeThreshold, 1_048_576)
    }

    // MARK: - Helpers

    private func createTempFile(size: Int) throws -> URL {
        let data = Data(repeating: 0x42, count: size)
        return try createTempFile(with: data)
    }

    private func createTempFile(with data: Data) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "test_\(UUID().uuidString).bin"
        let url = tempDir.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }
}
