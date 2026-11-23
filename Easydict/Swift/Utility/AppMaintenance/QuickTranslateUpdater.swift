//
//  QuickTranslateUpdater.swift
//  Easydict
//
//  Created for QuickTranslate app maintenance.
//

import AppKit
import Foundation

// MARK: - QuickTranslateUpdater

/// User-initiated update check backed by GitHub Releases.
///
/// Never checks automatically. Builds are ad-hoc signed, so the app does not
/// replace itself; it reports whether a newer build exists and offers the
/// install command, which the user runs in Terminal.
@MainActor
final class QuickTranslateUpdater {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = QuickTranslateUpdater()

    /// Starts a manual update check. Re-entrant calls while a check is running are ignored.
    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        Task { @MainActor in
            defer { self.isChecking = false }
            await self.performUpdateCheck()
        }
    }

    // MARK: Private

    private struct GitHubRelease: Decodable {
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
        }

        let tagName: String
    }

    private var isChecking = false

    private func performUpdateCheck() async {
        let currentBuild = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        let latestBuild: Int
        do {
            latestBuild = try await fetchLatestBuildNumber()
        } catch {
            logError("Update check failed: \(error.localizedDescription)")
            presentErrorAlert(
                message: String(
                    format: String(localized: "updater.error.network %@"),
                    error.localizedDescription
                )
            )
            return
        }

        if let currentBuild, latestBuild <= currentBuild {
            presentInfoAlert(
                title: String(localized: "updater.up_to_date.title"),
                message: String(
                    format: String(localized: "updater.up_to_date.message %@"),
                    String(currentBuild)
                )
            )
            return
        }

        presentInstallCommandAlert(
            title: String(
                format: String(localized: "updater.available.title %@"),
                String(latestBuild)
            ),
            message: String(
                format: String(localized: "updater.available.command_message %@"),
                QuickTranslateDistribution.installCommand
            )
        )
    }

    private func fetchLatestBuildNumber() async throws -> Int {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: QuickTranslateDistribution.latestReleaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode)
        else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(
                domain: "QuickTranslateUpdater",
                code: status,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(status)"]
            )
        }

        guard let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
              let build = QuickTranslateDistribution.parseBuildNumber(from: release.tagName)
        else {
            throw NSError(
                domain: "QuickTranslateUpdater",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "updater.error.invalid_release")]
            )
        }
        return build
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
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(QuickTranslateDistribution.installCommand, forType: .string)
            PasteboardSelfWriteTracker.shared.recordSelfWrite(changeCount: pasteboard.changeCount)
        }
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
}
