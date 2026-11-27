//
//  ChatGPTWebPanelController.swift
//  Easydict
//
//  Created by QuickTranslate on 2026/11/27.
//  Copyright © 2026 izual. All rights reserved.
//

import AppKit
import Combine
import Defaults
import Foundation
import WebKit

// MARK: - ChatGPTWebPanelController

/// Manages the dedicated floating window that opens `chatgpt.com` for translation
/// and follow-up questions without reading or extracting any page output.
@objcMembers
final class ChatGPTWebPanelController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    // MARK: Lifecycle

    private override init() {
        super.init()
        observeDefaults()
    }

    // MARK: Internal

    static let shared = ChatGPTWebPanelController()

    /// Fixed identifier for the dedicated `WKWebsiteDataStore` on macOS 14 and later.
    static let dataStoreIdentifier = UUID(uuidString: "9B7E4A12-5C8D-4E3F-A1B2-C3D4E5F60718")!

    /// Maximum character length of the full encoded URL before falling back to manual paste.
    static let maxEncodedURLCharacterCount = 6000

    /// Opens the ChatGPT window with the given English source text.
    @objc(showWithSourceText:)
    func show(sourceText: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.show(sourceText: sourceText)
            }
            return
        }

        let trimmed = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showEmptyChat()
            return
        }

        cancelIdleDiscardTimer()
        let panel = ensurePanel()
        let webView = ensureWebView()

        if isFollowUpMode, webView.url != nil {
            setNoticeMessage(nil)
            ensureSourceTextOnPasteboard(trimmed)
            presentPanel(panel, webView: webView)
            focusPromptAndPaste(in: webView, panel: panel)
            return
        }

        let prompt = Self.buildTranslationPrompt(for: trimmed)
        let useTemporaryChat = Defaults[.chatGPTWebTemporaryChat]

        if let queryURL = Self.buildChatURL(prompt: prompt, temporaryChat: useTemporaryChat),
           queryURL.absoluteString.count <= Self.maxEncodedURLCharacterCount {
            setNoticeMessage(nil)
            presentPanel(panel, webView: webView)
            webView.load(URLRequest(url: queryURL))
        } else if let emptyURL = Self.buildChatURL(prompt: nil, temporaryChat: useTemporaryChat) {
            ensureSourceTextOnPasteboard(trimmed)
            setNoticeMessage(String(localized: "quick_translate.chatgpt_web.long_text_paste_notice"))
            presentPanel(panel, webView: webView)
            webView.load(URLRequest(url: emptyURL))
        }
    }

    /// Opens the ChatGPT window with an empty chat (temporary chat by default).
    @objc
    func showEmptyChat() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.showEmptyChat()
            }
            return
        }

        cancelIdleDiscardTimer()
        let panel = ensurePanel()
        let webView = ensureWebView()

        setNoticeMessage(nil)
        presentPanel(panel, webView: webView)

        let useTemporaryChat = Defaults[.chatGPTWebTemporaryChat]
        if let url = Self.buildChatURL(prompt: nil, temporaryChat: useTemporaryChat) {
            webView.load(URLRequest(url: url))
        }
    }

    /// Closes (hides) the ChatGPT window and schedules ephemeral storage cleanup and idle teardown.
    @objc
    func closePanel() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.closePanel()
            }
            return
        }
        hidePanel(restorePreviousApp: true)
    }

    /// Tears down the WebView and removes the dedicated `WKWebsiteDataStore` during app uninstall.
    @MainActor
    func removeDataStoreForUninstall() async {
        cancelIdleDiscardTimer()
        panel?.orderOut(nil)
        discardWebView()

        let store = Self.makeWebsiteDataStore()
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.removeData(ofTypes: allTypes, modifiedSince: .distantPast) {
                continuation.resume()
            }
        }

        if #available(macOS 14.0, *) {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                WKWebsiteDataStore.remove(forIdentifier: Self.dataStoreIdentifier) { _ in
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        _ = notification
        guard let panel else { return }
        if isPinned
            || activeModalCount > 0
            || panel.attachedSheet != nil
            || !panel.sheets.isEmpty
            || NSApp.modalWindow != nil {
            return
        }
        hidePanel(restorePreviousApp: false)
    }

    func windowDidResize(_ notification: Notification) {
        _ = notification
        saveCurrentPanelFrame()
    }

    func windowDidMove(_ notification: Notification) {
        _ = notification
        saveCurrentPanelFrame()
    }

    func windowWillClose(_ notification: Notification) {
        _ = notification
        clearEphemeralWebStorage()
        scheduleIdleDiscardTimer()
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> ()
    ) {
        _ = webView
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about" || scheme == "blob" || scheme == "data" {
            decisionHandler(.allow)
            return
        }

        guard scheme == "https" || scheme == "http" else {
            decisionHandler(.cancel)
            return
        }

        // Links with target="_blank" (targetFrame == nil) open in the user's default browser.
        guard let targetFrame = navigationAction.targetFrame else {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        // Main-frame navigations outside ChatGPT / OpenAI / Cloudflare verification open in the default browser.
        if targetFrame.isMainFrame, !Self.isAllowedInAppHost(url.host) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        _ = navigation
        updateLoadingIndicator(isLoading: webView.isLoading)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        _ = navigation
        updateLoadingIndicator(isLoading: webView.isLoading)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        _ = navigation
        updateLoadingIndicator(isLoading: webView.isLoading)
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = navigation
        _ = error
        updateLoadingIndicator(isLoading: webView.isLoading)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        _ = navigation
        _ = error
        updateLoadingIndicator(isLoading: webView.isLoading)
    }

    // MARK: - WKUIDelegate

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    )
        -> WKWebView? {
        _ = webView
        _ = configuration
        _ = windowFeatures
        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme == "https" || scheme == "http" {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> ()
    ) {
        _ = webView
        _ = frame

        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = parameters.allowsDirectories
        openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
        openPanel.resolvesAliases = true

        activeModalCount += 1
        let finish: ([URL]?) -> () = { [weak self] urls in
            self?.activeModalCount = max(0, (self?.activeModalCount ?? 1) - 1)
            completionHandler(urls)
        }

        if let panel, panel.isVisible {
            openPanel.beginSheetModal(for: panel) { response in
                finish(response == .OK ? openPanel.urls : nil)
            }
        } else {
            let response = openPanel.runModal()
            finish(response == .OK ? openPanel.urls : nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> ()
    ) {
        _ = webView
        _ = frame

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "quick_translate.chatgpt_web.title")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "updater.alert.ok"))

        activeModalCount += 1
        let finish: () -> () = { [weak self] in
            self?.activeModalCount = max(0, (self?.activeModalCount ?? 1) - 1)
            completionHandler()
        }

        if let panel, panel.isVisible {
            alert.beginSheetModal(for: panel) { _ in
                finish()
            }
        } else {
            _ = alert.runModal()
            finish()
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> ()
    ) {
        _ = webView
        _ = frame

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "quick_translate.chatgpt_web.title")
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "updater.alert.ok"))
        alert.addButton(withTitle: String(localized: "uninstaller.confirm.cancel"))

        activeModalCount += 1
        let finish: (Bool) -> () = { [weak self] confirmed in
            self?.activeModalCount = max(0, (self?.activeModalCount ?? 1) - 1)
            completionHandler(confirmed)
        }

        if let panel, panel.isVisible {
            alert.beginSheetModal(for: panel) { response in
                finish(response == .alertFirstButtonReturn)
            }
        } else {
            let response = alert.runModal()
            finish(response == .alertFirstButtonReturn)
        }
    }

    // MARK: Private

    private enum Constants {
        static let minPanelSize = NSSize(width: 360, height: 420)
        static let defaultPanelSize = NSSize(width: 480, height: 640)
        static let headerBarHeight: CGFloat = 32
        static let noticeBarHeight: CGFloat = 24
        static let mouseOffset = CGPoint(x: 18, y: -12)
        static let pageZoomFactor: CGFloat = 0.9
        static let webViewIdleTimeout: TimeInterval = 10 * 60
    }

    /// Strict query value character set so `+`, `&`, `=`, `#`, and `%` in source text are percent-encoded.
    private static let queryValueAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "!*'();:@&=+$,/?#[]%")
        return allowed
    }()

    /// Modest CSS injection that hides the left sidebar when compact display is enabled.
    /// Does not read or return any DOM content.
    private static let compactDisplayInjectionScript = """
    (function() {
        var styleId = 'qt-chatgpt-compact-style';
        if (document.getElementById(styleId)) { return; }
        var style = document.createElement('style');
        style.id = styleId;
        style.textContent = '[data-testid="screen-sidebar"], #stage-slideover-sidebar { display: none !important; } main form { margin-bottom: 4px !important; }';
        (document.head || document.documentElement).appendChild(style);
    })();
    """

    private static let removeCompactDisplayScript = """
    (function() {
        var el = document.getElementById('qt-chatgpt-compact-style');
        if (el && el.parentNode) { el.parentNode.removeChild(el); }
    })();
    """

    /// Moves focus to the prompt input field in follow-up mode without returning any value.
    private static let focusPromptTextareaScript = """
    (function() {
        var el = document.querySelector('#prompt-textarea') || document.querySelector('textarea');
        if (el) { el.focus(); }
    })();
    """

    private var panel: ChatGPTWebPanel?
    private var webViewContainer: NSView?
    private var webView: WKWebView?
    private var loadingIndicator: NSProgressIndicator?
    private var noticeContainerView: NSView?
    private var noticeLabel: NSTextField?
    private var followUpButton: ChatGPTHeaderButton?
    private var pinButton: ChatGPTHeaderButton?

    private var isFollowUpMode = false
    private var isPinned = false
    private var activeModalCount = 0
    private var idleDiscardTimer: Timer?
    private var webViewLoadingCancellable: AnyCancellable?
    private var defaultsCancellables: Set<AnyCancellable> = []
    private weak var previousFrontmostApp: NSRunningApplication?

    private static func makeWebsiteDataStore() -> WKWebsiteDataStore {
        if #available(macOS 14.0, *) {
            return WKWebsiteDataStore(forIdentifier: dataStoreIdentifier)
        } else {
            return .default()
        }
    }

    private static func buildTranslationPrompt(for sourceText: String) -> String {
        "次の英文を自然な日本語に翻訳してください。訳文だけを出力してください。\n\n\(sourceText)"
    }

    private static func buildChatURL(prompt: String?, temporaryChat: Bool) -> URL? {
        var queryParts: [String] = []
        if temporaryChat {
            queryParts.append("temporary-chat=true")
        }
        if let prompt, !prompt.isEmpty {
            guard let encodedPrompt = prompt.addingPercentEncoding(
                withAllowedCharacters: queryValueAllowedCharacters
            ) else {
                return nil
            }
            queryParts.append("q=\(encodedPrompt)")
        }

        let urlString = queryParts.isEmpty
            ? "https://chatgpt.com/"
            : "https://chatgpt.com/?\(queryParts.joined(separator: "&"))"
        return URL(string: urlString)
    }

    private static func isAllowedInAppHost(_ rawHost: String?) -> Bool {
        guard let host = rawHost?.lowercased(), !host.isEmpty else {
            return false
        }
        let allowedDomains = [
            "chatgpt.com",
            "openai.com",
            "oaistatic.com",
            "oaiusercontent.com",
            "cloudflare.com",
            "arkoselabs.com",
            "funcaptcha.com",
        ]
        return allowedDomains.contains { domain in
            host == domain || host.hasSuffix("." + domain)
        }
    }

    private func observeDefaults() {
        Defaults.publisher(.chatGPTWebCompactDisplay, options: [])
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                self?.applyCompactDisplaySetting(isEnabled: change.newValue)
            }
            .store(in: &defaultsCancellables)
    }

    private func applyCompactDisplaySetting(isEnabled: Bool) {
        guard let webView else { return }
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        if isEnabled {
            let script = WKUserScript(
                source: Self.compactDisplayInjectionScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            controller.addUserScript(script)
            webView.evaluateJavaScript(Self.compactDisplayInjectionScript, completionHandler: nil)
        } else {
            webView.evaluateJavaScript(Self.removeCompactDisplayScript, completionHandler: nil)
        }
    }

    private func ensurePanel() -> ChatGPTWebPanel {
        if let panel {
            return panel
        }

        let initialSize = restoredPanelSize()
        let createdPanel = ChatGPTWebPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        createdPanel.title = String(localized: "quick_translate.chatgpt_web.title")
        createdPanel.titleVisibility = .hidden
        createdPanel.titlebarAppearsTransparent = true
        createdPanel.titlebarSeparatorStyle = .none
        createdPanel.standardWindowButton(.closeButton)?.isHidden = true
        createdPanel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        createdPanel.standardWindowButton(.zoomButton)?.isHidden = true
        createdPanel.level = .floating
        createdPanel.isFloatingPanel = true
        createdPanel.becomesKeyOnlyIfNeeded = false
        createdPanel.hidesOnDeactivate = false
        createdPanel.isReleasedWhenClosed = false
        createdPanel.isMovableByWindowBackground = false
        createdPanel.minSize = Constants.minPanelSize
        createdPanel.backgroundColor = .windowBackgroundColor
        createdPanel.delegate = self
        createdPanel.onCloseRequested = { [weak self] in
            self?.closePanel()
        }

        let rootView = NSView()
        rootView.translatesAutoresizingMaskIntoConstraints = false

        let headerView = buildHeaderView()
        let noticeView = buildNoticeView()

        let dividerView = NSBox()
        dividerView.boxType = .separator
        dividerView.translatesAutoresizingMaskIntoConstraints = false

        let webContainer = NSView()
        webContainer.translatesAutoresizingMaskIntoConstraints = false

        let headerStack = NSStackView(views: [headerView, noticeView])
        headerStack.orientation = .vertical
        headerStack.alignment = .width
        headerStack.spacing = 0
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(headerStack)
        rootView.addSubview(dividerView)
        rootView.addSubview(webContainer)

        createdPanel.contentView = rootView

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: rootView.topAnchor),
            headerStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            headerStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),

            headerView.heightAnchor.constraint(equalToConstant: Constants.headerBarHeight),
            noticeView.heightAnchor.constraint(equalToConstant: Constants.noticeBarHeight),

            dividerView.topAnchor.constraint(equalTo: headerStack.bottomAnchor),
            dividerView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            dividerView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),

            webContainer.topAnchor.constraint(equalTo: dividerView.bottomAnchor),
            webContainer.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            webContainer.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])

        webViewContainer = webContainer
        panel = createdPanel
        updateHeaderToggleButtons()
        return createdPanel
    }

    private func buildHeaderView() -> NSView {
        let header = ChatGPTWebHeaderView()
        header.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: String(localized: "quick_translate.chatgpt_web.title"))
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator = spinner

        let newChatBtn = ChatGPTHeaderButton(
            title: String(localized: "quick_translate.chatgpt_web.header.new_temporary_chat")
        )
        newChatBtn.toolTip = String(localized: "quick_translate.chatgpt_web.header.new_temporary_chat")
        newChatBtn.onClick = { [weak self] in
            self?.handleNewTemporaryChatClicked()
        }

        let followUpBtn = ChatGPTHeaderButton(
            title: String(localized: "quick_translate.chatgpt_web.header.follow_up")
        )
        followUpBtn.toolTip = String(localized: "quick_translate.chatgpt_web.header.follow_up.tooltip")
        followUpBtn.onClick = { [weak self] in
            self?.handleFollowUpToggleClicked()
        }
        followUpButton = followUpBtn

        let pinBtn = ChatGPTHeaderButton(
            title: String(localized: "quick_translate.chatgpt_web.header.pin")
        )
        pinBtn.toolTip = String(localized: "quick_translate.chatgpt_web.header.pin")
        pinBtn.onClick = { [weak self] in
            self?.handlePinToggleClicked()
        }
        pinButton = pinBtn

        let closeBtn = ChatGPTHeaderButton(
            title: String(localized: "quick_translate.chatgpt_web.header.close")
        )
        closeBtn.toolTip = String(localized: "quick_translate.chatgpt_web.header.close")
        closeBtn.onClick = { [weak self] in
            self?.closePanel()
        }

        let buttonStack = NSStackView(views: [newChatBtn, followUpBtn, pinBtn, closeBtn])
        buttonStack.orientation = .horizontal
        buttonStack.alignment = .centerY
        buttonStack.spacing = 4
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(titleLabel)
        header.addSubview(spinner)
        header.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            spinner.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            spinner.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 14),
            spinner.heightAnchor.constraint(equalToConstant: 14),

            buttonStack.leadingAnchor.constraint(greaterThanOrEqualTo: spinner.trailingAnchor, constant: 6),
            buttonStack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            buttonStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])

        return header
    }

    private func buildNoticeView() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.15).cgColor
        container.isHidden = true

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        noticeContainerView = container
        noticeLabel = label
        return container
    }

    private func ensureWebView() -> WKWebView {
        if let webView {
            return webView
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = Self.makeWebsiteDataStore()

        let contentController = WKUserContentController()
        if Defaults[.chatGPTWebCompactDisplay] {
            let script = WKUserScript(
                source: Self.compactDisplayInjectionScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            contentController.addUserScript(script)
        }
        configuration.userContentController = contentController

        let createdWebView = WKWebView(frame: .zero, configuration: configuration)
        createdWebView.navigationDelegate = self
        createdWebView.uiDelegate = self
        createdWebView.pageZoom = Constants.pageZoomFactor
        createdWebView.translatesAutoresizingMaskIntoConstraints = false

        if let container = webViewContainer {
            container.addSubview(createdWebView)
            NSLayoutConstraint.activate([
                createdWebView.topAnchor.constraint(equalTo: container.topAnchor),
                createdWebView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                createdWebView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                createdWebView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }

        webViewLoadingCancellable = createdWebView.publisher(for: \.isLoading)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoading in
                self?.updateLoadingIndicator(isLoading: isLoading)
            }

        webView = createdWebView
        return createdWebView
    }

    private func presentPanel(_ panel: ChatGPTWebPanel, webView: WKWebView) {
        recordFrontmostApplicationBeforeActivation()

        let shouldReposition = !panel.isVisible || !isPinned
        let targetSize = restoredPanelSize()
        if !panel.isVisible {
            panel.setContentSize(targetSize)
        }

        if shouldReposition {
            positionPanel(panel)
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(webView)
    }

    /// The last panel frame, stored as `NSStringFromRect` text (`.zero` when unset).
    private func savedPanelFrame() -> NSRect {
        let stored = Defaults[.chatGPTWebWindowFrame]
        return stored.isEmpty ? .zero : NSRectFromString(stored)
    }

    private func restoredPanelSize() -> NSSize {
        let savedFrame = savedPanelFrame()
        let width = savedFrame.width >= Constants.minPanelSize.width
            ? savedFrame.width
            : Constants.defaultPanelSize.width
        let height = savedFrame.height >= Constants.minPanelSize.height
            ? savedFrame.height
            : Constants.defaultPanelSize.height
        return NSSize(width: width, height: height)
    }

    private func positionPanel(_ panel: NSPanel) {
        let panelSize = panel.frame.size
        let savedFrame = savedPanelFrame()

        let desiredOrigin: CGPoint
        let targetScreen: NSScreen?

        if isPinned,
           savedFrame.width >= Constants.minPanelSize.width,
           savedFrame.height >= Constants.minPanelSize.height {
            desiredOrigin = savedFrame.origin
            targetScreen = NSScreen.screens.first { $0.frame.intersects(savedFrame) }
        } else {
            let mouseLocation = NSEvent.mouseLocation
            desiredOrigin = CGPoint(
                x: mouseLocation.x + Constants.mouseOffset.x,
                y: mouseLocation.y + Constants.mouseOffset.y - panelSize.height
            )
            targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
        }

        let visibleFrame = (targetScreen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let clampedWidth = min(panelSize.width, visibleFrame.width)
        let clampedHeight = min(panelSize.height, visibleFrame.height)

        let minX = visibleFrame.minX
        let maxX = max(minX, visibleFrame.maxX - clampedWidth)
        let minY = visibleFrame.minY
        let maxY = max(minY, visibleFrame.maxY - clampedHeight)

        let safeOrigin = NSPoint(
            x: min(max(desiredOrigin.x, minX), maxX),
            y: min(max(desiredOrigin.y, minY), maxY)
        )
        panel.setFrameOrigin(safeOrigin)
        saveCurrentPanelFrame()
    }

    private func saveCurrentPanelFrame() {
        guard let panel else { return }
        let frame = panel.frame
        guard frame.width >= Constants.minPanelSize.width,
              frame.height >= Constants.minPanelSize.height
        else {
            return
        }
        Defaults[.chatGPTWebWindowFrame] = NSStringFromRect(frame)
    }

    private func recordFrontmostApplicationBeforeActivation() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        if frontmost.processIdentifier != getpid(),
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousFrontmostApp = frontmost
        }
    }

    private func hidePanel(restorePreviousApp: Bool) {
        guard let panel, panel.isVisible else { return }
        saveCurrentPanelFrame()
        panel.orderOut(nil)
        // Hiding on focus loss keeps the page intact for follow-up questions; an explicit
        // close (or the idle teardown) removes the conversation's temporary web storage.
        if restorePreviousApp {
            clearEphemeralWebStorage()
        }
        scheduleIdleDiscardTimer()

        if restorePreviousApp,
           let previousFrontmostApp,
           !previousFrontmostApp.isTerminated {
            previousFrontmostApp.activate(options: [])
        }
    }

    private func handleNewTemporaryChatClicked() {
        showEmptyChat()
    }

    private func handleFollowUpToggleClicked() {
        isFollowUpMode.toggle()
        updateHeaderToggleButtons()
    }

    private func handlePinToggleClicked() {
        isPinned.toggle()
        updateHeaderToggleButtons()
        if isPinned {
            saveCurrentPanelFrame()
        }
    }

    private func updateHeaderToggleButtons() {
        followUpButton?.isToggledOn = isFollowUpMode
        pinButton?.isToggledOn = isPinned
    }

    private func updateLoadingIndicator(isLoading: Bool) {
        if isLoading {
            loadingIndicator?.startAnimation(nil)
        } else {
            loadingIndicator?.stopAnimation(nil)
        }
    }

    private func setNoticeMessage(_ message: String?) {
        if let message, !message.isEmpty {
            noticeLabel?.stringValue = message
            noticeContainerView?.isHidden = false
        } else {
            noticeLabel?.stringValue = ""
            noticeContainerView?.isHidden = true
        }
    }

    private func ensureSourceTextOnPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        if pasteboard.string(forType: .string) != text {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            PasteboardSelfWriteTracker.shared.recordSelfWrite(changeCount: pasteboard.changeCount)
        }
    }

    private func focusPromptAndPaste(in webView: WKWebView, panel: NSPanel) {
        panel.makeFirstResponder(webView)
        webView.evaluateJavaScript(Self.focusPromptTextareaScript) { [weak self] _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, let panel = self.panel, let webView = self.webView else { return }
                panel.makeFirstResponder(webView)
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: panel)
            }
        }
    }

    private func clearEphemeralWebStorage() {
        let types: Set<String> = [
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeSessionStorage,
        ]
        let store = webView?.configuration.websiteDataStore ?? Self.makeWebsiteDataStore()
        store.removeData(ofTypes: types, modifiedSince: .distantPast) {}
    }

    private func scheduleIdleDiscardTimer() {
        cancelIdleDiscardTimer()
        idleDiscardTimer = Timer.scheduledTimer(
            withTimeInterval: Constants.webViewIdleTimeout,
            repeats: false
        ) { [weak self] _ in
            guard let self else { return }
            if panel?.isVisible != true {
                discardWebView()
            }
        }
    }

    private func cancelIdleDiscardTimer() {
        idleDiscardTimer?.invalidate()
        idleDiscardTimer = nil
    }

    private func discardWebView() {
        webViewLoadingCancellable?.cancel()
        webViewLoadingCancellable = nil
        updateLoadingIndicator(isLoading: false)

        if let webView {
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.configuration.userContentController.removeAllUserScripts()
            webView.removeFromSuperview()
        }
        clearEphemeralWebStorage()
        webView = nil
    }
}

