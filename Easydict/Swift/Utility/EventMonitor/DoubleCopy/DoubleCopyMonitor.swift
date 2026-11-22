//
//  DoubleCopyMonitor.swift
//  Easydict
//
//  Created by QuickTranslate on 2026/04/19.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Carbon
import Combine
import CoreGraphics
import Defaults
import Foundation

// MARK: - Notification.Name

extension Notification.Name {
    static let doubleCopyMonitorStatusDidChange = Notification.Name("doubleCopyMonitorStatusDidChange")
}

// MARK: - DoubleCopyDetector

/// Pure state machine that detects pressing plain Cmd+C twice within a configured interval.
struct DoubleCopyDetector {
    // MARK: Lifecycle

    init(interval: TimeInterval = 0.6) {
        self.interval = interval
    }

    // MARK: Internal

    struct PendingState: Equatable {
        let timestamp: TimeInterval
        let frontmostPID: pid_t
        let pasteboardChangeCount: Int
    }

    enum Action: Equatable {
        case none
        case triggered(firstChangeCount: Int)
    }

    static let disallowedModifiers: CGEventFlags = [
        .maskShift,
        .maskAlternate,
        .maskControl,
        .maskSecondaryFn,
    ]

    var interval: TimeInterval

    private(set) var pendingState: PendingState?

    /// Returns `true` when the key-down represents plain Cmd+C (CapsLock ignored, no other modifiers).
    static func isPlainCmdC(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        keyCode == CGKeyCode(kVK_ANSI_C)
            && flags.contains(.maskCommand)
            && flags.isDisjoint(with: disallowedModifiers)
    }

    /// Processes a single key-down event and returns whether a double-Cmd+C trigger fired.
    mutating func handleKeyDown(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        isAutoRepeat: Bool,
        timestamp: TimeInterval,
        frontmostPID: pid_t,
        pasteboardChangeCount: Int
    )
        -> Action {
        if isAutoRepeat {
            return .none
        }

        guard Self.isPlainCmdC(keyCode: keyCode, flags: flags) else {
            pendingState = nil
            return .none
        }

        if let pending = pendingState {
            let elapsed = timestamp - pending.timestamp
            if pending.frontmostPID == frontmostPID, elapsed >= 0, elapsed <= interval {
                pendingState = nil
                return .triggered(firstChangeCount: pending.pasteboardChangeCount)
            }
        }

        pendingState = PendingState(
            timestamp: timestamp,
            frontmostPID: frontmostPID,
            pasteboardChangeCount: pasteboardChangeCount
        )
        return .none
    }

    /// Resets any pending first-press state when the active application changes.
    mutating func handleApplicationActivated(pid: pid_t) {
        _ = pid
        pendingState = nil
    }

    /// Explicitly clears pending state.
    mutating func reset() {
        pendingState = nil
    }
}

// MARK: - DoubleCopyPasteboardFilter

/// Validates clipboard types and text content for double-Cmd+C translation.
enum DoubleCopyPasteboardFilter {
    // MARK: Internal

    enum ValidationResult: Equatable {
        case valid(String)
        case ignored
        case tooLong(Int)
    }

    static let maxTextLength = 10_000

    static let excludedTypes: Set<NSPasteboard.PasteboardType> = [
        .fileURL,
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
    ]

    /// Filters pasteboard types and validates raw text content.
    static func validate(
        types: [NSPasteboard.PasteboardType],
        rawString: String?
    )
        -> ValidationResult {
        if types.contains(where: { excludedTypes.contains($0) }) {
            return .ignored
        }

        guard let rawString else {
            return .ignored
        }

        let trimmed = rawString.removeInvisibleChar().trim()
        guard !trimmed.isEmpty else {
            return .ignored
        }

        if trimmed.count > maxTextLength {
            return .tooLong(trimmed.count)
        }

        return .valid(trimmed)
    }

    /// Reads and validates plain string content from the general pasteboard.
    static func readFromGeneralPasteboard() -> ValidationResult {
        let pasteboard = NSPasteboard.general
        var allTypes = pasteboard.types ?? []
        if let items = pasteboard.pasteboardItems {
            for item in items {
                allTypes.append(contentsOf: item.types)
            }
        }
        let rawString = pasteboard.string(forType: .string)
        return validate(types: allTypes, rawString: rawString)
    }
}

// MARK: - PasteboardSelfWriteTracker

