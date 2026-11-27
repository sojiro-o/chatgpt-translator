//
//  CodexManagedRuntimeTests.swift
//  EasydictTests
//
//  Created by Alfred on 2026/09/14.
//

@testable import Easydict
import Foundation
import Testing

// MARK: - CodexManagedRuntimeTests

/// Verifies the isolation rules applied before a managed Codex command starts.
@MainActor
@Suite("Codex managed runtime")
struct CodexManagedRuntimeTests {
    @Test("user skills do not block managed login while skill instructions stay disabled")
    func userSkillsDoNotBlockManagedLogin() async throws {
        for release in [CodexRuntimeRelease.legacy, .modern] {
            try await withAccountFixture(release: release) { fixture in
                let skillDirectory = fixture.runtime().home
                    .appendingPathComponent(".agents/skills/example", isDirectory: true)
                try FileManager.default.createDirectory(
                    at: skillDirectory,
                    withIntermediateDirectories: true
                )
                try Data("test skill".utf8).write(
                    to: skillDirectory.appendingPathComponent("SKILL.md")
                )
                let account = fixture.account()

                account.login(origin: release.rawValue)
                try await waitForAccount { !account.isBusy && account.isSignedIn }

                #expect(fixture.invocationCount("login") == 1)
                #expect(fixture.invocationCount("exec") == 1)
                #expect(fixture.execArguments.contains("skills.include_instructions=false"))
            }
        }
    }

    @Test("modern runtime trims agent prompt sections and supports optional priority service tier")
    func modernRuntimeTrimsAgentPromptSectionsAndSupportsFastMode() async throws {
        try await withAccountFixture(release: .modern) { fixture in
            let runtime = fixture.runtime()
            let defaultArgs = try runtime.translationArguments(
                model: runtime.release.defaultModel,
                effort: "low"
            )
            let fastArgs = try runtime.translationArguments(
                model: runtime.release.defaultModel,
                effort: "low",
                fastMode: true
            )
            let appServerArgs = runtime.appServerArguments()
            let expectedInstructions = "instructions=\(CodexManagedRuntime.quoted(CodexManagedRuntime.translationInstructions))"
            let legacyDeveloperInstructions = "developer_instructions=\(CodexManagedRuntime.quoted(CodexManagedRuntime.translationInstructions))"

            for arguments in [defaultArgs, appServerArgs] {
                #expect(arguments.contains(expectedInstructions))
                #expect(!arguments.contains(legacyDeveloperInstructions))
                #expect(arguments.contains("include_permissions_instructions=false"))
                #expect(arguments.contains("include_environment_context=false"))
                #expect(arguments.contains("include_collaboration_mode_instructions=false"))
                #expect(arguments.contains("include_apps_instructions=false"))
                #expect(arguments.contains("personality"))
                #expect(arguments.contains("skill_search"))
            }
            #expect(!defaultArgs.contains("service_tier=\"priority\""))
            #expect(fastArgs.contains("service_tier=\"priority\""))
        }

        try await withAccountFixture(release: .legacy) { fixture in
            let runtime = fixture.runtime()
            let legacyArgs = try runtime.translationArguments(
                model: runtime.release.defaultModel,
                effort: "low",
                fastMode: true
            )
            let legacyDeveloperInstructions = "developer_instructions=\(CodexManagedRuntime.quoted(CodexManagedRuntime.translationInstructions))"

            #expect(legacyArgs.contains(legacyDeveloperInstructions))
            #expect(!legacyArgs.contains("include_permissions_instructions=false"))
            #expect(!legacyArgs.contains("include_environment_context=false"))
            #expect(!legacyArgs.contains("service_tier=\"priority\""))
        }
    }
}
