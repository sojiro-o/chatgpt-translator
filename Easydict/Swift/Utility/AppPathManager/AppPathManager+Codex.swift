//
//  AppPathManager+Codex.swift
//  Easydict
//
//  Created by Alfred on 2026/09/14.
//

import Foundation

extension AppPathManager {
    /// The root directory for Easydict-managed Codex files.
    var codexDirectory: URL {
        appSupportDirectory.appendingPathComponent("codex", isDirectory: true)
    }

    /// The directory containing downloaded Codex runtime components.
    var codexComponentsDirectory: URL {
        codexDirectory.appendingPathComponent("components", isDirectory: true)
    }

    /// The isolated `CODEX_HOME` used by the managed Codex runtime.
    var codexStateDirectory: URL {
        codexDirectory.appendingPathComponent("state", isDirectory: true)
    }

    /// Older roots checked by `CodexDirectoryMigration`, disabled in QuickTranslate
    /// so upstream Easydict's managed directory is never moved.
    var legacyCodexDirectories: [URL] {
        []
    }
}
