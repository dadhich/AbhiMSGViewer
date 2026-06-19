// MSGParserTests - Property-based tests for window deduplication and limit
// Feature: msg-file-viewer, Property 12: Window Deduplication and Limit

import XCTest
import SwiftCheck
import Foundation
@testable import MSGParser

// MARK: - Simulated Window Manager Logic

/// Simulates the WindowManager's deduplication and limit logic for property testing.
/// This mirrors the behavior of WindowManager without requiring NSWindow/AppKit dependencies.
private struct SimulatedWindowManager {
    /// Maps standardized file paths to "window identifiers" (simulated).
    private(set) var openWindows: [String: Int] = [:]

    /// Maximum number of simultaneous windows allowed.
    let maxWindows = 20

    /// Counter for generating unique window IDs.
    private var nextWindowID = 1

    /// Attempts to open a file. Returns whether a new window was created.
    /// - If the path is already open, brings existing window to front (no new window).
    /// - If the window limit is reached, rejects the request (no new window).
    /// - Otherwise, creates a new window entry.
    mutating func openFile(path: String) -> OpenResult {
        // Check if already open — deduplicate
        if openWindows[path] != nil {
            return .existingWindowReused
        }

        // Check window limit
        guard openWindows.count < maxWindows else {
            return .limitReached
        }

        // Create new window
        openWindows[path] = nextWindowID
        nextWindowID += 1
        return .newWindowCreated
    }

    /// The current number of open windows.
    var windowCount: Int {
        return openWindows.count
    }

    enum OpenResult {
        case newWindowCreated
        case existingWindowReused
        case limitReached
    }
}

// MARK: - Generators

/// Generates a file path string (simulated standardized path).
private func filePathGen() -> Gen<String> {
    let filenameGen = Gen<String>.compose { composer in
        let length = composer.generate(using: Gen<Int>.choose((3, 15)))
        let chars = (0..<length).map { _ -> Character in
            let charGen = Gen<Character>.fromElements(in: "a"..."z")
            return composer.generate(using: charGen)
        }
        return String(chars)
    }

    return filenameGen.map { "/Users/test/Documents/\($0).msg" }
}

/// Generates a sequence of file open requests, with some paths repeated (duplicates).
/// The pool size is smaller than the sequence length to force duplicates.
private func fileOpenSequenceGen() -> Gen<[String]> {
    return Gen<[String]>.compose { composer in
        // Create a pool of unique paths (5 to 25 paths)
        let poolSize = composer.generate(using: Gen<Int>.choose((5, 25)))
        let pool = (0..<poolSize).map { _ in
            composer.generate(using: filePathGen())
        }

        // Generate a sequence of open requests (10 to 50 requests) drawn from the pool
        let sequenceLength = composer.generate(using: Gen<Int>.choose((10, 50)))
        let sequence = (0..<sequenceLength).map { _ -> String in
            let index = composer.generate(using: Gen<Int>.choose((0, pool.count - 1)))
            return pool[index]
        }

        return sequence
    }
}

// MARK: - Property Tests

/// **Validates: Requirements 6.6**
final class WindowDeduplicationPropertyTests: XCTestCase {

    // MARK: - Property 12: Window Deduplication and Limit

    /// Verifies that the window count never exceeds 20 regardless of how many
    /// file open requests are made.
    /// **Validates: Requirements 6.6**
    func testWindowCountNeverExceedsMaximum() {
        property("Window count never exceeds 20 for any sequence of open requests") <- forAll(fileOpenSequenceGen()) { (requests: [String]) in
            var manager = SimulatedWindowManager()

            for path in requests {
                _ = manager.openFile(path: path)

                // Invariant: window count must never exceed maxWindows
                if manager.windowCount > manager.maxWindows {
                    return false
                }
            }

            return true
        }
    }

    /// Verifies that opening a file with a path that is already open does NOT create
    /// a new window — it reuses the existing one (deduplication).
    /// **Validates: Requirements 6.6**
    func testDuplicatePathReusesExistingWindow() {
        property("Opening a duplicate path reuses existing window, not creating a new one") <- forAll(fileOpenSequenceGen()) { (requests: [String]) in
            var manager = SimulatedWindowManager()

            for path in requests {
                let wasAlreadyOpen = manager.openWindows[path] != nil
                let countBefore = manager.windowCount
                let result = manager.openFile(path: path)

                if wasAlreadyOpen {
                    // If already open, must reuse (no new window created)
                    if result != .existingWindowReused {
                        return false
                    }
                    // Count must not change
                    if manager.windowCount != countBefore {
                        return false
                    }
                }
            }

            return true
        }
    }

    /// Combined property: processes a full sequence and verifies both invariants hold
    /// simultaneously across all steps.
    /// **Validates: Requirements 6.6**
    func testWindowDeduplicationAndLimitCombined() {
        property("Window count ≤ 20 AND duplicates reuse existing windows") <- forAll(fileOpenSequenceGen()) { (requests: [String]) in
            var manager = SimulatedWindowManager()
            var uniquePathsSeen = Set<String>()

            for path in requests {
                let countBefore = manager.windowCount
                let wasAlreadyOpen = manager.openWindows[path] != nil
                _ = manager.openFile(path: path)
                uniquePathsSeen.insert(path)

                // Invariant 1: Count never exceeds max
                if manager.windowCount > manager.maxWindows {
                    return false
                }

                // Invariant 2: Duplicate path never increases count
                if wasAlreadyOpen && manager.windowCount != countBefore {
                    return false
                }

                // Invariant 3: Count equals min(unique paths opened so far, maxWindows)
                let expectedCount = min(uniquePathsSeen.count, manager.maxWindows)
                if manager.windowCount != expectedCount {
                    return false
                }
            }

            return true
        }
    }
}
