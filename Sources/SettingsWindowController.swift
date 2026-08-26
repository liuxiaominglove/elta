import Cocoa
import Carbon
import WebKit

// MARK: - 连接测试结果分类

enum ConnectionResult: Equatable {
    case success(Int)
    case authFailure(Int)
    case serverError(Int)

    static func classify(_ code: Int) -> ConnectionResult {
        if code >= 200 && code < 300 { return .success(code) }
        if code == 401 || code == 403 { return .authFailure(code) }
        return .serverError(code)
    }
}

// MARK: - 通用标签页卡片布局

struct ProviderCardLayout {
    let registerLabelY: CGFloat
    let modelTitleY: CGFloat
    let modelPopupY: CGFloat
    let keyTitleY: CGFloat
    let keyFieldY: CGFloat
    let testButtonY: CGFloat
}

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
    private var customModelPopup: NSPopUpButton?
    private var providerDescLabel: NSTextField?
    private var testStatusLabel: NSTextField?
    private var providerCardView: NSView?          // 当前提供商的卡片容器
    private var providerCardHeight: CGFloat = 0
    private var cardLayout: ProviderCardLayout?    // 通用标签页卡片布局（模型严格居中）

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
    let splitRecorder = HotkeyRecorder(
        allowedSoloKeyCodes: [],
        soloKeyHint: "",
        defaultDisplay: { SettingsManager.shared.splitHotkeyDisplay }
    )

    // Tab 3: 翻译模板
    private var templateTextView: NSTextView?

    // Tab 2: 默认优先弹窗模式（整段 / 拆分）
    private var defaultSplitSeg: NSSegmentedControl?

    func show() {
        if let w = window { w.close(); window = nil }

        let ww: CGFloat = 640, hh: CGFloat = 880
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

        // 恢复默认按钮——窗口底部，保存按钮右侧，所有标签页通用（恢复 API Key 以外的设置）
        let resetBtn = NSButton(title: "恢复默认", target: self, action: #selector(resetAll))
        resetBtn.frame = NSRect(x: 16 + 120 + 8, y: 12, width: 120, height: 32)
        resetBtn.bezelStyle = .rounded
        win.contentView?.addSubview(resetBtn)

        // 版本号——底部居中，极简不干扰 UI
        let versionLabel = NSTextField(labelWithString: "ELTA \(APP_FULL_VERSION)")
        versionLabel.frame = NSRect(x: (ww - 160) / 2, y: 0, width: 160, height: 14)
        versionLabel.alignment = .center
        versionLabel.font = .systemFont(ofSize: 10, weight: .regular)
        versionLabel.textColor = .secondaryLabelColor
        win.contentView?.addSubview(versionLabel)

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

    /// 当前模型控件值：下拉框优先；无下拉框则返回 nil
    private var activeModelValue: String? {
        if let popup = customModelPopup, let title = popup.titleOfSelectedItem {
            return title
        }
        return nil
    }

    private func loadKey(for provider: AIProvider) {
        let key = SettingsManager.shared.apiKey(for: provider) ?? ""
        apiKeyHiddenField?.stringValue = key
        apiKeyVisibleField?.stringValue = key
        apiKeyVisible = false
        apiKeyHiddenField?.isHidden = false
        apiKeyVisibleField?.isHidden = true
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

        // 计算卡片布局：模型与 API Key 按给定底边 y 摆放
        self.cardLayout = Self.computeProviderCardLayout(
            modelPopupY: 549,
            keyFieldY: 415,
            cardHeight: size.height - 110)

        let provider = SettingsManager.shared.apiProvider
        let card = buildProviderCard(for: provider, width: w - 8)
        providerCardView = card
        providerCardHeight = card.frame.height
        card.frame.size.height = max(card.frame.height, scrollView.contentSize.height)
        scrollView.documentView = card

        // 匿名使用统计开关
        let telemetryCheck = NSButton(checkboxWithTitle: "参与匿名使用统计", target: self, action: #selector(telemetryToggled(_:)))
        telemetryCheck.state = SettingsManager.shared.telemetryEnabled ? .on : .off
        telemetryCheck.frame = NSRect(x: 4, y: 22, width: 220, height: 20)
        telemetryCheck.font = .systemFont(ofSize: 12)
        v.addSubview(telemetryCheck)

        let telemetryHint = NSTextField(labelWithString: "仅上报随机匿名标识统计每日使用人数，不含任何个人信息")
        telemetryHint.frame = NSRect(x: 24, y: 4, width: w - 28, height: 14)
        telemetryHint.font = .systemFont(ofSize: 10)
        telemetryHint.textColor = .secondaryLabelColor
        v.addSubview(telemetryHint)

        return v
    }

    @objc private func telemetryToggled(_ sender: NSButton) {
        SettingsManager.shared.telemetryEnabled = (sender.state == .on)
    }

    /// 计算通用标签页卡片内各控件的 y 坐标（非翻转坐标系，y 向上）。
    /// 模型下拉框与 API Key 输入框按给定的底边 y 摆放，标题自动跟随、测试按钮随 API Key 移动。
    static func computeProviderCardLayout(modelPopupY: CGFloat,
                                          keyFieldY: CGFloat,
                                          cardHeight: CGFloat) -> ProviderCardLayout {
        let labelHeight: CGFloat = 18
        let fieldHeight: CGFloat = 26
        let gap: CGFloat = 4
        let topMargin: CGFloat = 8
        let testButtonOffset: CGFloat = 38

        let registerLabelY = cardHeight - topMargin - labelHeight
        let modelTitleY = modelPopupY + fieldHeight + gap
        let keyTitleY = keyFieldY + fieldHeight + gap
        let testButtonY = keyFieldY - testButtonOffset

        return ProviderCardLayout(
            registerLabelY: registerLabelY,
            modelTitleY: modelTitleY,
            modelPopupY: modelPopupY,
            keyTitleY: keyTitleY,
            keyFieldY: keyFieldY,
            testButtonY: testButtonY)
    }

    private func buildProviderCard(for provider: AIProvider, width w: CGFloat) -> NSView {
        let settings = SettingsManager.shared
        let layout = cardLayout ?? Self.computeProviderCardLayout(
            modelPopupY: 549, keyFieldY: 415, cardHeight: 666)

        let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: 320))
        let descLabel = NSTextField(labelWithString: "注册地址：\(provider.registerURL)")
        descLabel.frame = NSRect(x: 4, y: layout.registerLabelY, width: w - 8, height: 18)
        descLabel.font = .systemFont(ofSize: 12, weight: .regular)
        descLabel.textColor = .secondaryLabelColor
        v.addSubview(descLabel)

        // --- 模型选择（预设下拉框） ---
        let models = provider.availableModels
        let mdlTitle = NSTextField(labelWithString: "模型（Model）：")
        mdlTitle.frame = NSRect(x: 4, y: layout.modelTitleY, width: w - 8, height: 18)
        mdlTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        v.addSubview(mdlTitle)

        let popup = NSPopUpButton(frame: NSRect(x: 4, y: layout.modelPopupY, width: w - 8, height: 26), pullsDown: false)
        for m in models { popup.addItem(withTitle: m) }
        let current = settings.modelOverride(for: provider) ?? provider.defaultModel
        if let idx = models.firstIndex(of: current) {
            popup.selectItem(at: idx)
        } else {
            popup.selectItem(at: 0)
        }
        v.addSubview(popup)
        customModelPopup = popup

        // --- API Key ---
        let keyTitle = NSTextField(labelWithString: "API Key：")
        keyTitle.frame = NSRect(x: 4, y: layout.keyTitleY, width: w - 8, height: 18)
        keyTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        v.addSubview(keyTitle)

        // Hidden secure field
        let hiddenField = PasteSecureTextField(frame: NSRect(x: 4, y: layout.keyFieldY, width: w - 40, height: 26))
        hiddenField.placeholderString = "输入 API Key..."
        hiddenField.isBordered = true
        hiddenField.bezelStyle = .roundedBezel
        v.addSubview(hiddenField)
        apiKeyHiddenField = hiddenField

        // Visible field
        let visibleField = PasteTextField(frame: NSRect(x: 4, y: layout.keyFieldY, width: w - 40, height: 26))
        visibleField.placeholderString = "输入 API Key..."
        visibleField.isBordered = true
        visibleField.bezelStyle = .roundedBezel
        visibleField.isHidden = true
        v.addSubview(visibleField)
        apiKeyVisibleField = visibleField

        // Eye toggle button
        let eyeBtn = NSButton(title: "👁️", target: self, action: #selector(toggleKeyVisibility))
        eyeBtn.frame = NSRect(x: w - 34, y: layout.keyFieldY, width: 28, height: 26)
        eyeBtn.bezelStyle = .roundRect
        eyeBtn.isBordered = false
        v.addSubview(eyeBtn)
        apiKeyEyeButton = eyeBtn

        // Test button
        let testBtn = NSButton(title: "测试连接", target: self, action: #selector(testAPIKeyConnection))
        testBtn.frame = NSRect(x: 4, y: layout.testButtonY, width: 100, height: 26)
        testBtn.bezelStyle = .rounded
        v.addSubview(testBtn)

        let testStatus = NSTextField(labelWithString: "")
        testStatus.frame = NSRect(x: 112, y: layout.testButtonY + 4, width: w - 120, height: 18)
        testStatus.font = .systemFont(ofSize: 11)
        testStatus.textColor = .secondaryLabelColor
        testStatus.lineBreakMode = .byWordWrapping
        v.addSubview(testStatus)
        testStatusLabel = testStatus

        // 修复负 y 布局：非翻转视图原点在左下，负 y 子视图会被裁剪不可见。
        // 把所有子视图上移使最小 y >= 0，并按内容顶高扩展卡片高度。
        let minY = v.subviews.map { $0.frame.minY }.min() ?? 0
        if minY < 0 {
            let shift = -minY
            for sv in v.subviews { sv.frame.origin.y += shift }
        }
        let maxTop = v.subviews.map { $0.frame.maxY }.max() ?? 0
        v.frame.size.height = max(v.frame.size.height, maxTop + 20)

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

    /// 解析「测试连接」实际应使用的 endpoint 与 model：
    /// 优先用输入框键入的模型（用户刚改、尚未保存），为空才回退到 provider 默认。
    static func resolveConnectionTarget(modelInput: String?, provider: AIProvider) -> (endpoint: String, model: String) {
        let endpoint = provider.endpoint
        let md = modelInput?.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = (md?.isEmpty == false) ? md! : provider.defaultModel
        return (endpoint, model)
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

        let target = Self.resolveConnectionTarget(
            modelInput: activeModelValue,
            provider: provider
        )

        guard let url = URL(string: target.endpoint) else {
            testStatusLabel?.stringValue = "无效的 API 地址"
            testStatusLabel?.textColor = .systemRed
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        let body: [String: Any] = ["model": target.model, "messages": [["role": "user", "content": "hi"]], "max_tokens": 1]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        // 捕获发起测试时的状态标签：切 provider 会重建卡片、重赋 testStatusLabel，
        // 若不捕获，迟到回调会把 A 的测试结果写进 B 的标签，造成假阳性「连接成功」。
        let statusLabel = testStatusLabel

        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    statusLabel?.stringValue = "连接失败: \(error.localizedDescription)"
                    statusLabel?.textColor = .systemRed
                    return
                }
                if let http = response as? HTTPURLResponse {
                    switch ConnectionResult.classify(http.statusCode) {
                    case .success(let code):
                        statusLabel?.stringValue = "连接成功 (HTTP \(code))"
                        statusLabel?.textColor = .systemGreen
                    case .authFailure(let code):
                        statusLabel?.stringValue = "API Key 无效 (HTTP \(code))"
                        statusLabel?.textColor = .systemRed
                    case .serverError(let code):
                        statusLabel?.stringValue = "服务器返回 HTTP \(code)"
                        statusLabel?.textColor = .systemOrange
                    }
                }
            }
        }.resume()
    }

    // MARK: - Tab 2: Hotkeys

    private func buildHotkeysTab(size: NSSize) -> NSView {
        // 内容比可视区略高，外包 NSScrollView 以容纳新增的「拆分翻译」快捷键行
        let contentHeight = size.height + 160
        let v = NSView(frame: NSRect(x: 0, y: 0, width: size.width, height: contentHeight))
        let w = size.width
        let y0 = contentHeight - 30

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
        statusLabel.frame = NSRect(x: 210, y: y0 - 88, width: w - 230, height: 48)
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
        selStatus.frame = NSRect(x: 210, y: selY - 88, width: w - 230, height: 48)
        selStatus.font = .systemFont(ofSize: 12)
        selStatus.textColor = .secondaryLabelColor
        selStatus.lineBreakMode = .byWordWrapping
        v.addSubview(selStatus)
        selectionRecorder.statusLabel = selStatus

        // ---- 3. Close panel hotkey ----
        let escY = selY - 175
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
        escStatus.frame = NSRect(x: 210, y: escY - 78, width: w - 230, height: 48)
        escStatus.font = .systemFont(ofSize: 12)
        escStatus.textColor = .secondaryLabelColor
        escStatus.lineBreakMode = .byWordWrapping
        v.addSubview(escStatus)
        closePanelRecorder.statusLabel = escStatus

        // ---- 4. Toggle panel position ----
        let toggleY = escY - 120
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
        toggleStatus.frame = NSRect(x: 210, y: toggleY - 78, width: w - 230, height: 48)
        toggleStatus.font = .systemFont(ofSize: 12)
        toggleStatus.textColor = .secondaryLabelColor
        toggleStatus.lineBreakMode = .byWordWrapping
        v.addSubview(toggleStatus)
        togglePanelRecorder.statusLabel = toggleStatus

        // ---- 5. Split translation hotkey ----
        let splitY = toggleY - 120
        let splitTitle = NSTextField(labelWithString: "🔀 拆分翻译")
        splitTitle.frame = NSRect(x: 20, y: splitY, width: 300, height: 22)
        splitTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        v.addSubview(splitTitle)

        let splitDesc = NSTextField(labelWithString: "翻译浮动面板显示时，按快捷键在「整段 / 拆分」之间切换")
        splitDesc.frame = NSRect(x: 20, y: splitY - 24, width: w - 40, height: 16)
        splitDesc.font = .systemFont(ofSize: 11)
        splitDesc.textColor = .secondaryLabelColor
        v.addSubview(splitDesc)

        let splitBtn = NSButton(title: "  \(SettingsManager.shared.splitHotkeyDisplay)  ", target: splitRecorder, action: #selector(HotkeyRecorder.start))
        splitBtn.frame = NSRect(x: 20, y: splitY - 65, width: 180, height: 32)
        splitBtn.font = .systemFont(ofSize: 18, weight: .medium)
        splitBtn.bezelStyle = .rounded
        v.addSubview(splitBtn)
        splitRecorder.recordBtn = splitBtn

        let splitStatus = NSTextField(labelWithString: "点击上方按钮开始录制新快捷键")
        splitStatus.frame = NSRect(x: 210, y: splitY - 78, width: w - 230, height: 48)
        splitStatus.font = .systemFont(ofSize: 12)
        splitStatus.textColor = .secondaryLabelColor
        splitStatus.lineBreakMode = .byWordWrapping
        v.addSubview(splitStatus)
        splitRecorder.statusLabel = splitStatus

        // ---- 6. 默认优先弹窗模式 ----
        let defaultSplitY = splitY - 135
        let defaultSplitTitle = NSTextField(labelWithString: "🎯 默认优先弹窗")
        defaultSplitTitle.frame = NSRect(x: 20, y: defaultSplitY, width: 300, height: 22)
        defaultSplitTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        v.addSubview(defaultSplitTitle)

        let defaultSplitDesc = NSTextField(labelWithString: "翻译完成后，优先显示「整段」还是「拆分」视图（内容不适合拆分时自动回退整段）")
        defaultSplitDesc.frame = NSRect(x: 20, y: defaultSplitY - 24, width: w - 40, height: 16)
        defaultSplitDesc.font = .systemFont(ofSize: 11)
        defaultSplitDesc.textColor = .secondaryLabelColor
        v.addSubview(defaultSplitDesc)

        let defaultSplitSeg = NSSegmentedControl(labels: ["整段", "拆分"], trackingMode: .selectOne,
                                                 target: nil, action: nil)
        defaultSplitSeg.frame = NSRect(x: 20, y: defaultSplitY - 55, width: 180, height: 28)
        defaultSplitSeg.segmentStyle = .rounded
        defaultSplitSeg.selectedSegment = SettingsManager.shared.defaultSplitMode ? 1 : 0
        v.addSubview(defaultSplitSeg)
        self.defaultSplitSeg = defaultSplitSeg

        // ---- 统一提示 ----
        let infoLabel = NSTextField(labelWithString: """
        💡 提示：
        • 截图翻译：任意位置按下快捷键 → 框选区域 → 自动翻译
        • 划词翻译：先选中文字 → 按下快捷键 → 自动翻译（更快捷）
        • 关闭面板：翻译浮动面板显示时，按下自定义快捷键即可关闭
        • 切换弹窗：翻译浮动面板显示时，按下快捷键可在左右侧之间切换
        • 拆分翻译：翻译浮动面板显示时，按快捷键可在「整段 / 拆分」之间切换
        """)
        infoLabel.frame = NSRect(x: 20, y: 10, width: w - 40, height: 96)
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.lineBreakMode = .byWordWrapping
        v.addSubview(infoLabel)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = v
        return scrollView
    }

    // MARK: - Save

    @objc private func saveAllSettings() {
        let settings = SettingsManager.shared

        // 二次确认：本次新录制的翻译热键若命中已知系统快捷键冲突，先让用户确认再保存
        let recorded: [(keyCode: Int?, modifiers: Int)] = [
            (screenshotRecorder.recordedKeyCode, screenshotRecorder.recordedModifiers),
            (selectionRecorder.recordedKeyCode, selectionRecorder.recordedModifiers),
        ]
        let conflicts = collectHotkeyConflicts(recorded)
        if !conflicts.isEmpty {
            let details = conflicts.map { "「\($0.display)」：\($0.reason)" }.joined(separator: "\n")
            let alert = NSAlert()
            alert.messageText = "快捷键可能与系统冲突"
            alert.informativeText = "以下快捷键在大多数应用中是常用功能：\n\n\(details)\n\n全局注册后，这些应用内按此键将触发翻译而非原功能。确定要使用吗？"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")
            if alert.runModal() != .alertFirstButtonReturn {
                return
            }
        }

        let keyStr = activeApiKeyFieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        logi("保存设置: provider=\(settings.apiProvider.rawValue), keyLen=\(keyStr.count)")
        if !keyStr.isEmpty {
            settings.setApiKey(keyStr, for: settings.apiProvider)
        } else {
            settings.setApiKey(nil, for: settings.apiProvider)
        }

        settings.setModelOverride(activeModelValue, for: settings.apiProvider)

        if let kc = screenshotRecorder.recordedKeyCode {
            settings.hotkeyKeyCode = kc
            settings.hotkeyModifiers = screenshotRecorder.recordedModifiers
            settings.hotkeyDisplay = hotkeyDisplayString(keyCode: kc, modifiers: screenshotRecorder.recordedModifiers)
        }

        if let kc = selectionRecorder.recordedKeyCode {
            settings.selectionHotkeyKeyCode = kc
            settings.selectionHotkeyModifiers = selectionRecorder.recordedModifiers
            settings.selectionHotkeyDisplay = hotkeyDisplayString(keyCode: kc, modifiers: selectionRecorder.recordedModifiers)
        }

        if let kc = closePanelRecorder.recordedKeyCode {
            settings.closePanelHotkeyKeyCode = kc
            settings.closePanelHotkeyModifiers = closePanelRecorder.recordedModifiers
            settings.closePanelHotkeyDisplay = hotkeyDisplayString(keyCode: kc, modifiers: closePanelRecorder.recordedModifiers)
        }

        if let kc = togglePanelRecorder.recordedKeyCode {
            settings.togglePanelHotkeyKeyCode = kc
            settings.togglePanelHotkeyModifiers = togglePanelRecorder.recordedModifiers
            settings.togglePanelHotkeyDisplay = hotkeyDisplayString(keyCode: kc, modifiers: togglePanelRecorder.recordedModifiers)
        }

        if let kc = splitRecorder.recordedKeyCode {
            settings.splitHotkeyKeyCode = kc
            settings.splitHotkeyModifiers = splitRecorder.recordedModifiers
            settings.splitHotkeyDisplay = hotkeyDisplayString(keyCode: kc, modifiers: splitRecorder.recordedModifiers)
        }

        if let seg = defaultSplitSeg {
            settings.defaultSplitMode = (seg.selectedSegment == 1)
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
        templateTextView?.string = settings.defaultPrompt
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

        settings.splitHotkeyKeyCode = DEFAULT_SPLIT_HOTKEY_KEYCODE
        settings.splitHotkeyModifiers = Int(controlKey)
        settings.splitHotkeyDisplay = "⌃D"

        settings.defaultSplitMode = true
        defaultSplitSeg?.selectedSegment = 1

        screenshotRecorder.recordBtn?.title = "    ⌃T    "
        screenshotRecorder.statusLabel?.stringValue = "已恢复默认快捷键 ⌃T"
        selectionRecorder.recordBtn?.title = "    ⇧⌃T    "
        selectionRecorder.statusLabel?.stringValue = "已恢复默认快捷键 ⇧⌃T"
        closePanelRecorder.recordBtn?.title = "    Esc    "
        closePanelRecorder.statusLabel?.stringValue = "已恢复默认快捷键 Esc"
        togglePanelRecorder.recordBtn?.title = "    `    "
        togglePanelRecorder.statusLabel?.stringValue = "已恢复默认快捷键 `"
        splitRecorder.recordBtn?.title = "    ⌃D    "
        splitRecorder.statusLabel?.stringValue = "已恢复默认快捷键 ⌃D"

        screenshotRecorder.reset()
        selectionRecorder.reset()
        closePanelRecorder.reset()
        togglePanelRecorder.reset()
        splitRecorder.reset()

        // 恢复默认后需重新注册全局热键，否则仍沿用重置前的旧热键
        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.reregisterHotkey()
        }
    }

    // MARK: - 提供商切换

    @objc private func providerChanged(_ sender: NSPopUpButton) {
        guard let idx = AIProvider.allCases.firstIndex(where: { sender.titleOfSelectedItem == $0.displayName }) else { return }
        let newProvider = AIProvider.allCases[idx]
        let settings = SettingsManager.shared

        let currentKey = activeApiKeyFieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentKey.isEmpty {
            settings.setApiKey(currentKey, for: settings.apiProvider)
        } else {
            settings.setApiKey(nil, for: settings.apiProvider)
        }

        settings.setModelOverride(activeModelValue, for: settings.apiProvider)
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

        let tvH = size.height - 80
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 20, width: w - 40, height: tvH))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = true

        let textView = ShortcutTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize))
        textView.isEditable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isRichText = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.string = SettingsManager.shared.systemPrompt
        scrollView.documentView = textView
        v.addSubview(scrollView)
        templateTextView = textView

        return v
    }
}

