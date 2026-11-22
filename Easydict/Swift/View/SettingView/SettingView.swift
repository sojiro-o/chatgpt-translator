//
//  SettingView.swift
//  Easydict
//
//  Created by Kyle on 2023/12/29.
//  Copyright © 2023 izual. All rights reserved.
//

import SwiftUI

// MARK: - SettingTab

enum SettingTab: Int {
    case general
    case service
    case disabled
    case advanced
    case shortcut
    case privacy
    case favorites
    case about
}

// MARK: - SettingsNavigationState

/// Shared navigation state for opening a specific settings tab or service from menu actions.
final class SettingsNavigationState: ObservableObject {
    static let shared = SettingsNavigationState()

    @Published var selectedTab: SettingTab = .general
    @Published var requestedServiceTypeID: String?

    func openChatGPTService() {
        selectedTab = .service
        requestedServiceTypeID = ServiceType.codexCLI.rawValue
    }
}

// MARK: - SettingView

struct SettingView: View {
    // MARK: Internal

    var body: some View {
        TabView(selection: $navigationState.selectedTab) {
            GeneralTab()
                .tabItem { Label("setting_general", systemImage: "gear") }
                .tag(SettingTab.general)

            ServiceTab()
                .tabItem { Label("service", systemImage: "briefcase") }
                .tag(SettingTab.service)

            ShortcutTab()
                .tabItem { Label("shortcut", systemImage: "command.square") }
                .tag(SettingTab.shortcut)

            AboutTab()
                .tabItem { Label("setting.about", systemImage: "info.bubble") }
                .tag(SettingTab.about)
        }
        .background(
            WindowAccessor(window: $window.didSet(execute: { _ in
                // reset frame when first launch
                resizeWindowFrame()
            }))
        )
        .onChange(of: navigationState.selectedTab) { _ in
            resizeWindowFrame()
        }
    }

    func resizeWindowFrame() {
        guard let window else { return }

        // Disable zoom button, refer: https://stackoverflow.com/a/66039864/8378840
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        // Keep the settings page Windows all the same width to avoid strange animations.
        let height: Double = switch navigationState.selectedTab {
        case .about:
            360
        default:
            defaultSettingsWindowHeight
        }

        let newSize = CGSize(width: settingsWindowWidth, height: height)

        let originalFrame = window.frame
        let newY = originalFrame.origin.y + originalFrame.size.height - newSize.height
        let newRect = NSRect(origin: CGPoint(x: originalFrame.origin.x, y: newY), size: newSize)

        window.setFrame(newRect, display: true, animate: false)
        // macOS 27: keep the sidebar below the title bar by removing the
        // `.fullSizeContentView` style SwiftUI keeps after resize. Older macOS
        // versions are unaffected.
        // Refer: https://github.com/tisfeng/Easydict/pull/1258#issuecomment-5186918247
        if #available(macOS 27.0, *) {
            window.styleMask.remove(.fullSizeContentView)
        }
        window.styleMask.remove(.resizable)
    }

    // MARK: Private

    @ObservedObject private var navigationState = SettingsNavigationState.shared
    @State private var window: NSWindow?

    private let settingsWindowWidth: Double = 960
    private let defaultSettingsWindowHeight: Double = 720
}

#Preview {
    SettingView()
}