// MARK: - ChatGPTWebPanel

private final class ChatGPTWebPanel: NSPanel {
    var onCloseRequested: (() -> ())?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()

        if flags == .command {
            switch key {
            case "w":
                onCloseRequested?()
                return true
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) {
                    return true
                }
            case "c":
                if NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        PasteboardSelfWriteTracker.shared.recordSelfWrite()
                    }
                    return true
                }
            case "x":
                if NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        PasteboardSelfWriteTracker.shared.recordSelfWrite()
                    }
                    return true
                }
            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) {
                    return true
                }
            case "z":
                if NSApp.sendAction(Selector(("undo:")), to: nil, from: self) {
                    return true
                }
            default:
                break
            }
        } else if flags == [.command, .shift], key == "z" {
            if NSApp.sendAction(Selector(("redo:")), to: nil, from: self) {
                return true
            }
        }

        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - ChatGPTWebHeaderView

private final class ChatGPTWebHeaderView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

// MARK: - ChatGPTHeaderButton

private final class ChatGPTHeaderButton: NSButton {
    // MARK: Lifecycle

    init(title: String) {
        self.labelTitle = title
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Internal

    var onClick: (() -> ())?

    var isToggledOn = false {
        didSet {
            guard oldValue != isToggledOn else { return }
            applyAppearance()
        }
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(width: base.width + 10, height: 22)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    // MARK: Private

    private let labelTitle: String

    private func configure() {
        isBordered = false
        bezelStyle = .inline
        setButtonType(.momentaryChange)
        target = self
        action = #selector(handleClicked)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        applyAppearance()
    }

    @objc
    private func handleClicked() {
        onClick?()
    }

    private func applyAppearance() {
        let font = NSFont.systemFont(
            ofSize: 11,
            weight: isToggledOn ? .semibold : .regular
        )
        let textColor: NSColor = isToggledOn ? .controlAccentColor : .labelColor
        attributedTitle = NSAttributedString(
            string: labelTitle,
            attributes: [
                .font: font,
                .foregroundColor: textColor,
            ]
        )

        if isToggledOn {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.75).cgColor
        } else {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
            layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.15).cgColor
        }
    }
}
