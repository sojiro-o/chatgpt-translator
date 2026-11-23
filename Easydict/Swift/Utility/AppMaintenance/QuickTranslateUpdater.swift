//
//  QuickTranslateUpdater.swift
//  Easydict
//
//  Created for QuickTranslate app maintenance.
//

import AppKit
import CryptoKit
import Foundation

// MARK: - QuickTranslateUpdater

/// User-initiated in-app updater backed by GitHub Releases.
/// Never performs background or automatic update checks.
@MainActor
final class QuickTranslateUpdater {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = QuickTranslateUpdater()

    /// Starts a manual update check. Re-entrant calls while an update is running are ignored.
    func checkForUpdates() {
        guard !isUpdating else { return }
        isUpdating = true
        Task { @MainActor in
            defer { self.isUpdating = false }
            await self.performUpdateCheck()
        }
    }

    // MARK: Private

    private enum UpdaterError: Error {
        case network(String)
        case invalidRelease
        case invalidCurrentBuild
        case invalidDownloadURL
        case fileTooLarge
        case checksumMismatch
        case extractFailed
        case signatureInvalid
        case bundleMismatch
        case launchFailed(String)

        var localizedMessage: String {
            switch self {
            case let .network(detail):
                return String(format: String(localized: "updater.error.network %@"), detail)
            case .invalidRelease:
                return String(localized: "updater.error.invalid_release")
            case .invalidCurrentBuild:
                return String(localized: "updater.error.invalid_current_build")
            case .invalidDownloadURL:
                return String(localized: "updater.error.invalid_download_url")
            case .fileTooLarge:
                return String(localized: "updater.error.file_too_large")
            case .checksumMismatch:
                return String(localized: "updater.error.checksum_mismatch")
            case .extractFailed:
                return String(localized: "updater.error.extract_failed")
            case .signatureInvalid:
                return String(localized: "updater.error.signature_invalid")
            case .bundleMismatch:
                return String(localized: "updater.error.bundle_mismatch")
            case let .launchFailed(detail):
                return String(format: String(localized: "updater.error.launch_failed %@"), detail)
            }
        }
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    private var isUpdating = false

    private func performUpdateCheck() async {
        // 1. Refuse to update unofficial / ad-hoc builds without making any network requests.
        let officiallySigned = await Task.detached(priority: .userInitiated) {
            QuickTranslateDistribution.isCurrentAppOfficiallySigned()
        }.value
        guard officiallySigned else {
            logWarn("In-app update skipped: running app does not satisfy official signature requirement")
            presentInstallCommandAlert(
                title: String(localized: "updater.unsupported.title"),
                message: String(
                    format: String(localized: "updater.unsupported.message %@"),
                    QuickTranslateDistribution.installCommand
                )
            )
            return
        }

        // 2. Refuse to update while running under App Translocation.
        if Bundle.main.bundlePath.contains("/AppTranslocation/") {
            logWarn("In-app update skipped: running app is translocated")
            presentInstallCommandAlert(
                title: String(localized: "updater.translocated.title"),
                message: String(
                    format: String(localized: "updater.translocated.message %@"),
                    QuickTranslateDistribution.installCommand
                )
            )
            return
        }

        let destinationURL = Bundle.main.bundleURL

        let session = Self.makeEphemeralSession()
        defer { session.invalidateAndCancel() }

        do {
            // 3. Query GitHub Releases API for the latest release.
            let release = try await fetchLatestRelease(using: session)
            guard let latestBuild = QuickTranslateDistribution.parseBuildNumber(from: release.tagName) else {
                throw UpdaterError.invalidRelease
            }

            guard let currentVersionRaw = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
                  let currentBuild = Int(currentVersionRaw.trimmingCharacters(in: .whitespacesAndNewlines))
            else {
                throw UpdaterError.invalidCurrentBuild
            }

            if latestBuild <= currentBuild {
                presentInfoAlert(
                    title: String(localized: "updater.up_to_date.title"),
                    message: String(
                        format: String(localized: "updater.up_to_date.message %@"),
                        String(currentBuild)
                    )
                )
                return
            }

            // Validate release assets before prompting the user.
            guard let zipAsset = release.assets.first(where: { $0.name == QuickTranslateDistribution.zipAssetName }),
                  let shaAsset = release.assets.first(where: { $0.name == QuickTranslateDistribution.sha256AssetName })
            else {
                throw UpdaterError.invalidRelease
            }

            guard QuickTranslateDistribution.isAllowedDownloadURL(zipAsset.browserDownloadURL),
                  QuickTranslateDistribution.isAllowedDownloadURL(shaAsset.browserDownloadURL),
                  let zipURL = URL(string: zipAsset.browserDownloadURL),
                  let shaURL = URL(string: shaAsset.browserDownloadURL)
            else {
                throw UpdaterError.invalidDownloadURL
            }

            // 4. Ask the user for confirmation.
            guard presentUpdateConfirmationAlert(latestBuild: latestBuild) else {
                return
            }

            // Verify parent directory writability before downloading.
            guard isDestinationParentWritable(for: destinationURL) else {
                presentNotWritableAlert()
                return
            }

            // 5. Download and verify .sha256 and .zip.
            let expectedSHA256 = try await fetchExpectedSHA256(from: shaURL, using: session)
            let downloadedZipURL = try await downloadVerifiedZip(
                from: zipURL,
                expectedSHA256: expectedSHA256,
                using: session
            )
            defer { try? FileManager.default.removeItem(at: downloadedZipURL) }

            // 6. Create same-volume work directory, extract, and validate the app bundle.
            let workDir: URL
            do {
                workDir = try FileManager.default.url(
                    for: .itemReplacementDirectory,
                    in: .userDomainMask,
                    appropriateFor: destinationURL,
                    create: true
                )
            } catch {
                throw UpdaterError.extractFailed
            }

            var shouldCleanupWorkDir = true
            defer {
                if shouldCleanupWorkDir {
                    try? FileManager.default.removeItem(at: workDir)
                }
            }

            let extractedAppURL = try await Task.detached(priority: .userInitiated) {
                try Self.extractAndVerifyApp(
                    zipURL: downloadedZipURL,
                    workDir: workDir,
                    expectedBuild: latestBuild
                )
            }.value
            // `NSApp.terminate` does not return, so remove the archive before relaunching.
            try? FileManager.default.removeItem(at: downloadedZipURL)

            // 7. Re-check parent directory writability right before replacing.
            guard isDestinationParentWritable(for: destinationURL) else {
                presentNotWritableAlert()
                return
            }

            // 8. Spawn post-exit swap script and terminate the current app.
            try launchSwapHelper(
                extractedAppURL: extractedAppURL,
                destinationURL: destinationURL,
                workDir: workDir
            )
            shouldCleanupWorkDir = false
            logInfo("Update swap helper launched; terminating for relaunch")
            NSApp.terminate(nil)
        } catch let error as UpdaterError {
            logError("In-app update failed: \(error)")
            presentErrorAlert(message: error.localizedMessage)
        } catch {
            logError("In-app update failed: \(error.localizedDescription)")
            presentErrorAlert(
                message: UpdaterError.network(error.localizedDescription).localizedMessage
            )
        }
    }

