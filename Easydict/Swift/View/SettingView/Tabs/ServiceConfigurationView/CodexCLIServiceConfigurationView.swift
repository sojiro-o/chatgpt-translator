//
//  CodexCLIServiceConfigurationView.swift
//  Easydict
//
//  Created by long2ice on 2026/05/07.
//  Copyright © 2026 izual. All rights reserved.
//

import Defaults
import SwiftUI

// MARK: - CodexCLIServiceConfigurationView

/// Configuration view for the Codex (ChatGPT sign-in) translation service.
///
/// Always operates in built-in ChatGPT sign-in mode and hides local CLI,
/// debug log, API key, endpoint, and dictionary/sentence options.
struct CodexCLIServiceConfigurationView: View {
    // MARK: Lifecycle

    init(service: CodexCLIService) {
        self.service = service
        self._managedModel = .init(service.managedModelKey)
        self._managedEffort = .init(service.managedReasoningEffortKey)
        CodexRequestCoordinator.shared.observe(uuid: service.uuid)
    }

    // MARK: Internal

    var body: some View {
        Section {
            CodexManagedAccountView(configuration: CodexServiceConfiguration(uuid: service.uuid))
            if !isManagedModelSupported || !managedEfforts.contains(managedEffort) {
                Text("service.codex_cli.managed.unsupported_selection")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }

        // Managed `.default` effort uses the selected model's catalog default.
        // QuickTranslate defaults to `.low` for fast responses while allowing overrides.
        Section {
            DisclosureGroup("service.codex_cli.advanced") {
                Picker("service.configuration.codex_cli.model.title", selection: managedModelSelection) {
                    ForEach(CodexManagedRuntime.bundledModelNames, id: \.self) { model in
                        Text(verbatim: model).tag(Optional(model))
                    }
                }
                Picker(
                    "service.configuration.codex_cli.reasoning_effort.title",
                    selection: managedEffortSelection
                ) {
                    if managedEffortSelection.wrappedValue == nil {
                        Text("service.codex_cli.managed.select_effort")
                            .tag(nil as CodexReasoningEffort?)
                            .disabled(true)
                    }
                    ForEach(managedEfforts, id: \.self) { effort in
                        Text(effort == .default ? "service.codex_cli.managed.reasoning_default" : effort.title)
                            .tag(Optional(effort))
                    }
                }
                .disabled(!isManagedModelSupported)
            }
        }
        StreamConfigurationView(
            service: service,
            showAPIKeySection: false,
            showEndpointSection: false,
            showSupportedModelsSection: false,
            showUsedModelSection: false,
            showCustomPromptSection: false,
            showTranslationToggle: false,
            showSentenceToggle: false,
            showDictionaryToggle: false,
            showThinkTagContent: false,
            showValidationButton: false
        )
    }

    // MARK: Private

    private let service: CodexCLIService
    @Default private var managedModel: String
    @Default private var managedEffort: CodexReasoningEffort

    private var isManagedModelSupported: Bool {
        CodexManagedRuntime.bundledModelNames.contains(managedModel)
    }

    private var managedModelSelection: Binding<String?> {
        Binding(get: { isManagedModelSupported ? managedModel : nil }, set: { model in
            if let model { managedModel = model }
        })
    }

    private var managedEffortSelection: Binding<CodexReasoningEffort?> {
        Binding(get: { managedEfforts.contains(managedEffort) ? managedEffort : nil }, set: { effort in
            if let effort { managedEffort = effort }
        })
    }

    private var managedEfforts: [CodexReasoningEffort] {
        CodexServiceConfiguration.reasoningEfforts(mode: .managed, model: managedModel)
    }
}
