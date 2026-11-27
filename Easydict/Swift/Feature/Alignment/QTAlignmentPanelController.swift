//
//  QTAlignmentPanelController.swift
//  Easydict
//
//  Created by QuickTranslate on 2026/11/27.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Foundation

// MARK: - QTAlignmentPanelController

/// Manages the floating panel that displays phrase-level alignment between English source text
/// and its Japanese translation. Keeps all text strictly in memory and clears it when closed.
@objcMembers
final class QTAlignmentPanelController: NSObject, NSWindowDelegate, NSTextViewDelegate {
    // MARK: Lifecycle

    private override init() {
        super.init()
    }

    // MARK: Internal

    static let shared = QTAlignmentPanelController()

    @objc(showWithAlignment:)
    func show(alignment: QTAlignment) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.show(alignment: alignment)
            }
            return
        }

        let panel = ensurePanel()
        currentAlignment = alignment
        hoveredChunkID = nil

        applySourceText(from: alignment)
        applyTranslationText(from: alignment)

        isUpdatingSelection = true
        sourceTextView?.setSelectedRange(NSRange(location: 0, length: 0))
        translationTextView?.setSelectedRange(NSRange(location: 0, length: 0))
        isUpdatingSelection = false

        clearAllTemporaryHighlights()
        sourceTextView?.scrollRangeToVisible(NSRange(location: 0, length: 0))
        translationTextView?.scrollRangeToVisible(NSRange(location: 0, length: 0))

        if !panel.isVisible {
            positionPanel(panel)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func closePanel() {
        panel?.close()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        _ = notification
        clearContent()
    }

    // MARK: - NSTextViewDelegate

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isUpdatingSelection else { return }
        guard let changedTextView = notification.object as? NSTextView else { return }

        if changedTextView === sourceTextView, changedTextView.selectedRange().length > 0 {
            isUpdatingSelection = true
            translationTextView?.setSelectedRange(NSRange(location: 0, length: 0))
            isUpdatingSelection = false
        } else if changedTextView === translationTextView, changedTextView.selectedRange().length > 0 {
            isUpdatingSelection = true
            sourceTextView?.setSelectedRange(NSRange(location: 0, length: 0))
            isUpdatingSelection = false
        }

        refreshHighlights()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        _ = textView
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            panel?.close()
            return true
        }
        return false
    }

    // MARK: Private

    private static let highlightPalette: [NSColor] = [
        NSColor.systemYellow.withAlphaComponent(0.35),
        NSColor.systemBlue.withAlphaComponent(0.35),
        NSColor.systemGreen.withAlphaComponent(0.35),
        NSColor.systemPink.withAlphaComponent(0.35),
        NSColor.systemOrange.withAlphaComponent(0.35),
        NSColor.systemPurple.withAlphaComponent(0.35),
        NSColor.systemTeal.withAlphaComponent(0.35),
    ]

    private var panel: QTAlignmentPanel?
    private var sourceTextView: QTAlignmentTextView?
    private var translationTextView: QTAlignmentTextView?
    private var currentAlignment: QTAlignment?
    private var hoveredChunkID: Int?
    private var isUpdatingSelection = false

    private func ensurePanel() -> QTAlignmentPanel {
        if let panel {
            return panel
        }

        let createdPanel = QTAlignmentPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        createdPanel.title = String(localized: "quick_translate.alignment.panel.title")
        createdPanel.level = .floating
        createdPanel.isFloatingPanel = true
        createdPanel.becomesKeyOnlyIfNeeded = false
        createdPanel.hidesOnDeactivate = false
        createdPanel.isReleasedWhenClosed = false
        createdPanel.minSize = NSSize(width: 360, height: 280)
        createdPanel.delegate = self

        let splitView = NSSplitView()
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]

        let (sourcePane, srcTextView) = makePane(
            title: String(localized: "quick_translate.alignment.source_label"),
            snapsSelectionToWord: true
        )
        let (translationPane, dstTextView) = makePane(
            title: String(localized: "quick_translate.alignment.translation_label"),
            snapsSelectionToWord: false
        )

        srcTextView.delegate = self
        dstTextView.delegate = self

        srcTextView.onHoverCharacterIndexChanged = { [weak self] charIndex in
            self?.handleHoverInSource(characterIndex: charIndex)
        }
        dstTextView.onHoverCharacterIndexChanged = { [weak self] charIndex in
            self?.handleHoverInTranslation(characterIndex: charIndex)
        }

        splitView.addArrangedSubview(sourcePane)
        splitView.addArrangedSubview(translationPane)

        createdPanel.contentView = splitView
        splitView.adjustSubviews()

        panel = createdPanel
        sourceTextView = srcTextView
        translationTextView = dstTextView
        return createdPanel
    }

    private func makePane(
        title: String,
        snapsSelectionToWord: Bool
    )
        -> (NSView, QTAlignmentTextView) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(
            containerSize: NSSize(width: 520, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = QTAlignmentTextView(
            frame: NSRect(x: 0, y: 0, width: 520, height: 180),
            textContainer: textContainer
        )
        textView.snapsSelectionToWord = snapsSelectionToWord
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        // Use temporary background attributes instead of the default opaque selection fill
        // so phrase palette colors remain visible while dragging.
        textView.selectedTextAttributes = [:]

        scrollView.documentView = textView

        container.addSubview(label)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            container.heightAnchor.constraint(greaterThanOrEqualToConstant: 110),
        ])

        return (container, textView)
    }

    private func positionPanel(_ panel: NSPanel) {
        if let floatingWindow = EZWindowManager.shared().floatingWindow,
           floatingWindow.isVisible {
            let floatingFrame = floatingWindow.frame
            let screenFrame = (floatingWindow.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            var originX = floatingFrame.maxX + 12
            if originX + panel.frame.width > screenFrame.maxX {
                originX = max(screenFrame.minX + 12, floatingFrame.minX - panel.frame.width - 12)
            }
            let originY = min(
                max(screenFrame.minY + 12, floatingFrame.maxY - panel.frame.height),
                screenFrame.maxY - panel.frame.height - 12
            )
            panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        } else {
            panel.center()
        }
    }

    private func applySourceText(from alignment: QTAlignment) {
        guard let sourceTextView, let textStorage = sourceTextView.textStorage else { return }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]

        let attributed = NSMutableAttributedString(string: alignment.sourceText, attributes: baseAttributes)
        let fullLength = (alignment.sourceText as NSString).length
        let underlineStyle = NSUnderlineStyle([.single, .patternDot]).rawValue
        let strongUnderlineColor = NSColor.labelColor.withAlphaComponent(0.50)
        let softUnderlineColor = NSColor.labelColor.withAlphaComponent(0.24)

        for (index, chunk) in alignment.chunks.enumerated() {
            guard chunk.sourceRange.location >= 0,
                  NSMaxRange(chunk.sourceRange) <= fullLength,
                  chunk.sourceRange.length > 0
            else {
                continue
            }
            let color = (index % 2 == 0) ? strongUnderlineColor : softUnderlineColor
            attributed.addAttributes(
                [
                    .underlineStyle: underlineStyle,
                    .underlineColor: color,
                ],
                range: chunk.sourceRange
            )
        }

        textStorage.setAttributedString(attributed)
    }

    private func applyTranslationText(from alignment: QTAlignment) {
        guard let translationTextView, let textStorage = translationTextView.textStorage else { return }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]

        let attributed = NSAttributedString(string: alignment.translationText, attributes: baseAttributes)
        textStorage.setAttributedString(attributed)
    }

    private func handleHoverInSource(characterIndex: Int?) {
        guard let alignment = currentAlignment else { return }
        let newChunkID: Int?
        if let characterIndex {
            newChunkID = alignment.chunks.first {
                NSLocationInRange(characterIndex, $0.sourceRange)
            }?.id
        } else {
            newChunkID = nil
        }

        if hoveredChunkID != newChunkID {
            hoveredChunkID = newChunkID
            refreshHighlights()
        }
    }

    private func handleHoverInTranslation(characterIndex: Int?) {
        guard let alignment = currentAlignment else { return }
        let newChunkID: Int?
        if let characterIndex {
            newChunkID = alignment.chunks.first { chunk in
                chunk.targetRanges.contains { NSLocationInRange(characterIndex, $0) }
            }?.id
        } else {
            newChunkID = nil
        }

        if hoveredChunkID != newChunkID {
            hoveredChunkID = newChunkID
            refreshHighlights()
        }
    }

    private func refreshHighlights() {
        clearAllTemporaryHighlights()
        guard let alignment = currentAlignment else { return }

        let sourceSelection = sourceTextView?.selectedRange() ?? NSRange(location: 0, length: 0)
        let translationSelection = translationTextView?.selectedRange() ?? NSRange(location: 0, length: 0)

        var activeChunks: [QTAlignedChunk] = []

        if sourceSelection.length > 0 {
            activeChunks = alignment.chunks.filter {
                NSIntersectionRange($0.sourceRange, sourceSelection).length > 0
            }
        } else if translationSelection.length > 0 {
            activeChunks = alignment.chunks.filter { chunk in
                chunk.targetRanges.contains {
                    NSIntersectionRange($0, translationSelection).length > 0
                }
            }
        } else if let hoveredChunkID,
                  let hoveredChunk = alignment.chunks.first(where: { $0.id == hoveredChunkID }) {
            activeChunks = [hoveredChunk]
        }

        guard !activeChunks.isEmpty else { return }

        let sourceLength = (alignment.sourceText as NSString).length
        let translationLength = (alignment.translationText as NSString).length
        let sourceLM = sourceTextView?.layoutManager
        let translationLM = translationTextView?.layoutManager

        for (index, chunk) in activeChunks.enumerated() {
            let color = Self.highlightPalette[index % Self.highlightPalette.count]

            if chunk.sourceRange.location >= 0,
               NSMaxRange(chunk.sourceRange) <= sourceLength,
               chunk.sourceRange.length > 0 {
                sourceLM?.addTemporaryAttribute(
                    .backgroundColor,
                    value: color,
                    forCharacterRange: chunk.sourceRange
                )
            }

            for targetRange in chunk.targetRanges {
                if targetRange.location >= 0,
                   NSMaxRange(targetRange) <= translationLength,
                   targetRange.length > 0 {
                    translationLM?.addTemporaryAttribute(
                        .backgroundColor,
                        value: color,
                        forCharacterRange: targetRange
                    )
                }
            }
        }
    }

    private func clearAllTemporaryHighlights() {
        if let sourceTextView,
           let layoutManager = sourceTextView.layoutManager,
           let textStorage = sourceTextView.textStorage,
           textStorage.length > 0 {
            layoutManager.removeTemporaryAttribute(
                .backgroundColor,
                forCharacterRange: NSRange(location: 0, length: textStorage.length)
            )
        }

        if let translationTextView,
           let layoutManager = translationTextView.layoutManager,
           let textStorage = translationTextView.textStorage,
           textStorage.length > 0 {
            layoutManager.removeTemporaryAttribute(
                .backgroundColor,
                forCharacterRange: NSRange(location: 0, length: textStorage.length)
            )
        }
    }

    private func clearContent() {
        clearAllTemporaryHighlights()
        isUpdatingSelection = true
        sourceTextView?.setSelectedRange(NSRange(location: 0, length: 0))
        translationTextView?.setSelectedRange(NSRange(location: 0, length: 0))
        sourceTextView?.textStorage?.setAttributedString(NSAttributedString())
        translationTextView?.textStorage?.setAttributedString(NSAttributedString())
        isUpdatingSelection = false
        hoveredChunkID = nil
        currentAlignment = nil
    }
}