/// Tracks the pasteboard `changeCount` produced by the app's own copy operations
/// so double-Cmd+C does not recursively translate text copied from QuickTranslate.
@objcMembers
final class PasteboardSelfWriteTracker: NSObject {
    // MARK: Lifecycle

    private override init() {
        super.init()
    }

    // MARK: Internal

    static let shared = PasteboardSelfWriteTracker()

    /// Records the current `NSPasteboard.general.changeCount` as written by this app.
    func recordSelfWrite() {
        recordSelfWrite(changeCount: NSPasteboard.general.changeCount)
    }

    /// Records a specific pasteboard `changeCount` as written by this app.
    func recordSelfWrite(changeCount: Int) {
        lock.lock()
        lastSelfWriteChangeCount = changeCount
        lock.unlock()
    }

    /// Returns `true` if `changeCount` matches the last recorded self-write.
    func isSelfWrite(changeCount: Int) -> Bool {
        lock.lock()
        let matches = (lastSelfWriteChangeCount == changeCount)
        lock.unlock()
        return matches
    }

    /// Clears the recorded self-write change count.
    func reset() {
        lock.lock()
        lastSelfWriteChangeCount = nil
        lock.unlock()
    }

    // MARK: Private

    private let lock = NSLock()
    private var lastSelfWriteChangeCount: Int?
}

// MARK: - DoubleCopyMonitor

/// Monitors global Cmd+C double presses using a listen-only `CGEventTap`
/// and triggers plain-text translation in the mini floating window.
///
/// - Important: `start()` and `stop()` mutate CFRunLoop / tap state and always
///   dispatch onto the main thread.
@objcMembers
final class DoubleCopyMonitor: NSObject {
    // MARK: Lifecycle

    private override init() {
        self.detector = DoubleCopyDetector(interval: Self.clampedIntervalSeconds(fromMs: Defaults[.doubleCopyTranslateInterval]))
        super.init()
    }

    // MARK: Internal

    static let shared = DoubleCopyMonitor()

    static let minIntervalMs = 200
    static let maxIntervalMs = 1500
    static let defaultIntervalMs = 600

    /// Returns `true` when the listen-only event tap is currently installed and active.
    var isRunning: Bool {
        eventTap != nil
    }

    /// Returns `true` when Input Monitoring permission is granted.
    var hasInputMonitoringPermission: Bool {
        CGPreflightListenEventAccess()
    }

    /// Starts monitoring at app launch if enabled in user defaults, and begins observing settings.
    func startIfEnabled() {
        performOnMainThread {
            self.observeDefaultsIfNeeded()
            if Defaults[.enableDoubleCopyTranslate] {
                self.start(promptIfNeeded: true)
            } else {
                self.postStatusDidChange()
            }
        }
    }

    /// Starts monitoring double Cmd+C events, prompting for Input Monitoring permission if needed.
    func start() {
        start(promptIfNeeded: true)
    }

    /// Starts monitoring double Cmd+C events.
    func start(promptIfNeeded: Bool) {
        performOnMainThread {
            self.observeDefaultsIfNeeded()
            self.shouldBeRunning = true
            self.syncIntervalFromDefaults()

            if self.eventTap != nil {
                self.postStatusDidChange()
                return
            }

            self.installWorkspaceObserverIfNeeded()

            if CGPreflightListenEventAccess() {
                if !self.attemptInstallEventTap() {
                    self.scheduleRetryTimer()
                }
            } else {
                self.scheduleRetryTimer()
                if promptIfNeeded, !self.hasShownPermissionAlertThisSession {
                    self.hasShownPermissionAlertThisSession = true
                    DispatchQueue.main.async { [weak self] in
                        self?.presentPermissionAlert()
                    }
                }
            }

            self.postStatusDidChange()
        }
    }

    /// Explicitly shows the Input Monitoring explanation alert (if not yet granted) and resumes monitoring.
    func requestPermissionAndStart() {
        performOnMainThread {
            self.observeDefaultsIfNeeded()
            self.shouldBeRunning = true
            self.syncIntervalFromDefaults()
            self.installWorkspaceObserverIfNeeded()

            if CGPreflightListenEventAccess() {
                if !self.attemptInstallEventTap() {
                    self.scheduleRetryTimer()
                }
                self.postStatusDidChange()
                return
            }

            self.hasShownPermissionAlertThisSession = true
            self.scheduleRetryTimer()
            self.presentPermissionAlert()
            self.postStatusDidChange()
        }
    }

