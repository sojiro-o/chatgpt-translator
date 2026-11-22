//
//  CodexDirectoryMigration.swift
//  Easydict
//
//  Created by Alfred on 2026/09/14.
//

import Foundation

// MARK: - CodexDirectoryMigration

/// Moves an existing managed Codex root to the current bundle-scoped location.
/// Existing destinations always win; legacy directories are never merged or overwritten.
enum CodexDirectoryMigration {
    // MARK: Internal

    static func run(
        pathManager _: AppPathManager = .current,
        fileManager _: FileManager = .default
    ) throws {
        // Disabled in QuickTranslate to avoid touching or moving upstream Easydict's
        // `Easydict/codex-managed` directory.
    }
}
