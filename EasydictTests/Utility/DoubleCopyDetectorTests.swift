//
//  DoubleCopyDetectorTests.swift
//  EasydictTests
//
//  Created by QuickTranslate on 2026/04/19.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Carbon
import CoreGraphics
import Foundation
import Testing

@testable import Easydict

// MARK: - DoubleCopyDetectorTests

@Suite("Double Copy Detector", .tags(.utilities, .unit))
struct DoubleCopyDetectorTests {
    // MARK: Internal

    @Test("Single Cmd+C does not trigger", .tags(.utilities, .unit))
    func testSingleCmdCDoesNotTrigger() {
        var detector = DoubleCopyDetector(interval: 0.6)

        let action = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: false,
            timestamp: 10.0,
            frontmostPID: 100,
            pasteboardChangeCount: 1
        )

        #expect(action == .none)
        #expect(detector.pendingState != nil)
    }

    @Test("Double Cmd+C within interval triggers with first changeCount", .tags(.utilities, .unit))
    func testDoubleCmdCWithinIntervalTriggers() {
        var detector = DoubleCopyDetector(interval: 0.6)

        let first = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: false,
            timestamp: 10.0,
            frontmostPID: 100,
            pasteboardChangeCount: 5
        )
        #expect(first == .none)

        let second = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: false,
            timestamp: 10.6,
            frontmostPID: 100,
            pasteboardChangeCount: 6
        )
        #expect(second == .triggered(firstChangeCount: 5))
        #expect(detector.pendingState == nil)
    }

    @Test("Double Cmd+C exceeding interval treats second press as new first press", .tags(.utilities, .unit))
    func testDoubleCmdCExceedingIntervalDoesNotTrigger() {
        var detector = DoubleCopyDetector(interval: 0.6)

        let first = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: false,
            timestamp: 10.0,
            frontmostPID: 100,
            pasteboardChangeCount: 10
        )
        #expect(first == .none)

        let second = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: false,
            timestamp: 10.61,
            frontmostPID: 100,
            pasteboardChangeCount: 11
        )
        #expect(second == .none)
        #expect(detector.pendingState?.pasteboardChangeCount == 11)

        // A third press within 0.6s of the second press triggers using the second press's changeCount.
        let third = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: false,
            timestamp: 10.9,
            frontmostPID: 100,
            pasteboardChangeCount: 12
        )
        #expect(third == .triggered(firstChangeCount: 11))
    }

    @Test("Key repeat events are ignored without advancing or resetting state", .tags(.utilities, .unit))
    func testKeyRepeatIsIgnored() {
        var detector = DoubleCopyDetector(interval: 0.6)

        // Auto-repeat before any press does not arm detector.
        let initialRepeat = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: true,
            timestamp: 1.0,
            frontmostPID: 100,
            pasteboardChangeCount: 1
        )
        #expect(initialRepeat == .none)
        #expect(detector.pendingState == nil)

        // First real Cmd+C arms detector.
        let first = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: false,
            timestamp: 2.0,
            frontmostPID: 100,
            pasteboardChangeCount: 2
        )
        #expect(first == .none)

        // Auto-repeat of Cmd+C neither triggers nor resets.
        let repeatCmdC = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: true,
            timestamp: 2.1,
            frontmostPID: 100,
            pasteboardChangeCount: 3
        )
        #expect(repeatCmdC == .none)
        #expect(detector.pendingState?.pasteboardChangeCount == 2)

        // Auto-repeat of another key also does not reset.
        let repeatOtherKey = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_V),
            flags: .maskCommand,
            isAutoRepeat: true,
            timestamp: 2.2,
            frontmostPID: 100,
            pasteboardChangeCount: 3
        )
        #expect(repeatOtherKey == .none)
        #expect(detector.pendingState?.pasteboardChangeCount == 2)

        // Second real Cmd+C within interval triggers.
        let second = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: false,
            timestamp: 2.4,
            frontmostPID: 100,
            pasteboardChangeCount: 3
        )
        #expect(second == .triggered(firstChangeCount: 2))
    }

    @Test("Other key-down resets pending state", .tags(.utilities, .unit))
    func testOtherKeyResetsPendingState() {
        var detector = DoubleCopyDetector(interval: 0.6)

        _ = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: false,
            timestamp: 5.0,
            frontmostPID: 100,
            pasteboardChangeCount: 1
        )
        #expect(detector.pendingState != nil)

        let otherKey = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_V),
            flags: .maskCommand,
            isAutoRepeat: false,
            timestamp: 5.1,
            frontmostPID: 100,
            pasteboardChangeCount: 2
        )
        #expect(otherKey == .none)
        #expect(detector.pendingState == nil)

        let secondCmdC = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: false,
            timestamp: 5.2,
            frontmostPID: 100,
            pasteboardChangeCount: 2
        )
        #expect(secondCmdC == .none)
    }

    @Test("Application switch resets pending state", .tags(.utilities, .unit))
    func testApplicationChangeResetsPendingState() {
        var detector = DoubleCopyDetector(interval: 0.6)

        _ = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: false,
            timestamp: 5.0,
            frontmostPID: 100,
            pasteboardChangeCount: 1
        )
        #expect(detector.pendingState != nil)

        // Explicit workspace activation resets state.
        detector.handleApplicationActivated(pid: 200)
        #expect(detector.pendingState == nil)

        // PID mismatch directly in handleKeyDown also prevents trigger and arms new app.
        _ = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: false,
            timestamp: 6.0,
            frontmostPID: 200,
            pasteboardChangeCount: 2
        )
        let mismatchedSecond = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: false,
            timestamp: 6.2,
            frontmostPID: 300,
            pasteboardChangeCount: 3
        )
        #expect(mismatchedSecond == .none)
        #expect(detector.pendingState?.frontmostPID == 300)
    }

    @Test("Modifier mismatches such as Cmd+Shift+C do not trigger and reset pending state", .tags(.utilities, .unit))
    func testModifierMismatchIsRejectedAndResets() {
        var detector = DoubleCopyDetector(interval: 0.6)

        _ = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: false,
            timestamp: 1.0,
            frontmostPID: 100,
            pasteboardChangeCount: 1
        )

        let cmdShiftC = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: [.maskCommand, .maskShift],
            isAutoRepeat: false,
            timestamp: 1.2,
            frontmostPID: 100,
            pasteboardChangeCount: 2
        )
        #expect(cmdShiftC == .none)
        #expect(detector.pendingState == nil)

        let cmdOptionC = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: [.maskCommand, .maskAlternate],
            isAutoRepeat: false,
            timestamp: 1.3,
            frontmostPID: 100,
            pasteboardChangeCount: 2
        )
        #expect(cmdOptionC == .none)

        let cmdControlC = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: [.maskCommand, .maskControl],
            isAutoRepeat: false,
            timestamp: 1.4,
            frontmostPID: 100,
            pasteboardChangeCount: 2
        )
        #expect(cmdControlC == .none)

        let cmdFnC = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: [.maskCommand, .maskSecondaryFn],
            isAutoRepeat: false,
            timestamp: 1.5,
            frontmostPID: 100,
            pasteboardChangeCount: 2
        )
        #expect(cmdFnC == .none)

        // CapsLock alone with Command is allowed.
        let capsFirst = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: [.maskCommand, .maskAlphaShift],
            isAutoRepeat: false,
            timestamp: 2.0,
            frontmostPID: 100,
            pasteboardChangeCount: 4
        )
        #expect(capsFirst == .none)

        let capsSecond = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: [.maskCommand, .maskAlphaShift],
            isAutoRepeat: false,
            timestamp: 2.3,
            frontmostPID: 100,
            pasteboardChangeCount: 5
        )
        #expect(capsSecond == .triggered(firstChangeCount: 4))
    }

    @Test("Triple Cmd+C triggers only once and arms on the third press", .tags(.utilities, .unit))
    func testTripleCmdCTriggersOnce() {
        var detector = DoubleCopyDetector(interval: 0.6)

        let first = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: false,
            timestamp: 10.0,
            frontmostPID: 100,
            pasteboardChangeCount: 1
        )
        #expect(first == .none)

        let second = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: false,
            timestamp: 10.2,
            frontmostPID: 100,
            pasteboardChangeCount: 2
        )
        #expect(second == .triggered(firstChangeCount: 1))

        let third = detector.handleKeyDown(
            keyCode: CGKeyCode(kVK_ANSI_C),
            flags: .maskCommand,
            isAutoRepeat: false,
            timestamp: 10.35,
            frontmostPID: 100,
            pasteboardChangeCount: 3
        )
        #expect(third == .none)
        #expect(detector.pendingState?.pasteboardChangeCount == 3)
    }

    @Test("Pasteboard filter rejects file URLs, concealed/transient types, blank, and overly long text", .tags(.utilities, .unit))
    func testPasteboardFilterValidation() {
        #expect(
            DoubleCopyPasteboardFilter.validate(
                types: [.string, .fileURL],
                rawString: "document.pdf"
            ) == .ignored
        )

        #expect(
            DoubleCopyPasteboardFilter.validate(
                types: [.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")],
                rawString: "secret-password"
            ) == .ignored
        )

        #expect(
            DoubleCopyPasteboardFilter.validate(
                types: [.string, NSPasteboard.PasteboardType("org.nspasteboard.TransientType")],
                rawString: "temp"
            ) == .ignored
        )

        #expect(
            DoubleCopyPasteboardFilter.validate(
                types: [.string],
                rawString: "   \n\t  "
            ) == .ignored
        )

        let tooLong = String(repeating: "a", count: DoubleCopyPasteboardFilter.maxTextLength + 1)
        #expect(
            DoubleCopyPasteboardFilter.validate(
                types: [.string],
                rawString: tooLong
            ) == .tooLong(DoubleCopyPasteboardFilter.maxTextLength + 1)
        )

        #expect(
            DoubleCopyPasteboardFilter.validate(
                types: [.string],
                rawString: "  Hello world  "
            ) == .valid("Hello world")
        )
    }
}