// MARK: - QTAlignmentPanel

private final class QTAlignmentPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        _ = sender
        close()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            close()
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            close()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - QTAlignmentTextView

private final class QTAlignmentTextView: NSTextView {
    // MARK: Internal

    var snapsSelectionToWord = false
    var onHoverCharacterIndexChanged: ((Int?) -> ())?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func selectionRange(
        forProposedRange proposedCharRange: NSRange,
        granularity: NSSelectionGranularity
    )
        -> NSRange {
        if snapsSelectionToWord, proposedCharRange.length > 0 {
            return super.selectionRange(forProposedRange: proposedCharRange, granularity: .selectByWord)
        }
        return super.selectionRange(forProposedRange: proposedCharRange, granularity: granularity)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let index = characterIndexAtMouseEvent(event)
        onHoverCharacterIndexChanged?(index)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHoverCharacterIndexChanged?(nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            window?.close()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: Private

    private var hoverTrackingArea: NSTrackingArea?

    private func characterIndexAtMouseEvent(_ event: NSEvent) -> Int? {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else {
            return nil
        }

        let viewPoint = convert(event.locationInWindow, from: nil)
        guard bounds.contains(viewPoint) else { return nil }

        let origin = textContainerOrigin
        let containerPoint = NSPoint(x: viewPoint.x - origin.x, y: viewPoint.y - origin.y)

        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        guard glyphIndex < layoutManager.numberOfGlyphs else {
            return nil
        }

        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        guard glyphRect.insetBy(dx: -2, dy: -2).contains(containerPoint) else {
            return nil
        }

        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < textStorage.length else {
            return nil
        }

        return charIndex
    }
}
