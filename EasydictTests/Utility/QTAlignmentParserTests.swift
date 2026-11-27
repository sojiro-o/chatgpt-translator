//
//  QTAlignmentParserTests.swift
//  EasydictTests
//
//  Created by QuickTranslate on 2026/11/27.
//  Copyright © 2026 izual. All rights reserved.
//

import Foundation
import Testing

@testable import Easydict

// MARK: - QTAlignmentParserTests

@Suite("QuickTranslate Alignment Parser", .tags(.utilities, .unit))
struct QTAlignmentParserTests {
    // MARK: Internal

    @Test("Parses markers into stripped translation text and accurate UTF-16 target ranges", .tags(.utilities, .unit))
    func testParseBasicAndReorderedMarkers() {
        let sourceText = "Among patients with acute hemorrhage who received treatment"
        let sourceChunks = [
            QTSourceChunk(id: 1, range: NSRange(location: 0, length: 14)),
            QTSourceChunk(id: 2, range: NSRange(location: 15, length: 21)),
            QTSourceChunk(id: 3, range: NSRange(location: 37, length: 22)),
        ]
        let rawTranslation = "[[2]]急性出血があり[[3]]治療を受けた[[1]]患者のうち"

        let alignment = QTAlignmentParser.parse(
            rawTranslation: rawTranslation,
            sourceText: sourceText,
            sourceChunks: sourceChunks
        )

        #expect(alignment != nil)
        guard let alignment else { return }

        #expect(alignment.sourceText == sourceText)
        #expect(alignment.translationText == "急性出血があり治療を受けた患者のうち")
        #expect(alignment.translationText == QTAlignmentParser.stripMarkers(from: rawTranslation))
        #expect(alignment.chunks.count == 3)

        let nsTranslation = alignment.translationText as NSString
        #expect(alignment.chunks[0].id == 1)
        #expect(alignment.chunks[0].targetRanges.map(nsTranslation.substring(with:)) == ["患者のうち"])

        #expect(alignment.chunks[1].id == 2)
        #expect(alignment.chunks[1].targetRanges.map(nsTranslation.substring(with:)) == ["急性出血があり"])

        #expect(alignment.chunks[2].id == 3)
        #expect(alignment.chunks[2].targetRanges.map(nsTranslation.substring(with:)) == ["治療を受けた"])
    }

    @Test("Supports repeated marker IDs for discontinuous Japanese ranges and trims segment whitespace", .tags(.utilities, .unit))
    func testRepeatedMarkersAndTrimmedTargetRanges() {
        let sourceText = "Do not open the door if it rains"
        let sourceChunks = [
            QTSourceChunk(id: 1, range: NSRange(location: 0, length: 20)),
            QTSourceChunk(id: 2, range: NSRange(location: 21, length: 11)),
        ]
        let rawTranslation = "  [[1]] ドアを [[2]] 雨が降ったら [[1]] 開けないでください  "

        let alignment = QTAlignmentParser.parse(
            rawTranslation: rawTranslation,
            sourceText: sourceText,
            sourceChunks: sourceChunks
        )

        #expect(alignment != nil)
        guard let alignment else { return }

        #expect(alignment.translationText == QTAlignmentParser.stripMarkers(from: rawTranslation))
        let nsTranslation = alignment.translationText as NSString

        #expect(alignment.chunks[0].targetRanges.map(nsTranslation.substring(with:)) == ["ドアを", "開けないでください"])
        #expect(alignment.chunks[1].targetRanges.map(nsTranslation.substring(with:)) == ["雨が降ったら"])
    }

