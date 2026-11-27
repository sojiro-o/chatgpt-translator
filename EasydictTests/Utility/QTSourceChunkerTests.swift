//
//  QTSourceChunkerTests.swift
//  EasydictTests
//
//  Created by QuickTranslate on 2026/11/27.
//  Copyright © 2026 izual. All rights reserved.
//

import Foundation
import Testing

@testable import Easydict

// MARK: - QTSourceChunkerTests

@Suite("QuickTranslate Source Chunker", .tags(.utilities, .unit))
struct QTSourceChunkerTests {
    // MARK: Internal

    @Test("Chunks cover English text in order without overlap, empty ranges, or surrounding whitespace", .tags(.utilities, .unit))
    func testChunkInvariantsOnEnglishTexts() {
        let samples = [
            "Among patients with acute intracerebral hemorrhage who were receiving oral anticoagulants, reversal of anticoagulation is critical.",
            "When you drag a phrase in the English source text, the corresponding Japanese translation is highlighted in the same color.\nThis helps you check how each clause was translated.",
            "\"QuickTranslate\" (a menu bar translator) translates copied English text into natural Japanese.",
            "A single short phrase.",
        ]

        for sample in samples {
            let chunks = QTSourceChunker.chunk(sample)
            #expect(chunks != nil)
            guard let chunks else { continue }

            assertInvariants(chunks: chunks, in: sample)

            let annotated = QTSourceChunker.annotate(sample, chunks: chunks)
            #expect(QTAlignmentParser.stripMarkers(from: annotated) == sample.trim())
        }
    }

    @Test("Long clause without prepositions or conjunctions is split into multiple valid chunks", .tags(.utilities, .unit))
    func testLongClauseIsSplit() {
        let text = "The quick brown fox jumps rapidly over the lazy sleeping dog every single sunny afternoon."
        let chunks = QTSourceChunker.chunk(text)
        #expect(chunks != nil)
        guard let chunks else { return }

        #expect(chunks.count >= 2)
        assertInvariants(chunks: chunks, in: text)
    }

    @Test("Returns nil when source contains double square brackets", .tags(.utilities, .unit))
    func testRejectsDoubleSquareBrackets() {
        #expect(QTSourceChunker.chunk("This text already has [[1]] inside it.") == nil)
        #expect(QTSourceChunker.chunk("Contains opening [[ bracket pair in English text.") == nil)
        #expect(QTSourceChunker.chunk("Contains closing ]] bracket pair in English text.") == nil)
    }

    @Test("Returns nil when source exceeds character limit or chunk count limit", .tags(.utilities, .unit))
    func testRejectsExceedingLimits() {
        let tooLongText = String(repeating: "Hello world. ", count: 260)
        #expect(tooLongText.count > QTSourceChunker.maxCharacterCount)
        #expect(QTSourceChunker.chunk(tooLongText) == nil)

        // 85 short clauses separated by commas -> exceeds 80 chunks while staying under 3,000 chars.
        let tooManyChunksText = (1 ... 85)
            .map { "item \($0) is valid" }
            .joined(separator: ", ")
        #expect(tooManyChunksText.count <= QTSourceChunker.maxCharacterCount)
        #expect(QTSourceChunker.chunk(tooManyChunksText) == nil)
    }

    @Test("Returns nil for empty, whitespace-only, or non-Latin texts", .tags(.utilities, .unit))
    func testRejectsEmptyOrNonLatinTexts() {
        #expect(QTSourceChunker.chunk("") == nil)
        #expect(QTSourceChunker.chunk("   \n\t  ") == nil)
        #expect(QTSourceChunker.chunk("これは日本語だけで書かれたテキストです。英語は含まれていません。") == nil)
        #expect(QTSourceChunker.chunk("12345 67890 + 11111 = 91346") == nil)
    }

    // MARK: Private

    private func assertInvariants(chunks: [QTSourceChunk], in text: String) {
        let nsText = text as NSString
        #expect(!chunks.isEmpty)
        #expect(chunks.count <= QTSourceChunker.maxChunkCount)

        // IDs must be 1-based consecutive integers.
        let expectedIDs = Array(1 ... chunks.count)
        #expect(chunks.map(\.id) == expectedIDs)

        var cursor = 0
        for chunk in chunks {
            // Range must be non-empty and within bounds.
            #expect(chunk.range.length > 0)
            #expect(chunk.range.location >= cursor)
            #expect(NSMaxRange(chunk.range) <= nsText.length)

            // Gap before this chunk must contain only whitespace/newlines.
            if chunk.range.location > cursor {
                let gap = nsText.substring(with: NSRange(location: cursor, length: chunk.range.location - cursor))
                #expect(gap.trim().isEmpty)
            }

            // Chunk text itself must not have leading or trailing whitespace.
            let chunkString = nsText.substring(with: chunk.range)
            #expect(!chunkString.isEmpty)
            #expect(chunkString == chunkString.trim())

            cursor = NSMaxRange(chunk.range)
        }

        // Trailing gap after the last chunk must contain only whitespace/newlines.
        if cursor < nsText.length {
            let tail = nsText.substring(with: NSRange(location: cursor, length: nsText.length - cursor))
            #expect(tail.trim().isEmpty)
        }
    }
}