    private nonisolated static func makeEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
    }

    private func fetchLatestRelease(using session: URLSession) async throws -> GitHubRelease {
        var request = URLRequest(url: QuickTranslateDistribution.latestReleaseAPIURL)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UpdaterError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdaterError.network("Invalid HTTP response")
        }
        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw UpdaterError.network("HTTP \(httpResponse.statusCode)")
        }

        do {
            return try JSONDecoder().decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdaterError.invalidRelease
        }
    }

    private func fetchExpectedSHA256(from url: URL, using session: URLSession) async throws -> String {
        guard QuickTranslateDistribution.isAllowedDownloadURL(url.absoluteString) else {
            throw UpdaterError.invalidDownloadURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UpdaterError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode)
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UpdaterError.network("HTTP \(status)")
        }

        guard let digest = Self.parseSHA256(from: data) else {
            throw UpdaterError.checksumMismatch
        }
        return digest
    }

    private func downloadVerifiedZip(
        from url: URL,
        expectedSHA256: String,
        using session: URLSession
    ) async throws -> URL {
        guard QuickTranslateDistribution.isAllowedDownloadURL(url.absoluteString) else {
            throw UpdaterError.invalidDownloadURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // The size cap is checked after the download; the resource timeout bounds the transfer.
        let downloadedURL: URL
        let response: URLResponse
        do {
            (downloadedURL, response) = try await session.download(for: request)
        } catch {
            throw UpdaterError.network(error.localizedDescription)
        }

        do {
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode)
            else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw UpdaterError.network("HTTP \(status)")
            }

            let fileSize = try downloadedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard fileSize > 0, Int64(fileSize) <= QuickTranslateDistribution.maxZipDownloadBytes else {
                throw UpdaterError.fileTooLarge
            }

            let actualSHA256 = try await Task.detached(priority: .userInitiated) {
                try Self.sha256Hex(of: downloadedURL)
            }.value

            guard actualSHA256 == expectedSHA256 else {
                throw UpdaterError.checksumMismatch
            }
            return downloadedURL
        } catch {
            try? FileManager.default.removeItem(at: downloadedURL)
            throw error
        }
    }

    private nonisolated static func parseSHA256(from data: Data) -> String? {
        guard data.count <= 4096,
              let content = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let lines = content
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count == 1 else { return nil }

        let parts = lines[0].split(whereSeparator: \.isWhitespace)
        guard let first = parts.first else { return nil }
        let digest = String(first).lowercased()
        guard digest.count == 64,
              digest.unicodeScalars.allSatisfy({
                  ($0.value >= 0x30 && $0.value <= 0x39) || ($0.value >= 0x61 && $0.value <= 0x66)
              })
        else {
            return nil
        }

        if parts.count >= 2 {
            let filename = String(parts[1])
            let normalizedName = filename.hasPrefix("*") ? String(filename.dropFirst()) : filename
            guard normalizedName == QuickTranslateDistribution.zipAssetName else {
                return nil
            }
        }
        return digest
    }

    private nonisolated static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func extractAndVerifyApp(
        zipURL: URL,
        workDir: URL,
        expectedBuild: Int
    ) throws -> URL {
        let exitCode: Int32
        do {
            exitCode = try runProcess(
                executablePath: "/usr/bin/ditto",
                arguments: ["-x", "-k", zipURL.path, workDir.path]
            )
        } catch {
            throw UpdaterError.extractFailed
        }
        guard exitCode == 0 else {
            throw UpdaterError.extractFailed
        }

        let fileManager = FileManager.default
        let extractedAppURL = workDir.appendingPathComponent("QuickTranslate.app", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard (try? fileManager.destinationOfSymbolicLink(atPath: extractedAppURL.path)) == nil,
              fileManager.fileExists(atPath: extractedAppURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw UpdaterError.extractFailed
        }

        guard QuickTranslateDistribution.verifyCodeSignature(at: extractedAppURL) else {
            throw UpdaterError.signatureInvalid
        }

        let infoPlistURL = extractedAppURL.appendingPathComponent("Contents/Info.plist")
        guard let plistData = try? Data(contentsOf: infoPlistURL),
              let plistObject = try? PropertyListSerialization.propertyList(
                  from: plistData,
                  options: [],
                  format: nil
              ),
              let infoDictionary = plistObject as? [String: Any],
              let bundleID = infoDictionary["CFBundleIdentifier"] as? String,
              bundleID == QuickTranslateDistribution.bundleID,
              let bundleVersion = infoDictionary["CFBundleVersion"] as? String,
              Int(bundleVersion.trimmingCharacters(in: .whitespacesAndNewlines)) == expectedBuild
        else {
            throw UpdaterError.bundleMismatch
        }

        // Best-effort quarantine attribute removal; ignore failures.
        _ = try? runProcess(
            executablePath: "/usr/bin/xattr",
            arguments: ["-dr", "com.apple.quarantine", extractedAppURL.path]
        )

        return extractedAppURL
    }

    private nonisolated static func runProcess(
        executablePath: String,
        arguments: [String]
    ) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationReason == .exit else {
            return -1
        }
        return process.terminationStatus
    }

    private func isDestinationParentWritable(for destinationURL: URL) -> Bool {
        let parentPath = destinationURL.deletingLastPathComponent().path
        return FileManager.default.isWritableFile(atPath: parentPath)
    }

    private func launchSwapHelper(
        extractedAppURL: URL,
        destinationURL: URL,
        workDir: URL
    ) throws {
        let swapScript = """
        pid="$1"; new="$2"; dest="$3"; work="$4"
        i=0; while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i+1)); done
        old="$dest.qt-old"
        rm -rf "$old"
        if mv "$dest" "$old"; then
          if mv "$new" "$dest"; then rm -rf "$old"; else mv "$old" "$dest"; fi
        fi
        rm -rf "$work"
        /usr/bin/open "$dest"
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            swapScript,
            "sh",
            String(ProcessInfo.processInfo.processIdentifier),
            extractedAppURL.path,
            destinationURL.path,
            workDir.path,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw UpdaterError.launchFailed(error.localizedDescription)
        }
    }

    // MARK: - Alerts

    private func presentInstallCommandAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "updater.alert.copy_command"))
        alert.addButton(withTitle: String(localized: "updater.alert.close"))

        if alert.runModal() == .alertFirstButtonReturn {
            copyToPasteboard(QuickTranslateDistribution.installCommand)
        }
    }

    private func presentNotWritableAlert() {
        presentInstallCommandAlert(
            title: String(localized: "updater.not_writable.title"),
            message: String(
                format: String(localized: "updater.not_writable.message %@"),
                QuickTranslateDistribution.installCommand
            )
        )
    }

    private func presentUpdateConfirmationAlert(latestBuild: Int) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(
            format: String(localized: "updater.available.title %@"),
            String(latestBuild)
        )
        alert.informativeText = String(localized: "updater.available.message")
        alert.addButton(withTitle: String(localized: "updater.alert.yes"))
        alert.addButton(withTitle: String(localized: "updater.alert.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentInfoAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "updater.alert.ok"))
        _ = alert.runModal()
    }

    private func presentErrorAlert(message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "updater.error.title")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "updater.alert.close"))
        _ = alert.runModal()
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        PasteboardSelfWriteTracker.shared.recordSelfWrite(changeCount: pasteboard.changeCount)
    }
}