    @Test("Ignores unknown marker numbers and returns nil when only unknown or no markers exist", .tags(.utilities, .unit))
    func testUnknownAndMissingMarkers() {
        let sourceText = "Hello world"
        let sourceChunks = [
            QTSourceChunk(id: 1, range: NSRange(location: 0, length: 11)),
        ]

        let mixedAlignment = QTAlignmentParser.parse(
            rawTranslation: "[[1]]こんにちは[[99]]世界",
            sourceText: sourceText,
            sourceChunks: sourceChunks
        )
        #expect(mixedAlignment != nil)
        if let mixedAlignment {
            #expect(mixedAlignment.translationText == "こんにちは世界")
            let nsTranslation = mixedAlignment.translationText as NSString
            #expect(mixedAlignment.chunks[0].targetRanges.map(nsTranslation.substring(with:)) == ["こんにちは"])
        }

        let onlyUnknown = QTAlignmentParser.parse(
            rawTranslation: "[[99]]こんにちは世界",
            sourceText: sourceText,
            sourceChunks: sourceChunks
        )
        #expect(onlyUnknown == nil)

        let noMarkers = QTAlignmentParser.parse(
            rawTranslation: "こんにちは世界",
            sourceText: sourceText,
            sourceChunks: sourceChunks
        )
        #expect(noMarkers == nil)
    }

    @Test("Strips complete markers and hides incomplete trailing markers during streaming", .tags(.utilities, .unit))
    func testStripMarkersDuringStreaming() {
        #expect(QTAlignmentParser.stripMarkers(from: "[") == "")
        #expect(QTAlignmentParser.stripMarkers(from: "[[") == "")
        #expect(QTAlignmentParser.stripMarkers(from: "[[1") == "")
        #expect(QTAlignmentParser.stripMarkers(from: "[[12]") == "")
        #expect(QTAlignmentParser.stripMarkers(from: "[[1]]こんにちは[") == "こんにちは")
        #expect(QTAlignmentParser.stripMarkers(from: "[[1]]こんにちは[[") == "こんにちは")
        #expect(QTAlignmentParser.stripMarkers(from: "[[1]]こんにちは[[2") == "こんにちは")
        #expect(QTAlignmentParser.stripMarkers(from: "[[1]]こんにちは[[12") == "こんにちは")
        #expect(QTAlignmentParser.stripMarkers(from: "[[1]]こんにちは[[12]") == "こんにちは")
        #expect(QTAlignmentParser.stripMarkers(from: "[[1]]こんにちは[[12]]世界") == "こんにちは世界")
    }

    @Test("Applies alignment to StreamService results and validates AppleIntelligenceService helpers", .tags(.utilities, .unit))
    func testApplyAlignmentAndAppleIntelligenceHelpers() {
        let service = AppleIntelligenceService()
        #expect(service.serviceType() == .appleIntelligence)
        #expect(service.apiKeyRequirement() == .none)
        #expect(service.iconName() == ServiceType.apple.rawValue)
        #expect(QueryServiceFactory.shared.service(withTypeId: ServiceType.appleIntelligence.rawValue) is AppleIntelligenceService)

        #expect(AppleIntelligenceService.delta(from: "", to: "[[1]]こんにちは") == "[[1]]こんにちは")
        #expect(AppleIntelligenceService.delta(from: "[[1]]こんにちは", to: "[[1]]こんにちは[[2]]世界") == "[[2]]世界")
        #expect(AppleIntelligenceService.delta(from: "[[1]]こんにちは", to: "[[1]]こんにちは") == "")

        #expect(throws: Never.self) {
            try AppleIntelligenceService.validateSourceLength(String(repeating: "a", count: 1500))
        }
        #expect(throws: QueryError.self) {
            try AppleIntelligenceService.validateSourceLength(String(repeating: "a", count: 1501))
        }

        _ = service.resetServiceResult()
        let sourceText = "Hello world"
        let chunks = [QTSourceChunk(id: 1, range: NSRange(location: 0, length: 11))]
        QTAlignmentParser.applyAlignment(
            to: service,
            rawText: "[[1]]こんにちは世界",
            sourceText: sourceText,
            sourceChunks: chunks
        )
        #expect(service.result?.alignment?.translationText == "こんにちは世界")

        QTAlignmentParser.applyAlignment(
            to: service,
            rawText: "こんにちは世界",
            sourceText: sourceText,
            sourceChunks: chunks
        )
        #expect(service.result?.alignment == nil)
    }
}
