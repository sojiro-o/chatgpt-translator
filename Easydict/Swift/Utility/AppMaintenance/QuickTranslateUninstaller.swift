//
//  QuickTranslateUninstaller.swift
//  Easydict
//
//  Created for QuickTranslate app maintenance.
//

import AppKit
import Foundation
import LaunchAtLogin

// MARK: - QuickTranslateUninstaller

/// Performs an in-app uninstall of QuickTranslate:
/// ChatGPT sign-out, App Server shutdown, Launch-at-Login removal,
/// moving the app bundle to Trash, and post-exit cleanup of local files,
/// UserDefaults, and TCC permissions.
@MainActor
final class QuickTranslateUninstaller {
    // MARK: Lifecycle

    private init() {}

    // MARK: Internal

    static let shared = QuickTranslateUninstaller()

    /// Starts the interactive uninstall flow. Re-entrant calls while running are ignored.
    func uninstall() {
        guard !isUninstalling else { return }
        isUninstalling = true
        Task { @MainActor in
            defer { self.isUninstalling = false }
            await self.performUninstall()
        }
    }

    // MARK: Private

    private var isUninstalling = false

    private func performUninstall() async {
        // 1. Confirm destructive action with the user.
        guard presentConfirmationAlert() else { return }

        logInfo("Starting QuickTranslate uninstall")

        // 2. Cancel active Codex operations and sign out of ChatGPT (20s cap).
        CodexComponentManager.shared.cancel()
        let logoutSucceeded = await CodexManagedAccount.shared.logoutAndWait(timeout: 20)
        if !logoutSucceeded {
            logWarn("ChatGPT logout did not complete cleanly during uninstall")
        }

        // 3. Stop the resident Codex App Server process.
        await CodexManagedAppServer.shared.invalidate()

        // 4. Disable launch at login.
        LaunchAtLogin.isEnabled = false

        // 5. Move the app bundle to the Trash.
        let appURL = Bundle.main.bundleURL
        let trashedApp: Bool
        do {
            try FileManager.default.trashItem(at: appURL, resultingItemURL: nil)
            trashedApp = true
        } catch {
            logError("Failed to move QuickTranslate app to Trash: \(error.localizedDescription)")
            trashedApp = false
        }

        // 6. Prepare post-exit cleanup arguments before showing the final dialog.
        let bundleID = Bundle.main.bundleIdentifier ?? AppConstants.bundleID
        let cleanupPaths = Self.buildCleanupPaths(bundleID: bundleID)

        // 7. Inform the user before spawning the post-exit cleanup helper and terminating,
        // so the helper's 30-second exit wait begins immediately when termination starts.
        presentCompletionAlert(logoutSucceeded: logoutSucceeded, trashedApp: trashedApp)

        do {
            try launchPostExitCleanup(bundleID: bundleID, paths: cleanupPaths)
        } catch {
            logError("Failed to launch post-exit cleanup helper: \(error.localizedDescription)")
            presentCleanupLaunchWarningAlert()
        }

        NSApp.terminate(nil)
    }

    private func launchPostExitCleanup(bundleID: String, paths: [String]) throws {
        guard !bundleID.isEmpty, !bundleID.contains("/"), !bundleID.contains("..") else {
            return
        }

        let cleanupScript = """
        pid="$1"; bid="$2"; shift 2
        i=0; while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i+1)); done
        for p in "$@"; do
          case "$p" in
            *"$bid"*|*/quicktranslate-codex-*) rm -rf "$p" ;;
          esac
        done
        /usr/bin/defaults delete "$bid" >/dev/null 2>&1
        rm -f "$HOME/Library/Preferences/$bid.plist"
        /usr/bin/tccutil reset All "$bid" >/dev/null 2>&1
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            cleanupScript,
            "sh",
            String(ProcessInfo.processInfo.processIdentifier),
            bundleID,
        ] + paths
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private static func buildCleanupPaths(bundleID: String) -> [String] {
        guard !bundleID.isEmpty, !bundleID.contains("/"), !bundleID.contains("..") else {
            return []
        }

        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        let library = home.appendingPathComponent("Library", isDirectory: true)

        var candidates: [URL] = [
            AppPathManager.current.appSupportDirectory,
            AppPathManager.current.cachesDirectory,
            library.appendingPathComponent("HTTPStorages", isDirectory: true)
                .appendingPathComponent(bundleID, isDirectory: true),
            library.appendingPathComponent("HTTPStorages", isDirectory: true)
                .appendingPathComponent("\(bundleID).binarycookies", isDirectory: false),
            library.appendingPathComponent("Saved Application State", isDirectory: true)
                .appendingPathComponent("\(bundleID).savedState", isDirectory: true),
            library.appendingPathComponent("WebKit", isDirectory: true)
                .appendingPathComponent(bundleID, isDirectory: true),
        ]

        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .resolvingSymlinksInPath()
        if let entries = try? fileManager.contentsOfDirectory(atPath: tempDirectory.path) {
            for entry in entries where entry.hasPrefix("quicktranslate-codex-") {
                candidates.append(tempDirectory.appendingPathComponent(entry))
            }
        }

        var seen = Set<String>()
        var result: [String] = []
        for url in candidates {
            let path = url.standardizedFileURL.path
            guard isSafeCleanupPath(path, bundleID: bundleID, homePath: home.path),
                  seen.insert(path).inserted
            else {
                continue
            }
            result.append(path)
        }
        return result
    }

    private static func isSafeCleanupPath(
        _ path: String,
        bundleID: String,
        homePath: String
    ) -> Bool {
        guard !path.isEmpty,
              path.hasPrefix("/"),
              path != "/",
              path != homePath,
              !path.hasSuffix("/..")
        else {
            return false
        }
        let lastComponent = URL(fileURLWithPath: path).lastPathComponent
        return path.contains(bundleID) || lastComponent.hasPrefix("quicktranslate-codex-")
    }

    // MARK: - Alerts

    private func presentConfirmationAlert() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "uninstaller.confirm.title")
        alert.informativeText = String(localized: "uninstaller.confirm.message")
        alert.addButton(withTitle: String(localized: "uninstaller.confirm.uninstall"))
        alert.addButton(withTitle: String(localized: "uninstaller.confirm.cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentCompletionAlert(logoutSucceeded: Bool, trashedApp: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = (logoutSucceeded && trashedApp) ? .informational : .warning
        alert.messageText = String(localized: "uninstaller.done.title")

        var notes: [String] = [String(localized: "uninstaller.done.message")]
        if !logoutSucceeded {
            notes.append(String(localized: "uninstaller.done.logout_warning"))
        }
        if !trashedApp {
            notes.append(String(localized: "uninstaller.done.trash_warning"))
        }
        alert.informativeText = notes.joined(separator: "\n\n")
        alert.addButton(withTitle: String(localized: "updater.alert.ok"))
        _ = alert.runModal()
    }

    private func presentCleanupLaunchWarningAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "uninstaller.done.title")
        alert.informativeText = String(localized: "uninstaller.done.cleanup_warning")
        alert.addButton(withTitle: String(localized: "updater.alert.ok"))
        _ = alert.runModal()
    }
}
