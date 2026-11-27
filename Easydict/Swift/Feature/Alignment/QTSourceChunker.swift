//
//  QTSourceChunker.swift
//  Easydict
//
//  Created by QuickTranslate on 2026/11/27.
//  Copyright © 2026 izual. All rights reserved.
//

import Foundation
import NaturalLanguage

// MARK: - QTSourceChunk

/// A numbered phrase chunk in the English source text.
struct QTSourceChunk: Equatable, Sendable {
    /// 1-based sequential identifier.
    let id: Int
    /// UTF-16 range in the original source string, excluding leading and trailing whitespace.
    let range: NSRange
}

// MARK: - QTAlignedChunk

/// Pairs a source phrase range with one or more corresponding ranges in the cleaned translation.
struct QTAlignedChunk: Equatable, Sendable {
    let id: Int
    let sourceRange: NSRange
    let targetRanges: [NSRange]
}

// MARK: - QTAlignment

/// Holds the source text, cleaned translation text, and phrase-level alignment mappings in memory.
@objcMembers
final class QTAlignment: NSObject {
    // MARK: Lifecycle

    @nonobjc
    init(sourceText: String, translationText: String, chunks: [QTAlignedChunk]) {
        self.sourceText = sourceText
        self.translationText = translationText
        self.chunks = chunks
        super.init()
    }

    // MARK: Internal

    let sourceText: String
    let translationText: String
    @nonobjc let chunks: [QTAlignedChunk]
}

// MARK: - QTSourceChunker

/// Mechanical phrase chunker for English source text using NaturalLanguage without consuming tokens.
enum QTSourceChunker {
    // MARK: Internal

    static let maxChunkCount = 80
    static let maxCharacterCount = 3000
    static let maxWordsPerChunk = 7
    static let fallbackSplitWordCount = 6

    /// Splits English source text into numbered phrase chunks, or returns `nil` if alignment
    /// should not be used (e.g. text too long, too many chunks, non-Latin text, or bracket collision).
    static func chunk(_ text: String) -> [QTSourceChunk]? {
        guard !text.isEmpty, text.count <= maxCharacterCount else {
            return nil
        }

        if text.contains("[[") || text.contains("]]") {
            return nil
        }

        guard hasSufficientLatinCharacters(in: text) else {
            return nil
        }

        let fullRange = text.startIndex ..< text.endIndex
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        tokenizer.setLanguage(.english)

        var wordRanges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: fullRange) { range, _ in
            wordRanges.append(range)
            return true
        }

        guard !wordRanges.isEmpty else {
            return nil
        }

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        tagger.setLanguage(.english, range: fullRange)

        var tokens: [WordToken] = []
        tokens.reserveCapacity(wordRanges.count)

        for (index, range) in wordRanges.enumerated() {
            let lower = text[range].lowercased()
            let (tag, _) = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lexicalClass)
            let gapBefore: Substring = index > 0
                ? text[wordRanges[index - 1].upperBound ..< range.lowerBound]
                : text[text.startIndex ..< range.lowerBound]
            let hasWhitespaceBefore = index == 0 || gapBefore.contains { $0.isWhitespace || $0.isNewline }
            let hasPunctuationOrNewlineBreakBefore = index > 0 && isBoundaryGap(gapBefore, hasWhitespace: hasWhitespaceBefore)

