//
//  ShortcutTab.swift
//  Easydict
//
//  Created by Sharker on 2024/1/21.
//  Copyright © 2024 izual. All rights reserved.
//

import Defaults
import SwiftUI

// MARK: - ShortcutTab

struct ShortcutTab: View {
    var body: some View {
        Form {
            // Double Cmd+C translate
            DoubleCopyShortcutSettingView()
            // Global shortcut
            GlobalShortcutSettingView()
            // In app shortcut
            AppShortcutSettingView()
        }
        .formStyle(.grouped)
    }
}

// MARK: - DoubleCopyShortcutSettingView

private struct DoubleCopyShortcutSettingView: View {
    // MARK: Internal

    var body: some View {
        let intervalBinding = Binding<Double>(
            get: {
                Double(clampedInterval)
            },
            set: { newValue in
                let roundedStep = Int((newValue / 50.0).rounded()) * 50
                doubleCopyTranslateInterval = min(
                    DoubleCopyMonitor.maxIntervalMs,
                    max(DoubleCopyMonitor.minIntervalMs, roundedStep)
                )
            }
        )

        Section {
            Toggle(isOn: $enableDoubleCopyTranslate) {
                Text("setting.shortcut.double_copy.enable")
            }

            LabeledContent {
                HStack(spacing: 8) {
                    Slider(
                        value: intervalBinding,
                        in: Double(DoubleCopyMonitor.minIntervalMs) ... Double(DoubleCopyMonitor.maxIntervalMs),
                        step: 50
                    )
                    Text(verbatim: "\(clampedInterval) ms")
                        .frame(width: 56, alignment: .trailing)
                        .monospacedDigit()
                }
            } label: {
                Text("setting.shortcut.double_copy.interval")
            }
            .disabled(!enableDoubleCopyTranslate)
            .opacity(enableDoubleCopyTranslate ? 1 : 0.6)

            if enableDoubleCopyTranslate && !isMonitoringActive {
                HStack {
                    Text(
                        hasInputMonitoringPermission
                            ? LocalizedStringKey("setting.shortcut.double_copy.status.stopped")
                            : LocalizedStringKey("setting.shortcut.double_copy.status.permission_required")
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button(
                        hasInputMonitoringPermission
                            ? LocalizedStringKey("setting.shortcut.double_copy.action.resume")
                            : LocalizedStringKey("setting.shortcut.double_copy.action.grant_permission")
                    ) {
                        if hasInputMonitoringPermission {
                            DoubleCopyMonitor.shared.start(promptIfNeeded: false)
                        } else {
                            DoubleCopyMonitor.shared.requestPermissionAndStart()
                        }
                        refreshMonitorStatus()
                    }
                }
            }
        } header: {
            Text("setting.shortcut.double_copy.header")
        } footer: {
            Text("setting.shortcut.double_copy.desc")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            refreshMonitorStatus()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .doubleCopyMonitorStatusDidChange)
        ) { _ in
            refreshMonitorStatus()
        }
    }

    // MARK: Private

    @Default(.enableDoubleCopyTranslate) private var enableDoubleCopyTranslate
    @Default(.doubleCopyTranslateInterval) private var doubleCopyTranslateInterval

    @State private var hasInputMonitoringPermission = DoubleCopyMonitor.shared.hasInputMonitoringPermission
    @State private var isMonitoringActive = DoubleCopyMonitor.shared.isRunning

    private var clampedInterval: Int {
        min(
            DoubleCopyMonitor.maxIntervalMs,
            max(DoubleCopyMonitor.minIntervalMs, doubleCopyTranslateInterval)
        )
    }

    private func refreshMonitorStatus() {
        hasInputMonitoringPermission = DoubleCopyMonitor.shared.hasInputMonitoringPermission
        isMonitoringActive = DoubleCopyMonitor.shared.isRunning
    }
}

#Preview {
    ShortcutTab()
}
