//
//  AboutTab.swift
//  Easydict
//
//  Created by Kyle on 2023/10/29.
//  Copyright © 2023 izual. All rights reserved.
//

import SFSafeSymbols
import SwiftUI

// MARK: - AboutTab

struct AboutTab: View {
    // MARK: Internal

    var body: some View {
        HStack(alignment: .center, spacing: 30) {
            Image(.logo)
                .resizable()
                .renderingMode(.original)
                .frame(width: 100, height: 100)
                .shadow(color: .gray, radius: 1, x: 0, y: 0.8)
                .padding(.bottom, 2)
                .padding(.leading, 16)
                .padding(.trailing, 16)

            VStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appName)
                        .font(.system(size: 35, weight: .medium))

                    Text("current_version \(version)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)

                    Text("setting.about.derivative_notice")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 440, alignment: .leading)

                    Text(copyrightInfo)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text("setting.about.license_notice")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 12)
                }

                HStack(spacing: 12) {
                    Button {
                        NSWorkspace.shared.open(AppConstants.repoURL)
                    } label: {
                        Label("setting.about.repository_link", systemSymbol: .starFill)
                    }

                    Button {
                        NSWorkspace.shared.open(
                            URL(string: "https://github.com/tisfeng/Easydict")!
                        )
                    } label: {
                        Label("setting.about.upstream_link", systemSymbol: .book)
                    }

                    Button {
                        HostWindowManager.shared.showAcknowWindow()
                    } label: {
                        Label("setting.about.acknowledgements", systemSymbol: .checkmarkSealFill)
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: Private

    @Environment(\.openWindow) private var openWindow

    private var appName: String {
        Bundle.main.infoDictionary?["CFBundleName"] as? String ?? ""
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private var copyrightInfo: String {
        Bundle.main.localizedString(
            forKey: "NSHumanReadableCopyright",
            value: "Copyright © 2023-2025 tisfeng. All rights reserved.",
            table: "InfoPlist"
        )
    }
}

#Preview {
    AboutTab()
}
