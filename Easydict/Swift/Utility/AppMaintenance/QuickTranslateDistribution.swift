//
//  QuickTranslateDistribution.swift
//  Easydict
//
//  Created for QuickTranslate app maintenance.
//

import Foundation
import Security

// MARK: - QuickTranslateDistribution

/// Shared distribution metadata and code-signature verification for QuickTranslate.
enum QuickTranslateDistribution {
    /// Public GitHub repository hosting QuickTranslate releases.
    static let repository = "sojiro-o/chatgpt-translator"

    /// GitHub Releases API endpoint for the latest release.
    static let latestReleaseAPIURL = URL(
        string: "https://api.github.com/repos/sojiro-o/chatgpt-translator/releases/latest"
    )!

    /// Release archive asset name (`ditto -c -k --keepParent QuickTranslate.app`).
    static let zipAssetName = "QuickTranslate.zip"

    /// Release SHA-256 checksum asset name (`<64-hex>  QuickTranslate.zip`).
    static let sha256AssetName = "QuickTranslate.zip.sha256"

    /// Allowed prefix for release asset download URLs.
    static let downloadURLPrefix = "https://github.com/sojiro-o/chatgpt-translator/releases/download/"

    /// Designated requirement for official QuickTranslate self-signed builds.
    static let codeSigningRequirement =
        #"identifier "io.github.sojiro-o.QuickTranslate" and certificate leaf = H"2697524092a9b371d9be557c80d82f6a20557eb1""#

    /// Expected bundle identifier of official QuickTranslate builds.
    static let bundleID = "io.github.sojiro-o.QuickTranslate"

    /// Terminal command for manual install / reinstall.
    static let installCommand =
        "curl -fsSL https://raw.githubusercontent.com/sojiro-o/chatgpt-translator/quicktranslate/scripts/install.sh | bash"

    /// Release tag prefix (`build-<N>`).
    static let tagPrefix = "build-"

    /// Maximum accepted zip archive size (300 MB).
    static let maxZipDownloadBytes: Int64 = 300 * 1024 * 1024

    /// Returns `true` when `urlString` is a valid HTTPS URL under `downloadURLPrefix`.
    static func isAllowedDownloadURL(_ urlString: String) -> Bool {
        guard urlString.hasPrefix(downloadURLPrefix),
              let url = URL(string: urlString),
              url.scheme == "https"
        else {
            return false
        }
        return true
    }

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

    /// Validates the code signature of the app bundle at `bundleURL` against `codeSigningRequirement`.
    static func verifyCodeSignatureStatus(at bundleURL: URL) -> OSStatus {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            return createStatus
        }

        var requirement: SecRequirement?
        let requirementStatus = SecRequirementCreateWithString(
            codeSigningRequirement as CFString,
            [],
            &requirement
        )
        guard requirementStatus == errSecSuccess, let requirement else {
            return requirementStatus
        }

        let flags = SecCSFlags(
            rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode
        )
        return SecStaticCodeCheckValidity(staticCode, flags, requirement)
    }

    /// Returns `true` if the bundle at `bundleURL` satisfies `codeSigningRequirement`.
    static func verifyCodeSignature(at bundleURL: URL) -> Bool {
        verifyCodeSignatureStatus(at: bundleURL) == errSecSuccess
    }

    /// Returns `true` if the currently running app bundle satisfies `codeSigningRequirement`.
    static func isCurrentAppOfficiallySigned() -> Bool {
        verifyCodeSignature(at: Bundle.main.bundleURL)
    }
}
