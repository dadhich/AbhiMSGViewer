# MSG File Viewer

A native macOS application for reading Microsoft Outlook `.msg` files completely offline. Built with Swift and SwiftUI.

<img width="892" height="468" alt="image" src="https://github.com/user-attachments/assets/fb3c0fda-e9e4-4029-bdf3-a49204bd8c87" />


## Requirements

- macOS 13+
- Swift 5.9+
- Xcode 15+ (optional, for GUI development)

## Build

```bash
swift build
```

## Run

```bash
swift run MSGFileViewer
```

Or run the built binary directly:

```bash
.build/debug/MSGFileViewer
```

## Run with Xcode

```bash
open Package.swift
```

Then press ⌘R to build and run.

## Opening .msg Files

Once the app is running, you can open `.msg` files in several ways:

- **Drag and drop** a `.msg` file onto the app window
- **File > Open** (⌘O) to browse for a file
- **Double-click** a `.msg` file in Finder (after UTType registration)
- **Drag** a `.msg` file onto the dock icon

## Run Tests

```bash
swift test
```

This runs all 107 tests including property-based tests (SwiftCheck) across the full parsing and presentation pipeline.

## Project Structure

```
Sources/
├── MSGParser/          # OLE/CFB parser, MAPI extractor, LZFu decompressor
└── MSGFileViewer/      # SwiftUI app, views, view models, window management
Tests/
└── MSGParserTests/     # Unit, property-based, integration, and performance tests
```

## Features

- Parses OLE/CFB binary format directly in Swift (no external C dependencies)
- Extracts email metadata, body (HTML/plain text/RTF), and attachments
- Memory-mapped I/O for large files (>1 MB)
- Multi-window support with deduplication (max 20 windows)
- Fully offline — no network access, no telemetry
- App sandbox with network entitlements denied