    /// Opens the macOS System Settings Input Monitoring pane.
    func openInputMonitoringSettings() {
        if let url = URL(string: Constants.inputMonitoringSettingsURL) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Stops monitoring and releases the event tap, timers, and observers.
    func stop() {
        performOnMainThread {
            self.shouldBeRunning = false
            self.stopRetryTimer()
            self.cancelPendingPasteboardPoll()
            self.detector.reset()
            self.removeWorkspaceObserver()
            self.tearDownEventTap()
            self.postStatusDidChange()
        }
    }

    // MARK: Private

    private enum Constants {
        static let inputMonitoringSettingsURL =
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        static let pasteboardPollInterval: TimeInterval = 0.025
        static let pasteboardPollTimeout: TimeInterval = 0.5
        static let permissionRetryInterval: TimeInterval = 2.0
    }

    private var detector: DoubleCopyDetector
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var installedRunLoop: CFRunLoop?

    private var workspaceObserver: NSObjectProtocol?
    private var retryTimer: Timer?
    private var pendingPollWorkItem: DispatchWorkItem?
    private var pollGeneration: UInt = 0

    private var cancellables: Set<AnyCancellable> = []
    private var isObservingDefaults = false
    private var shouldBeRunning = false
    private var hasShownPermissionAlertThisSession = false

    private static func clampedIntervalSeconds(fromMs ms: Int) -> TimeInterval {
        let clamped = min(maxIntervalMs, max(minIntervalMs, ms))
        return TimeInterval(clamped) / 1000.0
    }

    private func performOnMainThread(_ block: @escaping () -> ()) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private func observeDefaultsIfNeeded() {
        guard !isObservingDefaults else { return }
        isObservingDefaults = true

        Defaults.publisher(.enableDoubleCopyTranslate, options: [])
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self else { return }
                if change.newValue {
                    start(promptIfNeeded: true)
                } else {
                    stop()
                }
            }
            .store(in: &cancellables)

        Defaults.publisher(.doubleCopyTranslateInterval, options: [])
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard let self else { return }
                detector.interval = Self.clampedIntervalSeconds(fromMs: change.newValue)
            }
            .store(in: &cancellables)
    }

    private func syncIntervalFromDefaults() {
        detector.interval = Self.clampedIntervalSeconds(fromMs: Defaults[.doubleCopyTranslateInterval])
    }

    @discardableResult
    private func attemptInstallEventTap() -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))

        if eventTap != nil {
            stopRetryTimer()
            return true
        }

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }
            let monitor = Unmanaged<DoubleCopyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handleTapEvent(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: refcon
        ) else {
            logInfo("DoubleCopyMonitor: failed to create listen-only CGEventTap")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let mainRunLoop = CFRunLoopGetMain()
        CFRunLoopAddSource(mainRunLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        installedRunLoop = mainRunLoop

        stopRetryTimer()
        logInfo("DoubleCopyMonitor: started listen-only CGEventTap")
        postStatusDidChange()
        return true
    }

    private func tearDownEventTap() {
        dispatchPrecondition(condition: .onQueue(.main))

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource, let installedRunLoop {
                CFRunLoopRemoveSource(installedRunLoop, runLoopSource, .commonModes)
            }
            CFMachPortInvalidate(eventTap)
            self.runLoopSource = nil
            self.installedRunLoop = nil
            self.eventTap = nil
            logInfo("DoubleCopyMonitor: stopped listen-only CGEventTap")
        }
    }

    private func installWorkspaceObserverIfNeeded() {
        guard workspaceObserver == nil else { return }

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = activatedApp?.processIdentifier ?? 0
            detector.handleApplicationActivated(pid: pid)
        }
    }

    private func removeWorkspaceObserver() {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
    }

    private func scheduleRetryTimer() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard retryTimer == nil else { return }

        retryTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.permissionRetryInterval,
            repeats: true
        ) { [weak self] _ in
            guard let self else { return }
            guard shouldBeRunning, Defaults[.enableDoubleCopyTranslate] else {
                stopRetryTimer()
                return
            }
            guard CGPreflightListenEventAccess() else { return }
            _ = attemptInstallEventTap()
        }
    }

    private func stopRetryTimer() {
        retryTimer?.invalidate()
        retryTimer = nil
    }

    private func presentPermissionAlert() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard shouldBeRunning, !CGPreflightListenEventAccess() else { return }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("double_copy.permission.alert.title", comment: "")
        alert.informativeText = NSLocalizedString("double_copy.permission.alert.message", comment: "")
        alert.addButton(withTitle: NSLocalizedString("double_copy.permission.alert.open_settings", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("double_copy.permission.alert.later", comment: ""))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            _ = CGRequestListenEventAccess()
            openInputMonitoringSettings()
            if CGPreflightListenEventAccess() {
                _ = attemptInstallEventTap()
            }
        }
    }

    private func handleTapEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        case .keyDown:
            break
        default:
            return
        }

        let currentPID = getpid()
        let sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
        if sourcePID == Int64(currentPID) {
            return
        }

        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return
        }

        // Our popup is a non-activating panel, so the source app can stay frontmost
        // while the popup has keyboard focus. Ignore copies made inside our own windows
        // to avoid re-translating the translation.
        if frontmostApp.processIdentifier == currentPID || NSApp.isActive || NSApp.keyWindow != nil {
            detector.reset()
            return
        }

        if let selfBundleID = Bundle.main.bundleIdentifier,
           !selfBundleID.isEmpty,
           frontmostApp.bundleIdentifier == selfBundleID {
            detector.reset()
            return
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let timestamp = ProcessInfo.processInfo.systemUptime
        let changeCount = NSPasteboard.general.changeCount

        let action = detector.handleKeyDown(
            keyCode: keyCode,
            flags: event.flags,
            isAutoRepeat: isAutoRepeat,
            timestamp: timestamp,
            frontmostPID: frontmostApp.processIdentifier,
            pasteboardChangeCount: changeCount
        )

        if case let .triggered(firstChangeCount) = action {
            pollPasteboardAndTranslate(
                firstChangeCount: firstChangeCount,
                secondChangeCount: changeCount
            )
        }
    }

    private func pollPasteboardAndTranslate(
        firstChangeCount: Int,
        secondChangeCount: Int
    ) {
        cancelPendingPasteboardPoll()
        pollGeneration &+= 1
        let generation = pollGeneration
        let deadline = ProcessInfo.processInfo.systemUptime + Constants.pasteboardPollTimeout

        schedulePasteboardPollStep(
            generation: generation,
            firstChangeCount: firstChangeCount,
            secondChangeCount: secondChangeCount,
            deadline: deadline
        )
    }

    private func schedulePasteboardPollStep(
        generation: UInt,
        firstChangeCount: Int,
        secondChangeCount: Int,
        deadline: TimeInterval
    ) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, pollGeneration == generation, shouldBeRunning else { return }

            let currentChangeCount = NSPasteboard.general.changeCount
            if currentChangeCount != secondChangeCount {
                pendingPollWorkItem = nil
                processPasteboardIfEligible(changeCount: currentChangeCount)
                return
            }

            if ProcessInfo.processInfo.systemUptime >= deadline {
                pendingPollWorkItem = nil
                if currentChangeCount != firstChangeCount {
                    processPasteboardIfEligible(changeCount: currentChangeCount)
                }
                return
            }

            schedulePasteboardPollStep(
                generation: generation,
                firstChangeCount: firstChangeCount,
                secondChangeCount: secondChangeCount,
                deadline: deadline
            )
        }

        pendingPollWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Constants.pasteboardPollInterval,
            execute: workItem
        )
    }

    private func cancelPendingPasteboardPoll() {
        pollGeneration &+= 1
        pendingPollWorkItem?.cancel()
        pendingPollWorkItem = nil
    }

    private func processPasteboardIfEligible(changeCount: Int) {
        guard !PasteboardSelfWriteTracker.shared.isSelfWrite(changeCount: changeCount) else {
            return
        }

        switch DoubleCopyPasteboardFilter.readFromGeneralPasteboard() {
        case .ignored:
            return
        case .tooLong:
            let message = NSLocalizedString("double_copy.text_too_long", comment: "")
            EZToast.showText(message)
        case let .valid(text):
            let windowManager = EZWindowManager.shared()
            windowManager.lastPoint = NSEvent.mouseLocation
            windowManager.doubleCopyTranslateText(text)
        }
    }

    private func postStatusDidChange() {
        NotificationCenter.default.post(name: .doubleCopyMonitorStatusDidChange, object: nil)
    }
}
