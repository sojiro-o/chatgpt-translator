//
//  CodexCLILogger.swift
//  Easydict
//
//  Created by long2ice on 2026/05/07.
//  Copyright © 2026 izual. All rights reserved.
//

import Foundation

// MARK: - CodexCLILogger

/// Kept for source compatibility; logging is disabled in QuickTranslate so source
/// and translated text are never written to disk or broadcast to debug windows.
final class CodexCLILogger: @unchecked Sendable {
    // MARK: Lifecycle

    init(command _: String, prompt _: String) {}

    // MARK: Internal

    /// No-op in QuickTranslate.
    func start() {}

    /// No-op in QuickTranslate.
    func appendStdout(_: String) {}

    /// No-op in QuickTranslate.
    func finish(stderr _: String, exitCode _: Int, duration _: TimeInterval) {}
}

// MARK: - CodexCLIDebugLogger

/// Kept for source compatibility; notifications are disabled in QuickTranslate.
final class CodexCLIDebugLogger {
    static let shared = CodexCLIDebugLogger()

    static let didAppendNotification = Notification.Name("CodexCLIDebugLogDidAppend")
    static let textKey = "text"

    /// No-op in QuickTranslate.
    func post(_: String) {}
}
