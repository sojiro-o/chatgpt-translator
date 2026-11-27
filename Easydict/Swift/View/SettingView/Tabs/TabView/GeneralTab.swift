//
//  GeneralTab.swift
//  Easydict
//
//  Created by Kyle on 2023/12/29.
//  Copyright © 2023 izual. All rights reserved.
//

import Defaults
import LaunchAtLogin
import SFSafeSymbols
import SwiftUI

// MARK: - GeneralTab

struct GeneralTab: View {
    // MARK: Internal

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Form {
            Section {
                FirstAndSecondLanguageSettingView()
            } header: {
                Text("setting.general.query_language.header")
            }

            Section {
                Toggle(isOn: $enableMarkdownRendering) {
                    Label(
                        "setting.general.display.enable_markdown_rendering",
                        systemSymbol: .docRichtext
                    )
                }
            } header: {
                Text("setting.general.display.header")
            } footer: {
                Text("setting.general.display.enable_markdown_rendering.description")
                    .font(.footnote)
            }

            Section {
                Toggle(isOn: $quickTranslateAlignmentEnabled) {
                    Text("setting.general.display.quick_translate_alignment_enabled")
                }
            } footer: {
                Text("setting.general.display.quick_translate_alignment_enabled.description")
                    .font(.footnote)
            }

            Section {
                Picker(
                    "setting.general.chatgpt_web.double_copy_target",
                    selection: $doubleCopyOpensChatGPTWeb
                ) {
                    Text("setting.general.chatgpt_web.double_copy_target.popup")
                        .tag(false)
                    Text("setting.general.chatgpt_web.double_copy_target.chatgpt_web")
                        .tag(true)
                }
                Toggle(isOn: $chatGPTWebTemporaryChat) {
                    Text("setting.general.chatgpt_web.temporary_chat")
                }
                Toggle(isOn: $chatGPTWebCompactDisplay) {
                    Text("setting.general.chatgpt_web.compact_display")
                }
            }

            Section {
                Picker("setting.general.language", selection: $languageState.language) {
                    ForEach(LanguageState.LanguageType.allCases, id: \.rawValue) { language in
                        Text(language.name)
                            .tag(language)
                    }
                }
                Picker(
                    "setting.general.appearance.light_dark_appearance", selection: $appearanceType
                ) {
                    ForEach(AppearanceType.allCases, id: \.rawValue) { option in
                        Text(option.title)
                            .tag(option)
                    }
                }

                LaunchAtLogin.Toggle {
                    Text("launch_at_startup")
                }

                Picker(
                    "modify_menubar_icon",
                    selection: $selectedMenuBarIcon
                ) {
                    ForEach(MenuBarIconType.allCases) { option in
                        Label {
                            EmptyView()
                        } icon: {
                            Image(option.rawValue)
                                .renderingMode(.template)
                        }
                        .labelStyle(.iconOnly)
                    }
                }

            } header: {
                Text("setting.general.app_setting.header")
            }

            Section {
                let bindingFontSize = Binding<Double>(
                    get: {
                        Double(fontSizeOptionIndex)
                    },
                    set: { newValue in
                        fontSizeOptionIndex = UInt(newValue)
                    }
                )
                Slider(value: bindingFontSize, in: 0.0 ... 4.0, step: 1) {
                    Text("setting.general.font.font_size.label")
                } minimumValueLabel: {
                    Text("small")
                        .font(.system(size: 10))
                } maximumValueLabel: {
                    Text("large")
                        .font(.system(size: 14))
                }
            } header: {
                Text("setting.general.font.header")
            } footer: {
                Text("hints_keyboard_shortcuts_font_size")
                    .font(.footnote)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Private

    // App setting
    @EnvironmentObject private var languageState: LanguageState

    @Default(.appearanceType) private var appearanceType
    @Default(.selectedMenuBarIcon) private var selectedMenuBarIcon
    @Default(.fontSizeOptionIndex) private var fontSizeOptionIndex
    @Default(.enableMarkdownRendering) private var enableMarkdownRendering
    @Default(.quickTranslateAlignmentEnabled) private var quickTranslateAlignmentEnabled
    @Default(.doubleCopyOpensChatGPTWeb) private var doubleCopyOpensChatGPTWeb
    @Default(.chatGPTWebTemporaryChat) private var chatGPTWebTemporaryChat
    @Default(.chatGPTWebCompactDisplay) private var chatGPTWebCompactDisplay
}

#Preview {
    GeneralTab()
}

// MARK: - FirstAndSecondLanguageSettingView

private struct FirstAndSecondLanguageSettingView: View {
    // MARK: Internal

    var body: some View {
        Group {
            Picker("setting.general.language.first_language", selection: $firstLanguage) {
                ForEach(Language.allAvailableOptions, id: \.rawValue) { option in
                    Text(verbatim: "\(option.flagEmoji) \(option.localizedName)")
                        .tag(option)
                }
            }
            Picker("setting.general.language.second_language", selection: $secondLanguage) {
                ForEach(Language.allAvailableOptions, id: \.rawValue) { option in
                    Text(verbatim: "\(option.flagEmoji) \(option.localizedName)")
                        .tag(option)
                }
            }
        }
        .onChange(of: firstLanguage) { [firstLanguage] newValue in
            let oldValue = firstLanguage
            if newValue == secondLanguage {
                secondLanguage = oldValue
                languageDuplicatedAlert = .init(
                    duplicatedLanguage: newValue, setField: .second, setLanguage: oldValue
                )
            }
        }
        .onChange(of: secondLanguage) { [secondLanguage] newValue in
            let oldValue = secondLanguage
            if newValue == firstLanguage {
                firstLanguage = oldValue
                languageDuplicatedAlert = .init(
                    duplicatedLanguage: newValue, setField: .first, setLanguage: oldValue
                )
            }
        }
        .alert(
            "setting.general.language.duplicated_alert.title",
            isPresented: showLanguageDuplicatedAlert,
            presenting: languageDuplicatedAlert
        ) { _ in
        } message: { alert in
            Text(alert.description)
        }
    }

    // MARK: Private

    private struct LanguageDuplicateAlert: CustomStringConvertible {
        enum Field: CustomLocalizedStringResourceConvertible {
            case first
            case second

            // MARK: Internal

            var localizedStringResource: LocalizedStringResource {
                switch self {
                case .first:
                    "setting.general.language.duplicated_alert.field.first"
                case .second:
                    "setting.general.language.duplicated_alert.field.second"
                }
            }
        }

        let duplicatedLanguage: Language

        let setField: Field

        let setLanguage: Language

        var description: String {
            // First language should not be same as second language. (\(duplicatedLanguage))
            // \(setField) is replaced with \(setLanguage).
            String(
                localized:
                "setting.general.language.duplicated_alert \(duplicatedLanguage.localizedName)\(String(localized: setField.localizedStringResource))\(setLanguage.localizedName)"
            )
        }
    }

    @State private var languageDuplicatedAlert: LanguageDuplicateAlert?

    @Default(.firstLanguage) private var firstLanguage
    @Default(.secondLanguage) private var secondLanguage

    private var showLanguageDuplicatedAlert: Binding<Bool> {
        .init {
            languageDuplicatedAlert != nil
        } set: { newValue in
            if !newValue {
                languageDuplicatedAlert = nil
            }
        }
    }
}
