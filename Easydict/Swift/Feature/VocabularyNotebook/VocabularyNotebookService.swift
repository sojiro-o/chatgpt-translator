//
//  VocabularyNotebookService.swift
//  Easydict
//
//  Created by izual on 2026/9/15.
//  Copyright © 2026 izual. All rights reserved.
//

import Defaults
import Foundation

// MARK: - VocabularyNotebookService

/// Appends completed query results to the local `words.jsonl` file consumed by an
/// external review program and synced via Syncthing.
///
/// The service is view-free: write failures are surfaced through a
/// `Notification.Name.vocabularyNotebookWriteFailed` notification instead of an
/// `NSAlert`, keeping the write logic decoupled from UI.
@objc(VocabularyNotebookService)
@objcMembers
final class VocabularyNotebookService: NSObject {
    // MARK: Lifecycle

    override init() {
        super.init()
    }

    // MARK: Internal

    static let shared = VocabularyNotebookService()

    /// No-op: vocabulary notebook persistence is disabled in QuickTranslate.
    func append(queryModel: QueryModel, result: QueryResult) {
        _ = (queryModel, result)
    }

    /// Blocks until all previously queued appends have been written to disk.
    ///
    /// Called from EasydictApp's synchronous termination handler so a query that completes right before
    /// the app quits is still persisted instead of being dropped with the process.
    func flush() {
        appendQueue.sync {}
    }

    // MARK: Private

    /// File name of the JSONL notebook in the selected directory.
    private static let fileName = "words.jsonl"

    /// Serializes appends so UI and HTTP writes never interleave in a single process.
    private let appendQueue = DispatchQueue(label: "io.github.sojiro-o.QuickTranslate.vocabulary-notebook")

    private static func append(_ entry: VocabularyEntry, to directory: String) throws {
        let directoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        let fileURL = directoryURL.appendingPathComponent(fileName)
        if !fileManager.fileExists(atPath: fileURL.path) {
            fileManager.createFile(atPath: fileURL.path, contents: nil)
        }

        let encoder = makeEncoder()
        let data = try encoder.encode(entry)
        var line = data
        line.append(0x0A)

        let handle = try FileHandle(forUpdating: fileURL)
        defer { try? handle.close() }
        let endOffset = try handle.seekToEnd()
        // A file written by another tool may not end with a newline; insert one so the
        // appended record stays on its own JSONL line instead of concatenating with the
        // previous one.
        if endOffset > 0 {
            try handle.seek(toOffset: endOffset - 1)
            let lastByte = try handle.read(upToCount: 1)
            try handle.seekToEnd()
            if lastByte != Data([0x0A]) {
                try handle.write(contentsOf: Data([0x0A]))
            }
        }
        try handle.write(contentsOf: line)
        try handle.synchronize()
    }

    /// Builds an encoder that formats timestamps in local ISO 8601 time.
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            // DateFormatter is not thread-safe; create a fresh instance per encode.
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }
}