            tokens.append(
                WordToken(
                    range: range,
                    lowercased: lower,
                    lexicalTag: tag,
                    hasWhitespaceBefore: hasWhitespaceBefore,
                    hasPunctuationOrNewlineBreakBefore: hasPunctuationOrNewlineBreakBefore
                )
            )
        }

        // Step 1: Initial splitting by punctuation/newlines and phrase-introducing words.
        var groups: [WordGroup] = []
        var currentStart = 0

        for index in 1 ..< tokens.count {
            let token = tokens[index]
            let shouldSplit = token.hasPunctuationOrNewlineBreakBefore
                || (token.hasWhitespaceBefore && isPhraseStarter(token))
            if shouldSplit {
                groups.append(WordGroup(startWord: currentStart, endWord: index))
                currentStart = index
            }
        }
        groups.append(WordGroup(startWord: currentStart, endWord: tokens.count))

        // Step 2: Merge single-word chunks with a neighbor (sentence-final 1-word chunks merge backward).
        groups = mergeSingleWordGroups(groups, tokens: tokens)

        // Step 3: Split chunks exceeding 7 words (before determiners/verbs, or every 6 words).
        groups = splitLongGroups(groups, tokens: tokens)

        // Step 4: Convert word groups to non-overlapping UTF-16 NSRanges without leading/trailing whitespace.
        let chunks = buildSourceChunks(from: groups, tokens: tokens, in: text)

        guard !chunks.isEmpty, chunks.count <= maxChunkCount else {
            return nil
        }

        return chunks
    }

    /// Inserts `[[id]]` at the start of each chunk while preserving all intermediate whitespace and newlines.
    static func annotate(_ text: String, chunks: [QTSourceChunk]) -> String {
        guard !chunks.isEmpty else { return text }

        let nsText = text as NSString
        let length = nsText.length
        let output = NSMutableString(capacity: length + chunks.count * 6)
        var cursor = 0

        for chunk in chunks {
            let start = chunk.range.location
            let end = NSMaxRange(chunk.range)
            guard start >= cursor, end <= length else { continue }

            if start > cursor {
                output.append(nsText.substring(with: NSRange(location: cursor, length: start - cursor)))
            }
            output.append("[[\(chunk.id)]]")
            output.append(nsText.substring(with: chunk.range))
            cursor = end
        }

        if cursor < length {
            output.append(nsText.substring(with: NSRange(location: cursor, length: length - cursor)))
        }

        return output as String
    }

    // MARK: Private

    private struct WordToken {
        let range: Range<String.Index>
        let lowercased: String
        let lexicalTag: NLTag?
        let hasWhitespaceBefore: Bool
        let hasPunctuationOrNewlineBreakBefore: Bool
    }

    private struct WordGroup {
        var startWord: Int
        var endWord: Int

        var wordCount: Int { endWord - startWord }
    }

    private static let relativeWords: Set<String> = [
        "who", "which", "that", "whom", "whose", "where", "when",
    ]

    private static let prepositions: Set<String> = [
        "about", "above", "across", "after", "against", "along", "among", "around",
        "at", "before", "behind", "below", "beneath", "beside", "between", "beyond",
        "by", "despite", "down", "during", "except", "for", "from", "in", "inside",
        "into", "near", "of", "off", "on", "onto", "over", "per", "since", "through",
        "throughout", "till", "toward", "towards", "under", "until", "up", "upon",
        "via", "with", "within", "without",
    ]

    private static let conjunctions: Set<String> = [
        "although", "and", "as", "because", "but", "if", "nor", "once", "or",
        "since", "so", "than", "though", "unless", "until", "whereas", "whether",
        "while", "yet",
    ]

    private static let determiners: Set<String> = [
        "a", "all", "an", "another", "any", "both", "each", "either", "every",
        "few", "her", "his", "its", "many", "my", "neither", "no", "our",
        "several", "some", "that", "the", "their", "these", "this", "those", "your",
    ]

    private static let commonVerbs: Set<String> = [
        "am", "are", "be", "been", "being", "can", "could", "did", "do", "does",
        "had", "has", "have", "is", "may", "might", "must", "shall", "should",
        "was", "were", "will", "would",
    ]

    private static let unconditionalBreakCharacters: Set<Character> = [
        ",", ";", "(", ")", "[", "]", "{", "}", "\"", "“", "”", "—", "–", "…",
        "、", "。", "（", "）", "「", "」",
    ]

    private static let whitespaceDependentBreakCharacters: Set<Character> = [
        ".", "!", "?", ":", "/",
    ]

    private static let openingAttachablePunctuation: Set<Character> = [
        "(", "[", "{", "\"", "'", "“", "‘", "<", "«", "「", "『", "（", "$", "#", "@",
    ]

    private static func hasSufficientLatinCharacters(in text: String) -> Bool {
        var latinCount = 0
        var letterCount = 0
        var nonWhitespaceCount = 0

        for char in text {
            if !char.isWhitespace, !char.isNewline {
                nonWhitespaceCount += 1
            }
            if char.isLetter {
                letterCount += 1
                if char.unicodeScalars.contains(where: isLatinScalar) {
                    latinCount += 1
                }
            }
        }

        guard latinCount > 0, nonWhitespaceCount > 0 else {
            return false
        }

        let letterRatio = Double(latinCount) / Double(max(1, letterCount))
        let nonWhitespaceRatio = Double(latinCount) / Double(nonWhitespaceCount)
        return letterRatio >= 0.3 && nonWhitespaceRatio >= 0.15
    }

    private static func isLatinScalar(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return (0x0041 ... 0x005A).contains(value)
            || (0x0061 ... 0x007A).contains(value)
            || (0x00C0 ... 0x024F).contains(value)
            || (0x1E00 ... 0x1EFF).contains(value)
    }

    private static func isBoundaryGap(_ gap: Substring, hasWhitespace: Bool) -> Bool {
        if gap.contains(where: { $0.isNewline }) {
            return true
        }
        if gap.contains(where: { unconditionalBreakCharacters.contains($0) }) {
            return true
        }
        if hasWhitespace, gap.contains(where: { whitespaceDependentBreakCharacters.contains($0) }) {
            return true
        }
        return false
    }

    private static func isPhraseStarter(_ token: WordToken) -> Bool {
        if token.lowercased == "to" || relativeWords.contains(token.lowercased) {
            return true
        }
        if token.lexicalTag == .preposition || prepositions.contains(token.lowercased) {
            return true
        }
        if token.lexicalTag == .conjunction || conjunctions.contains(token.lowercased) {
            return true
        }
        return false
    }

    private static func isMidSplitCandidate(_ token: WordToken) -> Bool {
        if token.lexicalTag == .determiner || determiners.contains(token.lowercased) {
            return true
        }
        if token.lexicalTag == .verb || commonVerbs.contains(token.lowercased) {
            return true
        }
        return false
    }

    private static func mergeSingleWordGroups(
        _ initialGroups: [WordGroup],
        tokens: [WordToken]
    )
        -> [WordGroup] {
        var groups = initialGroups
        guard groups.count > 1 else { return groups }

        var index = 0
        while index < groups.count, groups.count > 1 {
            guard groups[index].wordCount == 1 else {
                index += 1
                continue
            }

            let isLastGroup = (index == groups.count - 1)
            let nextWordIndex = groups[index].endWord
            let hasBreakAfter = isLastGroup || (
                nextWordIndex < tokens.count && tokens[nextWordIndex].hasPunctuationOrNewlineBreakBefore
            )

            if isLastGroup || (hasBreakAfter && index > 0) {
                // Merge backward into the preceding group.
                groups[index - 1].endWord = groups[index].endWord
                groups.remove(at: index)
                index = max(0, index - 1)
            } else {
                // Merge forward into the following group.
                groups[index + 1].startWord = groups[index].startWord
                groups.remove(at: index)
            }
        }

        return groups
    }

    private static func splitLongGroups(
        _ groups: [WordGroup],
        tokens: [WordToken]
    )
        -> [WordGroup] {
        var result: [WordGroup] = []
        result.reserveCapacity(groups.count)

        for group in groups {
            if group.wordCount <= maxWordsPerChunk {
                result.append(group)
                continue
            }

            var currentStart = group.startWord
            let endWord = group.endWord

            while endWord - currentStart > maxWordsPerChunk {
                let remaining = endWord - currentStart
                // Ensure both the split chunk and the remaining words have at least 2 words.
                let maxOffset = min(maxWordsPerChunk, remaining - 2)
                var chosenOffset: Int?

                if maxOffset >= 2 {
                    // Prefer a determiner or verb near the middle of the chunk (around offset 3..6).
                    let preferredOffsets = [4, 5, 3, 6, 2, 7].filter { $0 >= 2 && $0 <= maxOffset }
                    for offset in preferredOffsets {
                        let token = tokens[currentStart + offset]
                        if token.hasWhitespaceBefore, isMidSplitCandidate(token) {
                            chosenOffset = offset
                            break
                        }
                    }
                }

                let splitOffset = chosenOffset ?? min(fallbackSplitWordCount, max(2, maxOffset))
                result.append(WordGroup(startWord: currentStart, endWord: currentStart + splitOffset))
                currentStart += splitOffset
            }

            if currentStart < endWord {
                result.append(WordGroup(startWord: currentStart, endWord: endWord))
            }
        }

        return result
    }

    private static func buildSourceChunks(
        from groups: [WordGroup],
        tokens: [WordToken],
        in text: String
    )
        -> [QTSourceChunk] {
        guard !groups.isEmpty else { return [] }

        // Compute leading start index for each group, attaching adjacent opening punctuation.
        var groupStarts: [String.Index] = []
        groupStarts.reserveCapacity(groups.count)

        for (groupIndex, group) in groups.enumerated() {
            let firstToken = tokens[group.startWord]
            var start = firstToken.range.lowerBound

            if groupIndex == 0 {
                // Include any leading non-whitespace characters before the first word.
                if let firstNonWS = text[text.startIndex ..< start].firstIndex(where: { !$0.isWhitespace && !$0.isNewline }) {
                    start = firstNonWS
                }
            } else if firstToken.hasWhitespaceBefore {
                let prevLastWordEnd = tokens[groups[groupIndex - 1].endWord - 1].range.upperBound
                var cursor = start
                while cursor > prevLastWordEnd {
                    let prevIndex = text.index(before: cursor)
                    let ch = text[prevIndex]
                    if !ch.isWhitespace, !ch.isNewline, openingAttachablePunctuation.contains(ch) {
                        cursor = prevIndex
                    } else {
                        break
                    }
                }
                start = cursor
            }

            groupStarts.append(start)
        }

        var chunks: [QTSourceChunk] = []
        chunks.reserveCapacity(groups.count)

        for (groupIndex, group) in groups.enumerated() {
            let start = groupStarts[groupIndex]
            let lastWordEnd = tokens[group.endWord - 1].range.upperBound
            let upperBound = (groupIndex + 1 < groups.count) ? groupStarts[groupIndex + 1] : text.endIndex

            var end = max(lastWordEnd, start)
            if upperBound > end {
                let trailingSlice = text[end ..< upperBound]
                if let lastNonWS = trailingSlice.lastIndex(where: { !$0.isWhitespace && !$0.isNewline }) {
                    end = text.index(after: lastNonWS)
                }
            }

            // Trim any leading or trailing whitespace just in case.
            var trimmedStart = start
            while trimmedStart < end, text[trimmedStart].isWhitespace || text[trimmedStart].isNewline {
                trimmedStart = text.index(after: trimmedStart)
            }
            var trimmedEnd = end
            while trimmedEnd > trimmedStart {
                let prev = text.index(before: trimmedEnd)
                if text[prev].isWhitespace || text[prev].isNewline {
                    trimmedEnd = prev
                } else {
                    break
                }
            }

            guard trimmedStart < trimmedEnd else { continue }
            let nsRange = NSRange(trimmedStart ..< trimmedEnd, in: text)
            guard nsRange.length > 0 else { continue }

            chunks.append(QTSourceChunk(id: chunks.count + 1, range: nsRange))
        }

        return chunks
    }
}

