//
//  QuickTranslateDistribution.swift
//  Easydict
//
//  Created for QuickTranslate app maintenance.
//

import Foundation

// MARK: - QuickTranslateDistribution

/// Shared distribution metadata for QuickTranslate releases on GitHub.
enum QuickTranslateDistribution {
    /// GitHub Releases API endpoint for the latest release.
    static let latestReleaseAPIURL = URL(
        string: "https://api.github.com/repos/sojiro-o/chatgpt-translator/releases/latest"
    )!

    /// Terminal command that installs or updates QuickTranslate from the latest release.
    static let installCommand =
        "curl -fsSL https://raw.githubusercontent.com/sojiro-o/chatgpt-translator/quicktranslate/scripts/install.sh | bash"

    /// Release tag prefix (`build-<N>`, where N equals `CFBundleVersion`).
    static let tagPrefix = "build-"

    /// Extracts the positive integer build number `N` from a `build-<N>` tag.
    static func parseBuildNumber(from tagName: String) -> Int? {
        guard tagName.hasPrefix(tagPrefix) else { return nil }
        let suffix = tagName.dropFirst(tagPrefix.count)
        guard !suffix.isEmpty,
              suffix.allSatisfy({ $0.isASCII && $0.isNumber }),
              let buildNumber = Int(suffix),
              buildNumber > 0
        else {
            return nil
        }
        return buildNumber
    }
}
