import Cocoa
import Carbon
import WebKit

// MARK: - 偏好设置窗口

final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var tabView: NSTabView?

    // Tab 1: 通用 — API 提供商 & Key
    private var providerPopup: NSPopUpButton?
    private var apiKeyVisibleField: PasteTextField?   // 明文输入
    private var apiKeyHiddenField: PasteSecureTextField?  // 密文（默认显示）
    private var apiKeyEyeButton: NSButton?
    private var apiKeyVisible: Bool = false             // 当前是否明文
    private var customEndpointField: NSTextField?
    private var customModelField: NSTextField?
    private var providerDescLabel: NSTextField?
    private var testStatusLabel: NSTextField?
    private var providerCardView: NSView?          // 当前提供商的卡片容器
    private var providerCardHeight: CGFloat = 0

    // Tab 2: 快捷键 — 4 个 HotkeyRecorder 实例
    let screenshotRecorder = HotkeyRecorder(
        allowedSoloKeyCodes: [],
        soloKeyHint: "",
        defaultDisplay: { SettingsManager.shared.hotkeyDisplay }
    )
    let selectionRecorder = HotkeyRecorder(
        allowedSoloKeyCodes: [],
        soloKeyHint: "",
        defaultDisplay: { SettingsManager.shared.selectionHotkeyDisplay }
    )
    let closePanelRecorder = HotkeyRecorder(
        allowedSoloKeyCodes: [0x35],
        soloKeyHint: "或直接按 ESC",
        defaultDisplay: { SettingsManager.shared.closePanelHotkeyDisplay }
    )
    let togglePanelRecorder = HotkeyRecorder(
        allowedSoloKeyCodes: [0x32],
        soloKeyHint: "或直接按 ` 键",
        defaultDisplay: { SettingsManager.shared.togglePanelHotkeyDisplay }
    )

    // Tab 3: 翻译模板
    private var templateTextView: NSTextView?
    private var templatePreviewWebView: WKWebView?

    func show() {
        if let w = window { w.close(); window = nil }

        let ww: CGFloat = 640, hh: CGFloat = 780
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: ww, height: hh),
                           styleMask: [.titled, .closable, .miniaturizable],
                           backing: .buffered, defer: false)
        win.title = "\(APP_DISPLAY_NAME) 偏好设置"
        win.center()
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.delegate = self

        let tabs = NSTabView(frame: NSRect(x: 12, y: 50, width: ww - 24, height: hh - 74))
        tabs.tabViewType = .topTabsBezelBorder
        tabs.tabViewBorderType = .none

        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.label = "通用"
        generalTab.view = buildGeneralTab(size: tabs.contentRect.size)
        tabs.addTabViewItem(generalTab)

        let hotkeysTab = NSTabViewItem(identifier: "hotkeys")
        hotkeysTab.label = "快捷键"
        hotkeysTab.view = buildHotkeysTab(size: tabs.contentRect.size)
        tabs.addTabViewItem(hotkeysTab)

        let templateTab = NSTabViewItem(identifier: "template")
        templateTab.label = "模板"
        templateTab.view = buildTemplateTab(size: tabs.contentRect.size)
        tabs.addTabViewItem(templateTab)

        win.contentView?.addSubview(tabs)
        tabView = tabs

        // 保存按钮——窗口底部，所有标签页通用
        let saveBtn = NSButton(title: "保存并应用", target: self, action: #selector(saveAllSettings))
        saveBtn.frame = NSRect(x: 16, y: 12, width: 120, height: 32)
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"  // Enter 键快捷保存
        win.contentView?.addSubview(saveBtn)

        window = win

        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        win.level = .floating
        let f = win.level
        DispatchQueue.main.async {
            win.level = f
            win.makeKeyAndOrderFront(nil)
        }

        // 初始化 API Key 字段（同时填充密文/明文两个字段，避免显示空框）
        loadKey(for: SettingsManager.shared.apiProvider)
    }

    // --- computed helpers ---

    private var activeApiKeyFieldValue: String {
        if apiKeyVisible { return apiKeyVisibleField?.stringValue ?? "" }
        return apiKeyHiddenField?.stringValue ?? ""
    }

    private func loadKey(for provider: AIProvider) {
        let key = SettingsManager.shared.apiKey(for: provider) ?? ""
        apiKeyHiddenField?.stringValue = key
        apiKeyVisibleField?.stringValue = key
        apiKeyVisible = false
        if let eyeBtn = apiKeyEyeButton {
            eyeBtn.title = "👁️"
        }
    }

    // MARK: - Tab 1: General

    private func buildGeneralTab(size: NSSize) -> NSView {
        let v = NSView(frame: NSRect(origin: .zero, size: size))
        let w = size.width

        // Provider selector
        let providerTitle = NSTextField(labelWithString: "AI 模型提供商：")
        providerTitle.frame = NSRect(x: 4, y: size.height - 28, width: w - 8, height: 18)
        providerTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        v.addSubview(providerTitle)

        let popup = NSPopUpButton(frame: NSRect(x: 4, y: size.height - 54, width: w - 8, height: 24), pullsDown: false)
        for provider in AIProvider.allCases {
            popup.addItem(withTitle: provider.displayName)
        }
        if let idx = AIProvider.allCases.firstIndex(of: SettingsManager.shared.apiProvider) {
            popup.selectItem(at: idx)
        }
        popup.target = self
        popup.action = #selector(providerChanged(_:))
        v.addSubview(popup)
        providerPopup = popup

        // API provider card (scrollable)
        let scrollView = NSScrollView(frame: NSRect(x: 4, y: 48, width: w - 8, height: size.height - 110))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        v.addSubview(scrollView)

        let provider = SettingsManager.shared.apiProvider
        let card = buildProviderCard(for: provider, width: w - 8)
        providerCardView = card
        providerCardHeight = card.frame.height
        card.frame.size.height = max(card.frame.height, scrollView.contentSize.height)
        scrollView.documentView = card
        return v
    }

    private func buildProviderCard(for provider: AIProvider, width w: CGFloat) -> NSView {
        let settings = SettingsManager.shared
        var y: CGFloat = 160

        let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: 320))
        let descLabel = NSTextField(labelWithString: provider == .ollama
            ? "Ollama 无需注册，本地运行即可"
            : "注册地址：\(provider.registerURL)")
        descLabel.frame = NSRect(x: 4, y: 180, width: w - 8, height: 18)
        descLabel.font = .systemFont(ofSize: 12, weight: .regular)
        descLabel.textColor = .secondaryLabelColor
        v.addSubview(descLabel)

        if provider.needsAPIKey {
            let keyTitle = NSTextField(labelWithString: "API Key：")
            keyTitle.frame = NSRect(x: 4, y: 146, width: w - 8, height: 18)
            keyTitle.font = .systemFont(ofSize: 12, weight: .semibold)
            v.addSubview(keyTitle)

            // Hidden secure field
            let hiddenField = PasteSecureTextField(frame: NSRect(x: 4, y: 116, width: w - 40, height: 26))
            hiddenField.placeholderString = "输入 API Key..."
            hiddenField.isBordered = true
            hiddenField.bezelStyle = .roundedBezel
            v.addSubview(hiddenField)
            apiKeyHiddenField = hiddenField

            // Visible field
            let visibleField = PasteTextField(frame: NSRect(x: 4, y: 116, width: w - 40, height: 26))
            visibleField.placeholderString = "输入 API Key..."
            visibleField.isBordered = true
            visibleField.bezelStyle = .roundedBezel
            visibleField.isHidden = true
            v.addSubview(visibleField)
            apiKeyVisibleField = visibleField

            // Eye toggle button
            let eyeBtn = NSButton(title: "👁️", target: self, action: #selector(toggleKeyVisibility))
            eyeBtn.frame = NSRect(x: w - 34, y: 116, width: 28, height: 26)
            eyeBtn.bezelStyle = .roundRect
            eyeBtn.isBordered = false
            v.addSubview(eyeBtn)
            apiKeyEyeButton = eyeBtn

            // Test button
            let testBtn = NSButton(title: "测试连接", target: self, action: #selector(testAPIKeyConnection))
            testBtn.frame = NSRect(x: 4, y: 78, width: 100, height: 26)
            testBtn.bezelStyle = .rounded
            v.addSubview(testBtn)

            let testStatus = NSTextField(labelWithString: "")
            testStatus.frame = NSRect(x: 112, y: 82, width: w - 120, height: 18)
            testStatus.font = .systemFont(ofSize: 11)
            testStatus.textColor = .secondaryLabelColor
            testStatus.lineBreakMode = .byWordWrapping
            v.addSubview(testStatus)
            testStatusLabel = testStatus

            y = 60
        } else {
            // Ollama 无需 API Key
            let noKeyLabel = NSTextField(labelWithString: "Ollama 运行在本地，无需 API Key。")
            noKeyLabel.frame = NSRect(x: 4, y: y, width: w - 8, height: 18)
            noKeyLabel.font = .systemFont(ofSize: 12, weight: .medium)
            noKeyLabel.textColor = .secondaryLabelColor
            v.addSubview(noKeyLabel)
            y -= 28
        }

        // --- 分隔线 ---
        let sep1 = NSBox(frame: NSRect(x: 4, y: y, width: w - 8, height: 1))
        sep1.boxType = .separator
        v.addSubview(sep1)
        y -= 16

        // --- 自定义 Endpoint（OpenAI-Compatible 和 Ollama） ---
        if provider.needsCustomEndpoint {
            let epTitle = NSTextField(labelWithString: "API 地址（Endpoint）：")
            epTitle.frame = NSRect(x: 4, y: y, width: w - 8, height: 18)
            epTitle.font = .systemFont(ofSize: 12, weight: .semibold)
            v.addSubview(epTitle)
            y -= 22

            let epField = PasteTextField(frame: NSRect(x: 4, y: y, width: w - 8, height: 26))
            epField.placeholderString = provider == .ollama
                ? "http://localhost:11434/v1/chat/completions"
                : "https://your-api.com/v1/chat/completions"
            epField.stringValue = settings.customEndpoint ?? provider.endpoint
            epField.isBordered = true
            epField.bezelStyle = .roundedBezel
            v.addSubview(epField)
            self.customEndpointField = epField
            y -= 40
        }

        // --- 自定义 Model ---
        if provider.needsCustomModel {
            let mdlTitle = NSTextField(labelWithString: "模型名称（Model）：")
            mdlTitle.frame = NSRect(x: 4, y: y, width: w - 8, height: 18)
            mdlTitle.font = .systemFont(ofSize: 12, weight: .semibold)
            v.addSubview(mdlTitle)
            y -= 22

            let mdlField = PasteTextField(frame: NSRect(x: 4, y: y, width: w - 8, height: 26))
            mdlField.placeholderString = provider == .ollama ? "llama3.2" : "gpt-3.5-turbo"
            let currentModel: String
            if provider == .ollama {
                currentModel = settings.ollamaModel ?? provider.defaultModel
            } else {
                currentModel = settings.customModel ?? provider.defaultModel
            }
            mdlField.stringValue = currentModel
            mdlField.isBordered = true
            mdlField.bezelStyle = .roundedBezel
            v.addSubview(mdlField)
            customModelField = mdlField
            y -= 40
        }

        // 确保卡片高度足够
        if y < 0 {
            v.frame.size.height += abs(y) + 20
        }

        return v
    }

    @objc private func toggleKeyVisibility() {
        guard let hidden = apiKeyHiddenField, let visible = apiKeyVisibleField, let eye = apiKeyEyeButton else { return }
        apiKeyVisible.toggle()
        if apiKeyVisible {
            visible.stringValue = hidden.stringValue
            hidden.isHidden = true
            visible.isHidden = false
            eye.title = "🔒"
        } else {
            hidden.stringValue = visible.stringValue
            visible.isHidden = true
            hidden.isHidden = false
            eye.title = "👁️"
        }
    }

    @objc private func testAPIKeyConnection() {
        let settings = SettingsManager.shared
        let provider = settings.apiProvider

        // 优先读取输入框中的 Key（用户刚粘贴的），fallback 到 Keychain 已保存的
        let key: String
        let fieldKey = activeApiKeyFieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fieldKey.isEmpty {
            key = fieldKey
        } else if let savedKey = settings.activeApiKey, !savedKey.isEmpty {
            key = savedKey
        } else {
            testStatusLabel?.stringValue = "请先输入 API Key"
            testStatusLabel?.textColor = .systemRed
            return
        }

        testStatusLabel?.stringValue = "测试中..."
        testStatusLabel?.textColor = .secondaryLabelColor

        guard let url = URL(string: provider.endpoint) else {
            testStatusLabel?.stringValue = "无效的 API 地址"
            testStatusLabel?.textColor = .systemRed
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        let body: [String: Any] = ["model": provider.defaultModel, "messages": [["role": "user", "content": "hi"]], "max_tokens": 1]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        switch provider {
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .googleAI:
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        default:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.testStatusLabel?.stringValue = "连接失败: \(error.localizedDescription)"
                    self?.testStatusLabel?.textColor = .systemRed
                    return
                }
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 || http.statusCode == 401 || http.statusCode == 403 {
                        self?.testStatusLabel?.stringValue = "连接成功 (HTTP \(http.statusCode))"
                        self?.testStatusLabel?.textColor = .systemGreen
                    } else {
                        self?.testStatusLabel?.stringValue = "服务器返回 HTTP \(http.statusCode)"
                        self?.testStatusLabel?.textColor = .systemOrange
                    }
                }
            }
        }.resume()
    }

    // MARK: - Tab 2: Hotkeys

    private func buildHotkeysTab(size: NSSize) -> NSView {
        let v = NSView(frame: NSRect(origin: .zero, size: size))
        let w = size.width
        let y0 = size.height - 30

        // ---- 1. Screenshot hotkey ----
        let titleLabel = NSTextField(labelWithString: "📸 截图翻译快捷键")
        titleLabel.frame = NSRect(x: 20, y: y0, width: 300, height: 22)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        v.addSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: "框选屏幕区域 → OCR 识别 → AI 翻译")
        descLabel.frame = NSRect(x: 20, y: y0 - 24, width: w - 40, height: 16)
        descLabel.font = .systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        v.addSubview(descLabel)

        let currentDisplay = SettingsManager.shared.hotkeyDisplay
        let recordBtn = NSButton(title: "    \(currentDisplay)    ", target: screenshotRecorder, action: #selector(HotkeyRecorder.start))
        recordBtn.frame = NSRect(x: 20, y: y0 - 80, width: 180, height: 42)
        recordBtn.bezelStyle = .rounded
        recordBtn.font = .systemFont(ofSize: 20, weight: .medium)
        v.addSubview(recordBtn)
        screenshotRecorder.recordBtn = recordBtn

        let statusLabel = NSTextField(labelWithString: "点击上方按钮开始录制新快捷键")
        statusLabel.frame = NSRect(x: 210, y: y0 - 70, width: w - 230, height: 30)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        v.addSubview(statusLabel)
        screenshotRecorder.statusLabel = statusLabel

        // ---- 2. Selection hotkey ----
        let selY = y0 - 150
        let sTitle = NSTextField(labelWithString: "📝 划词翻译快捷键")
        sTitle.frame = NSRect(x: 20, y: selY, width: 300, height: 22)
        sTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        v.addSubview(sTitle)

        let sDesc = NSTextField(labelWithString: "先选中文字，再按快捷键 → 直接 AI 翻译（无需截图+OCR）")
        sDesc.frame = NSRect(x: 20, y: selY - 24, width: w - 40, height: 16)
        sDesc.font = .systemFont(ofSize: 11)
        sDesc.textColor = .secondaryLabelColor
        v.addSubview(sDesc)

        let selDisplay = SettingsManager.shared.selectionHotkeyDisplay
        let selRecordBtn = NSButton(title: "    \(selDisplay)    ", target: selectionRecorder, action: #selector(HotkeyRecorder.start))
        selRecordBtn.frame = NSRect(x: 20, y: selY - 80, width: 180, height: 42)
        selRecordBtn.bezelStyle = .rounded
        selRecordBtn.font = .systemFont(ofSize: 20, weight: .medium)
        v.addSubview(selRecordBtn)
        selectionRecorder.recordBtn = selRecordBtn

        let selStatus = NSTextField(labelWithString: "点击上方按钮开始录制新快捷键")
        selStatus.frame = NSRect(x: 210, y: selY - 70, width: w - 230, height: 30)
        selStatus.font = .systemFont(ofSize: 12)
        selStatus.textColor = .secondaryLabelColor
        selStatus.lineBreakMode = .byWordWrapping
        v.addSubview(selStatus)
        selectionRecorder.statusLabel = selStatus

        // ---- 3. Close panel hotkey ----
        let escY = selY - 160
        let escTitle = NSTextField(labelWithString: "🚪 关闭翻译面板")
        escTitle.frame = NSRect(x: 20, y: escY, width: 300, height: 22)
        escTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        v.addSubview(escTitle)

        let escDesc = NSTextField(labelWithString: "翻译浮动面板显示时，按下自定义快捷键即可关闭")
        escDesc.frame = NSRect(x: 20, y: escY - 24, width: w - 40, height: 16)
        escDesc.font = .systemFont(ofSize: 11)
        escDesc.textColor = .secondaryLabelColor
        v.addSubview(escDesc)

        let closePanelBtn = NSButton(title: "  \(SettingsManager.shared.closePanelHotkeyDisplay)  ", target: closePanelRecorder, action: #selector(HotkeyRecorder.start))
        closePanelBtn.frame = NSRect(x: 20, y: escY - 65, width: 180, height: 32)
        closePanelBtn.font = .systemFont(ofSize: 18, weight: .medium)
        closePanelBtn.bezelStyle = .rounded
        v.addSubview(closePanelBtn)
        closePanelRecorder.recordBtn = closePanelBtn

        let escStatus = NSTextField(labelWithString: "点击上方按钮开始录制新快捷键")
        escStatus.frame = NSRect(x: 210, y: escY - 60, width: w - 230, height: 30)
        escStatus.font = .systemFont(ofSize: 12)
        escStatus.textColor = .secondaryLabelColor
        escStatus.lineBreakMode = .byWordWrapping
        v.addSubview(escStatus)
        closePanelRecorder.statusLabel = escStatus

        // ---- 4. Toggle panel position ----
        let toggleY = escY - 140
        let toggleTitle = NSTextField(labelWithString: "↔️ 切换弹窗位置")
        toggleTitle.frame = NSRect(x: 20, y: toggleY, width: 300, height: 22)
        toggleTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        v.addSubview(toggleTitle)

        let toggleDesc = NSTextField(labelWithString: "翻译浮动面板显示时，按快捷键将弹窗切换到屏幕另一侧")
        toggleDesc.frame = NSRect(x: 20, y: toggleY - 24, width: w - 40, height: 16)
        toggleDesc.font = .systemFont(ofSize: 11)
        toggleDesc.textColor = .secondaryLabelColor
        v.addSubview(toggleDesc)

        let togglePanelBtn = NSButton(title: "  \(SettingsManager.shared.togglePanelHotkeyDisplay)  ", target: togglePanelRecorder, action: #selector(HotkeyRecorder.start))
        togglePanelBtn.frame = NSRect(x: 20, y: toggleY - 65, width: 180, height: 32)
        togglePanelBtn.font = .systemFont(ofSize: 18, weight: .medium)
        togglePanelBtn.bezelStyle = .rounded
        v.addSubview(togglePanelBtn)
        togglePanelRecorder.recordBtn = togglePanelBtn

        let toggleStatus = NSTextField(labelWithString: "点击上方按钮开始录制新快捷键")
        toggleStatus.frame = NSRect(x: 210, y: toggleY - 60, width: w - 230, height: 30)
        toggleStatus.font = .systemFont(ofSize: 12)
        toggleStatus.textColor = .secondaryLabelColor
        toggleStatus.lineBreakMode = .byWordWrapping
        v.addSubview(toggleStatus)
        togglePanelRecorder.statusLabel = toggleStatus

        // ---- 统一提示 ----
        let infoLabel = NSTextField(labelWithString: """
        💡 提示：
        • 截图翻译：任意位置按下快捷键 → 框选区域 → 自动翻译
        • 划词翻译：先选中文字 → 按下快捷键 → 自动翻译（更快捷）
        • 关闭面板：翻译浮动面板显示时，按下自定义快捷键即可关闭
        • 切换弹窗：翻译浮动面板显示时，按下快捷键可在左右侧之间切换
        """)
        infoLabel.frame = NSRect(x: 20, y: 5, width: w - 40, height: 80)
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.lineBreakMode = .byWordWrapping
        v.addSubview(infoLabel)

        return v
    }

    // MARK: - Save

    @objc private func saveAllSettings() {
        let settings = SettingsManager.shared

        let keyStr = activeApiKeyFieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        logi("保存设置: provider=\(settings.apiProvider.rawValue), keyLen=\(keyStr.count)")
        if !keyStr.isEmpty {
            settings.setApiKey(keyStr, for: settings.apiProvider)
        } else {
            settings.setApiKey(nil, for: settings.apiProvider)
        }

        if let ep = customEndpointField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !ep.isEmpty {
            guard AIProvider.isValidEndpoint(ep) else {
                let alert = NSAlert()
                alert.messageText = "无效的自定义接口地址"
                alert.informativeText = "仅支持 HTTPS 地址或以 localhost / 192.168.x.x / 10.x.x.x 开头的 HTTP 地址。\n当前输入：\(ep)"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "确定")
                alert.runModal()
                return
            }
            settings.customEndpoint = ep
        }
        if let mdl = customModelField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !mdl.isEmpty {
            if settings.apiProvider == .ollama {
                settings.ollamaModel = mdl
            } else {
                settings.customModel = mdl
            }
        }

        if screenshotRecorder.recordedKeyCode != 0 {
            settings.hotkeyKeyCode = screenshotRecorder.recordedKeyCode
            settings.hotkeyModifiers = screenshotRecorder.recordedModifiers
            settings.hotkeyDisplay = hotkeyDisplayString(keyCode: screenshotRecorder.recordedKeyCode, modifiers: screenshotRecorder.recordedModifiers)
        }

        if selectionRecorder.recordedKeyCode != 0 {
            settings.selectionHotkeyKeyCode = selectionRecorder.recordedKeyCode
            settings.selectionHotkeyModifiers = selectionRecorder.recordedModifiers
            settings.selectionHotkeyDisplay = hotkeyDisplayString(keyCode: selectionRecorder.recordedKeyCode, modifiers: selectionRecorder.recordedModifiers)
        }

        if closePanelRecorder.recordedKeyCode != 0 {
            settings.closePanelHotkeyKeyCode = closePanelRecorder.recordedKeyCode
            settings.closePanelHotkeyModifiers = closePanelRecorder.recordedModifiers
            settings.closePanelHotkeyDisplay = hotkeyDisplayString(keyCode: closePanelRecorder.recordedKeyCode, modifiers: closePanelRecorder.recordedModifiers)
        }

        if togglePanelRecorder.recordedKeyCode != 0 {
            settings.togglePanelHotkeyKeyCode = togglePanelRecorder.recordedKeyCode
            settings.togglePanelHotkeyModifiers = togglePanelRecorder.recordedModifiers
            settings.togglePanelHotkeyDisplay = hotkeyDisplayString(keyCode: togglePanelRecorder.recordedKeyCode, modifiers: togglePanelRecorder.recordedModifiers)
        }

        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.reregisterHotkey()
        }

        if let template = templateTextView?.string, !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.systemPrompt = template
        }

        logi("设置已保存")
    }

    @objc private func resetAll() {
        let alert = NSAlert()
        alert.messageText = "恢复默认设置"
        alert.informativeText = "将恢复 API Key 以外的所有设置为默认值，包括快捷键和翻译模板。确定继续？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "恢复默认")
        alert.addButton(withTitle: "取消")
        alert.layout()
        alert.window.level = .floating
        alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if alert.runModal() != .alertFirstButtonReturn { return }

        let settings = SettingsManager.shared
        settings.systemPrompt = settings.defaultPrompt
        settings.hotkeyKeyCode = DEFAULT_HOTKEY_KEYCODE
        settings.hotkeyModifiers = Int(controlKey)
        settings.hotkeyDisplay = "⌃T"

        settings.selectionHotkeyKeyCode = DEFAULT_SELECTION_HOTKEY_KEYCODE
        settings.selectionHotkeyModifiers = Int(controlKey | shiftKey)
        settings.selectionHotkeyDisplay = "⇧⌃T"

        settings.closePanelHotkeyKeyCode = 0x35
        settings.closePanelHotkeyModifiers = 0
        settings.closePanelHotkeyDisplay = "Esc"

        settings.togglePanelHotkeyKeyCode = 0x32
        settings.togglePanelHotkeyModifiers = 0
        settings.togglePanelHotkeyDisplay = "`"

        screenshotRecorder.recordBtn?.title = "    ⌃T    "
        screenshotRecorder.statusLabel?.stringValue = "已恢复默认快捷键 ⌃T"
        selectionRecorder.recordBtn?.title = "    ⇧⌃T    "
        selectionRecorder.statusLabel?.stringValue = "已恢复默认快捷键 ⇧⌃T"
        closePanelRecorder.recordBtn?.title = "    Esc    "
        closePanelRecorder.statusLabel?.stringValue = "已恢复默认快捷键 Esc"
        togglePanelRecorder.recordBtn?.title = "    `    "
        togglePanelRecorder.statusLabel?.stringValue = "已恢复默认快捷键 `"

        screenshotRecorder.reset()
        selectionRecorder.reset()
        closePanelRecorder.reset()
        togglePanelRecorder.reset()
    }

    // MARK: - 提供商切换

    @objc private func providerChanged(_ sender: NSPopUpButton) {
        guard let idx = AIProvider.allCases.firstIndex(where: { sender.titleOfSelectedItem == $0.displayName }) else { return }
        let newProvider = AIProvider.allCases[idx]
        let settings = SettingsManager.shared

        let currentKey = activeApiKeyFieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentKey.isEmpty {
            settings.setApiKey(currentKey, for: settings.apiProvider)
        }

        if let ep = customEndpointField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !ep.isEmpty {
            if AIProvider.isValidEndpoint(ep) {
                settings.customEndpoint = ep
            } else {
                logi("providerChanged：拒绝保存非法 endpoint: \(ep.prefix(50))")
            }
        }
        if let mdl = customModelField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !mdl.isEmpty {
            if settings.apiProvider == .ollama {
                settings.ollamaModel = mdl
            } else {
                settings.customModel = mdl
            }
        }

        settings.apiProvider = newProvider

        guard let scrollView = providerCardView?.enclosingScrollView else { return }
        let cardWidth = scrollView.contentSize.width

        let card = buildProviderCard(for: newProvider, width: cardWidth)
        providerCardView = card
        providerCardHeight = card.frame.height
        card.frame.size.height = max(card.frame.height, scrollView.contentSize.height)
        scrollView.documentView = card

        loadKey(for: newProvider)
    }

    // MARK: - Tab 3: 翻译模板

    private func buildTemplateTab(size: NSSize) -> NSView {
        let v = NSView(frame: NSRect(origin: .zero, size: size))
        let w = size.width

        let titleLabel = NSTextField(labelWithString: "翻译提示词模板（可编辑）")
        titleLabel.frame = NSRect(x: 20, y: size.height - 30, width: 400, height: 22)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        v.addSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: "编辑翻译指令与输出格式。修改后点击窗口底部「保存并应用」使更改生效。")
        descLabel.frame = NSRect(x: 20, y: size.height - 52, width: w - 40, height: 16)
        descLabel.font = .systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        v.addSubview(descLabel)

        let tvH = size.height - 260
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 190, width: w - 40, height: tvH))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true

        let textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.isEditable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isRichText = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = self
        textView.string = SettingsManager.shared.systemPrompt
        scrollView.documentView = textView
        v.addSubview(scrollView)
        templateTextView = textView

        let previewTitle = NSTextField(labelWithString: "实时预览：")
        previewTitle.frame = NSRect(x: 20, y: 170, width: 200, height: 18)
        previewTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        v.addSubview(previewTitle)

        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: NSRect(x: 20, y: 10, width: w - 40, height: 155), configuration: config)
        wv.loadHTMLString(templatePreviewHTML(), baseURL: nil)
        wv.layer?.borderWidth = 1
        wv.layer?.borderColor = NSColor.separatorColor.cgColor
        v.addSubview(wv)
        templatePreviewWebView = wv

        return v
    }

    private func templatePreviewHTML() -> String {
        """
        <html><head><style>
        body{font-family:-apple-system;padding:12px;color:#ddd;background:#1e1e1e;margin:0;}
        h2{font-size:14px;margin-top:8px;margin-bottom:4px;color:#6cf;}
        p{margin:2px 0;}
        strong{color:#f9a;}
        </style></head><body><p style='color:#999;font-size:11px;'>
        提示词将在翻译时附加到 AI 请求中...</p></body></html>
        """
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

extension SettingsWindowController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView, tv == templateTextView else { return }
        templatePreviewWebView?.loadHTMLString(templatePreviewHTML(), baseURL: nil)
    }
}