// MARK: - QTAlignmentParser

/// Strips `[[id]]` markers during streaming and parses final marker positions into a `QTAlignment`.
enum QTAlignmentParser {
    // MARK: Internal

    /// Removes complete `[[id]]` markers and any trailing incomplete marker prefix (such as `[`, `[[`, `[[1`, `[[12]`),
    /// then trims outer whitespace and newlines to match `StreamService` result formatting.
    static func stripMarkers(from text: String) -> String {
        guard !text.isEmpty else { return "" }

        let withoutTrailingPartial = stripTrailingIncompleteMarker(from: text)
        let nsString = withoutTrailingPartial as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)
        let stripped = completeMarkerRegex.stringByReplacingMatches(
            in: withoutTrailingPartial,
            options: [],
            range: fullRange,
            withTemplate: ""
        )
        return stripped.trim()
    }

    /// Parses raw translation text containing `[[id]]` markers into a `QTAlignment`.
    /// Returns `nil` if `sourceChunks` is empty or if no known marker ID produces a non-empty target range.
    static func parse(
        rawTranslation: String,
        sourceText: String,
        sourceChunks: [QTSourceChunk]
    )
        -> QTAlignment? {
        guard !rawTranslation.isEmpty, !sourceChunks.isEmpty else {
            return nil
        }

        let input = stripTrailingIncompleteMarker(from: rawTranslation)
        let nsInput = input as NSString
        let fullRange = NSRange(location: 0, length: nsInput.length)
        let matches = completeMarkerRegex.matches(in: input, options: [], range: fullRange)

        guard !matches.isEmpty else {
            return nil
        }

        let validIDs = Set(sourceChunks.map(\.id))
        let cleanBuilder = NSMutableString(capacity: nsInput.length)
        var rawSegments: [(id: Int, rangeInClean: NSRange)] = []

        var cursor = 0
        var activeMarkerID: Int?
        var activeStartInClean = 0

        for match in matches {
            let matchRange = match.range
            if matchRange.location > cursor {
                let piece = nsInput.substring(with: NSRange(location: cursor, length: matchRange.location - cursor))
                cleanBuilder.append(piece)
            }

            if let currentID = activeMarkerID {
                let segLength = cleanBuilder.length - activeStartInClean
                if segLength > 0 {
                    rawSegments.append((id: currentID, rangeInClean: NSRange(location: activeStartInClean, length: segLength)))
                }
            }

            let digitsRange = match.range(at: 1)
            let idString = nsInput.substring(with: digitsRange)
            activeMarkerID = Int(idString)
            activeStartInClean = cleanBuilder.length
            cursor = NSMaxRange(matchRange)
        }

        if cursor < nsInput.length {
            let tail = nsInput.substring(with: NSRange(location: cursor, length: nsInput.length - cursor))
            cleanBuilder.append(tail)
        }

        if let currentID = activeMarkerID {
            let segLength = cleanBuilder.length - activeStartInClean
            if segLength > 0 {
                rawSegments.append((id: currentID, rangeInClean: NSRange(location: activeStartInClean, length: segLength)))
            }
        }

        let untrimmedClean = cleanBuilder as NSString
        let trimmedOuterRange = trimmedRange(of: NSRange(location: 0, length: untrimmedClean.length), in: untrimmedClean)
        guard trimmedOuterRange.length > 0 else {
            return nil
        }

        let translationText = untrimmedClean.substring(with: trimmedOuterRange)
        let outerTrimOffset = trimmedOuterRange.location

        var targetRangesByID: [Int: [NSRange]] = [:]
        var hasAnyValidTargetRange = false

        for segment in rawSegments {
            guard validIDs.contains(segment.id) else { continue }
            let trimmedSegment = trimmedRange(of: segment.rangeInClean, in: untrimmedClean)
            guard trimmedSegment.length > 0 else { continue }

            let shiftedLocation = trimmedSegment.location - outerTrimOffset
            guard shiftedLocation >= 0,
                  shiftedLocation + trimmedSegment.length <= trimmedOuterRange.length
            else {
                continue
            }

            let targetRange = NSRange(location: shiftedLocation, length: trimmedSegment.length)
            targetRangesByID[segment.id, default: []].append(targetRange)
            hasAnyValidTargetRange = true
        }

        guard hasAnyValidTargetRange else {
            return nil
        }

        let alignedChunks = sourceChunks.map { sourceChunk in
            QTAlignedChunk(
                id: sourceChunk.id,
                sourceRange: sourceChunk.range,
                targetRanges: targetRangesByID[sourceChunk.id] ?? []
            )
        }

        return QTAlignment(
            sourceText: sourceText,
            translationText: translationText,
            chunks: alignedChunks
        )
    }

    // MARK: Private

    private static let completeMarkerRegex = try! NSRegularExpression(pattern: #"\[\[([0-9]{1,3})\]\]"#)
    private static let trailingIncompleteMarkerRegex = try! NSRegularExpression(
        pattern: #"\[(?:\[(?:[0-9]{1,3}\]?)?)?$"#
    )

    private static func stripTrailingIncompleteMarker(from text: String) -> String {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let match = trailingIncompleteMarkerRegex.firstMatch(in: text, options: [], range: fullRange) else {
            return text
        }
        return nsText.substring(to: match.range.location)
    }

    private static func trimmedRange(of range: NSRange, in string: NSString) -> NSRange {
        guard range.length > 0 else { return NSRange(location: range.location, length: 0) }

        let whitespaceSet = CharacterSet.whitespacesAndNewlines
        var start = range.location
        var end = NSMaxRange(range)

        while start < end {
            let ch = string.character(at: start)
            if let scalar = Unicode.Scalar(ch), whitespaceSet.contains(scalar) {
                start += 1
            } else {
                break
            }
        }

        while end > start {
            let ch = string.character(at: end - 1)
            if let scalar = Unicode.Scalar(ch), whitespaceSet.contains(scalar) {
                end -= 1
            } else {
                break
            }
        }

        return NSRange(location: start, length: end - start)
    }
}
