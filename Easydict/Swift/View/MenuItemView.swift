//
//  MenuItemView.swift
//  Easydict
//
//  Created by Kyle on 2023/12/29.
//  Copyright © 2023 izual. All rights reserved.
//

import Defaults
import SettingsAccess
import SFSafeSymbols
import SwiftUI

// MARK: - MenuItemView

struct MenuItemView: View {
    // MARK: Internal

    var body: some View {
        // .menuBarExtraStyle为 .menu 时某些控件可能会失效，只能显示内容（按照菜单项高度、图像以 template 方式渲染）无法交互
        // 比如 Stepper、Slider 等，像基本的 Button、Text、Divider、Image 等还是能正常显示的。
        // Button 和Label的systemImage是不会渲染的
        Group {
            versionItem

            Divider()

            pasteboardTranslateItem.keyboardShortcut(.pasteboardTranslate)

            Divider()

            signInChatGPTItem
            settingItem.keyboardShortcut(.init(","))

            Divider()

            checkForUpdatesItem
            uninstallItem

            Divider()

            quitItem.keyboardShortcut(.init("q"))
        }
    }

    // MARK: Private

    @State private var currentVersion =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

    private var versionString: String {
        "QuickTranslate \(currentVersion)"
    }

    @ViewBuilder private var pasteboardTranslateItem: some View {
        menuItem(for: .pasteboardTranslate)
    }

    // MARK: - Other Items

    /// Version item
    @ViewBuilder private var versionItem: some View {
        Text(versionString)
    }

    /// Sign in to ChatGPT item (opens Service settings with ChatGPT/Codex selected)
    @ViewBuilder private var signInChatGPTItem: some View {
        let titleKey = LocalizedStringKey("menu.sign_in_chatgpt")
        if #available(macOS 14.0, *) {
            SettingsLink {
                Text(titleKey)
            } preAction: {
                logInfo("Open ChatGPT Sign-In Settings")
                SettingsNavigationState.shared.openChatGPTService()
                NSApplication.shared.activateApp()
            } postAction: {
                // nothing to do
            }
        } else {
            Button(titleKey) {
                logInfo("Open ChatGPT Sign-In Settings")
                SettingsNavigationState.shared.openChatGPTService()
                NSApplication.shared.activateApp()

                // Refer https://stackoverflow.com/a/77265223/8378840
                NSApplication.shared.sendAction(
                    Selector(("showSettingsWindow:")), to: nil, from: nil
                )
            }
        }
    }

    /// Settings item
    @ViewBuilder private var settingItem: some View {
        let titleKey = LocalizedStringKey("Settings...")
        if #available(macOS 14.0, *) {
            SettingsLink {
                Text(titleKey)
            } preAction: {
                logInfo("Open App Settings")
                NSApplication.shared.activateApp()
            } postAction: {
                // nothing to do
            }
        } else {
            Button(titleKey) {
                logInfo("Open App Settings")
                NSApplication.shared.activateApp()

                // Refer https://stackoverflow.com/a/77265223/8378840
                NSApplication.shared.sendAction(
                    Selector(("showSettingsWindow:")), to: nil, from: nil
                )
            }
        }
    }

    /// Check for updates item
    @ViewBuilder private var checkForUpdatesItem: some View {
        Button("menu.check_for_updates") {
            logInfo("Check for Updates")
            Task { @MainActor in
                QuickTranslateUpdater.shared.checkForUpdates()
            }
        }
    }

    /// Uninstall QuickTranslate item
    @ViewBuilder private var uninstallItem: some View {
        Button("menu.uninstall_quicktranslate") {
            logInfo("Uninstall QuickTranslate")
            Task { @MainActor in
                QuickTranslateUninstaller.shared.uninstall()
            }
        }
    }

    /// Quit item
    @ViewBuilder private var quitItem: some View {
        Button("menu.quit_quicktranslate") {
            logInfo("Quit Application")
            NSApplication.shared.terminate(nil)
        }
    }
}

// MARK: - MenuItemView Extensions

extension MenuItemView {
    /// Create a menu item from ShortcutAction configuration
    fileprivate func menuItem(for shortcutType: ShortcutAction) -> some View {
        MenuItemBuilder(
            data: MenuItemData(
                icon: shortcutType.icon,
                titleKey: shortcutType.localizedStringKey(),
                action: shortcutType.executeAction
            )
        )
    }
}

// MARK: - MenuItemData

/// Data structure for menu items
private struct MenuItemData {
    // MARK: Lifecycle

    init(icon: SFSymbol, titleKey: String, action: @escaping () -> ()) {
        self.icon = icon
        self.titleKey = titleKey
        self.action = action
    }

    // MARK: Internal

    let icon: SFSymbol
    let titleKey: String
    let action: () -> ()
}

// MARK: - MenuItemBuilder

/// Builder for creating consistent menu items
private struct MenuItemBuilder: View {
    let data: MenuItemData

    var body: some View {
        let titleKey = data.titleKey
        Button {
            logInfo("Menu Action: \(titleKey)")
            data.action()
        } label: {
            HStack {
                Image(systemSymbol: data.icon)
                Text(LocalizedStringKey(titleKey))
            }
        }
    }
}

#Preview {
    MenuItemView()
}