// MARK: - 热键录制器（消除 4 份重复代码）

final class HotkeyRecorder: NSObject {
    weak var recordBtn: NSButton?
    weak var statusLabel: NSTextField?
    var isRecording = false
    var recordedKeyCode = 0
    var recordedModifiers = 0
    private var monitor: Any?

    let allowedSoloKeyCodes: Set<Int>
    let soloKeyHint: String
    let defaultDisplay: () -> String

    init(allowedSoloKeyCodes: Set<Int>, soloKeyHint: String, defaultDisplay: @escaping () -> String) {
        self.allowedSoloKeyCodes = allowedSoloKeyCodes
        self.soloKeyHint = soloKeyHint
        self.defaultDisplay = defaultDisplay
    }

    @objc func start() {
        guard !HotkeyRecorder.anyRecording else { return }
        isRecording = true
        recordedKeyCode = 0
        recordedModifiers = 0

        recordBtn?.title = "  ... 按下组合键 ...  "
        recordBtn?.bezelColor = .systemOrange
        statusLabel?.stringValue = "请按下组合键..."

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecording else { return event }
            self.record(event: event)
            return nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, self.isRecording else { return }
            self.cancel()
        }
    }

    private func record(event: NSEvent) {
        let carbonModifiers = cocoaToCarbonModifiers(event.modifierFlags)
        let keyCode = Int(event.keyCode)

        guard allowedSoloKeyCodes.contains(keyCode) || hotkeyHasRequiredModifiers(carbonModifiers) else {
            cancel()
            statusLabel?.stringValue = "❌ 单个字母不能作为快捷键\n请同时按住 ⌘ / ⌥ / ⌃ / ⇧ 之一再按字母"
            recordBtn?.bezelColor = .systemRed
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.recordBtn?.bezelColor = nil
            }
            return
        }

        recordedKeyCode = keyCode
        recordedModifiers = carbonModifiers
        isRecording = false

        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }

        let display = hotkeyDisplayString(keyCode: recordedKeyCode, modifiers: recordedModifiers)
        recordBtn?.title = "    \(display)    "
        recordBtn?.bezelColor = .systemGreen
        var status = "✅ 已录制：\(display)\n点击「保存并应用」使快捷键生效"
        if let conflict = checkSystemHotkeyConflict(modifiers: recordedModifiers, keyCode: recordedKeyCode) {
            status += "\n⚠️ 可能与系统快捷键冲突：\(conflict)"
            recordBtn?.bezelColor = .systemOrange
        }
        statusLabel?.stringValue = status

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.recordBtn?.bezelColor = nil
        }
    }

    private func cancel() {
        isRecording = false
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        let display = defaultDisplay()
        recordBtn?.title = "    \(display)    "
        recordBtn?.bezelColor = nil
        statusLabel?.stringValue = "录制超时，请重试"
    }

    func reset() {
        recordedKeyCode = 0
        recordedModifiers = 0
    }

    static var anyRecording: Bool {
        let ctrl = SettingsWindowController.shared
        return ctrl.screenshotRecorder.isRecording
            || ctrl.selectionRecorder.isRecording
            || ctrl.closePanelRecorder.isRecording
            || ctrl.togglePanelRecorder.isRecording
    }
}