extension SettingsWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        window = nil
        // 关闭窗口时清理未完成的录制，避免本地 keyDown monitor 残留
        screenshotRecorder.reset()
        selectionRecorder.reset()
        closePanelRecorder.reset()
        togglePanelRecorder.reset()
        splitRecorder.reset()
    }
}

// MARK: - 热键录制器（消除 4 份重复代码）

final class HotkeyRecorder: NSObject {
    weak var recordBtn: NSButton?
    weak var statusLabel: NSTextField?
    var isRecording = false
    var recordedKeyCode: Int? = nil
    var recordedModifiers = 0
    private var monitor: Any?
    private var timeoutWorkItem: DispatchWorkItem?
    private var bezelResetWorkItem: DispatchWorkItem?

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
        recordedKeyCode = nil
        recordedModifiers = 0

        bezelResetWorkItem?.cancel()
        bezelResetWorkItem = nil

        recordBtn?.title = "  ... 按下组合键 ...  "
        recordBtn?.bezelColor = .systemOrange
        statusLabel?.stringValue = "请按下组合键..."

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecording else { return event }
            self.record(event: event)
            return nil
        }

        // 10 秒超时：存为 workItem，结束录制时取消，避免旧超时误杀新的一次录制
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, self.isRecording else { return }
            self.cancel()
        }
        timeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)
    }

    /// 可取消的 bezel 颜色复位：只清「非录制中」的按钮颜色，避免旧复位误清新录制（start 置橙）的指示
    private func scheduleBezelReset(after seconds: TimeInterval) {
        bezelResetWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isRecording else { return }
            self.recordBtn?.bezelColor = nil
        }
        bezelResetWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func record(event: NSEvent) {
        let carbonModifiers = cocoaToCarbonModifiers(event.modifierFlags)
        let keyCode = Int(event.keyCode)

        guard allowedSoloKeyCodes.contains(keyCode) || hotkeyHasRequiredModifiers(carbonModifiers) else {
            cancel()
            statusLabel?.stringValue = "❌ 单个字母不能作为快捷键\n请同时按住 ⌘ / ⌥ / ⌃ / ⇧ 之一再按字母"
            recordBtn?.bezelColor = .systemRed
            scheduleBezelReset(after: 1.5)
            return
        }

        recordedKeyCode = keyCode
        recordedModifiers = carbonModifiers
        isRecording = false

        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil

        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }

        let display = hotkeyDisplayString(keyCode: recordedKeyCode ?? 0, modifiers: recordedModifiers)
        recordBtn?.title = "    \(display)    "
        recordBtn?.bezelColor = .systemGreen
        var status = "✅ 已录制：\(display)\n点击「保存并应用」使快捷键生效"
        if let conflict = checkSystemHotkeyConflict(modifiers: recordedModifiers, keyCode: recordedKeyCode ?? 0) {
            status += "\n⚠️ 可能与系统快捷键冲突：\(conflict)"
            recordBtn?.bezelColor = .systemOrange
        }
        statusLabel?.stringValue = status

        scheduleBezelReset(after: 2)
    }

    private func cancel() {
        isRecording = false
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        bezelResetWorkItem?.cancel()
        bezelResetWorkItem = nil
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
        isRecording = false
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        bezelResetWorkItem?.cancel()
        bezelResetWorkItem = nil
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
        recordedKeyCode = nil
        recordedModifiers = 0
    }

    static var anyRecording: Bool {
        let ctrl = SettingsWindowController.shared
        return ctrl.screenshotRecorder.isRecording
            || ctrl.selectionRecorder.isRecording
            || ctrl.closePanelRecorder.isRecording
            || ctrl.togglePanelRecorder.isRecording
            || ctrl.splitRecorder.isRecording
    }
}