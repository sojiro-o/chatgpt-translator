//
//  GitHubReleaseFetcher.swift
//  Easydict
//
//  Created by Sharker on 2024/5/29.
//  Copyright © 2024 izual. All rights reserved.
//

import Foundation

// MARK: - GitHubReleaseFetcher

/// Fetches release versions of a GitHub repository (disabled in QuickTranslate).
enum GitHubReleaseFetcher {
    // MARK: Internal

    /// Update checks are disabled in QuickTranslate; always returns nil without network requests.
    static func latestVersion(
        of repo: String = AppConstants.repoName,
        includePrerelease: Bool
    ) async
        -> String? {
        _ = repo
        _ = includePrerelease
        return nil
    }

    /// Whether `candidate` is a newer version than `current`, eg. 2.10.0 is newer than 2.9.1.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        current.compare(candidate, options: .numeric) == .orderedAscending
    }
}

// MARK: - GitHubRelease

/// The subset of a GitHub release response that Easydict uses.
struct GitHubRelease: Decodable {
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }

    let tagName: String
}
