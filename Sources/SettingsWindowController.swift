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
    private var apiKeyHiddenField: NSSecureTextField?  // 密文（默认显示）
    private var apiKeyEyeButton: NSButton?
    private var apiKeyVisible: Bool = false             // 当前是否明文
    private var customEndpointField: NSTextField?
    private var customModelField: NSTextField?
    private var providerDescLabel: NSTextField?
    private var testStatusLabel: NSTextField?
    private var providerCardView: NSView?          // 当前提供商的卡片容器
    private var providerCardHeight: CGFloat = 0

    // Tab 2: 快捷键
    private var hotkeyLabel: NSTextField?
    private var hotkeyRecordBtn: NSButton?
    private var hotkeyStatusLabel: NSTextField?
    private var isRecordingHotkey = false
    private var recordedKeyCode: Int = 0
    private var recordedModifiers: Int = 0

    // 划词翻译快捷键
    private var selectionHotkeyRecordBtn: NSButton?
    private var selectionHotkeyStatusLabel: NSTextField?
    private var isRecordingSelectionHotkey = false
    private var recordedSelectionKeyCode: Int = 0
    private var recordedSelectionModifiers: Int = 0
    private var hotkeyMonitor: Any?

    // 关闭翻译面板快捷键
    private var closePanelHotkeyRecordBtn: NSButton?
    private var closePanelHotkeyStatusLabel: NSTextField?
    private var isRecordingClosePanelHotkey = false
    private var recordedClosePanelKeyCode: Int = 0
    private var recordedClosePanelModifiers: Int = 0
    private var selectionHotkeyMonitor: Any?
    private var closePanelHotkeyMonitor: Any?

    // 切换弹窗位置快捷键
    private var togglePanelHotkeyRecordBtn: NSButton?
    private var togglePanelHotkeyStatusLabel: NSTextField?
    private var isRecordingTogglePanelHotkey = false
    private var recordedTogglePanelKeyCode: Int = 0
    private var recordedTogglePanelModifiers: Int = 0
    private var togglePanelHotkeyMonitor: Any?

    // Tab 3: 翻译模板
    private var templateTextView: NSTextView?
    private var templatePreviewWebView: WKWebView?

    func show() {
        if let w = window { w.close(); window = nil }

        let ww: CGFloat = 640, hh: CGFloat = 700
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: ww, height: hh),
                           styleMask: [.titled, .closable, .miniaturizable],
                           backing: .buffered, defer: false)
        win.title = "\(APP_DISPLAY_NAME) 偏好设置"
        win.center()
        win.isReleasedWhenClosed = false
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NSView(frame: NSRect(x: 0, y: 0, width: ww, height: hh))

        // ---- 标签页 ----
        let tabView = NSTabView(frame: NSRect(x: 16, y: 50, width: ww - 32, height: hh - 66))
        tabView.tabViewType = .topTabsBezelBorder

        // Tab 1: 通用
        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.label = "通用"
        generalTab.view = buildGeneralTab(size: tabView.frame.size)
        tabView.addTabViewItem(generalTab)

        // Tab 2: 快捷键
        let hotkeyTab = NSTabViewItem(identifier: "hotkey")
        hotkeyTab.label = "快捷键"
        hotkeyTab.view = buildHotkeyTab(size: tabView.frame.size)
        tabView.addTabViewItem(hotkeyTab)

        // Tab 3: 翻译模板
        let templateTab = NSTabViewItem(identifier: "template")
        templateTab.label = "翻译模板"
        templateTab.view = buildTemplateTab(size: tabView.frame.size)
        tabView.addTabViewItem(templateTab)

        content.addSubview(tabView)
        self.tabView = tabView

        // ---- 底部按钮 ----
        let resetBtn = NSButton(title: "恢复默认", target: self, action: #selector(resetAll))
        resetBtn.frame = NSRect(x: 16, y: 12, width: 100, height: 28)
        resetBtn.bezelStyle = .rounded
        content.addSubview(resetBtn)

        let saveBtn = NSButton(title: "保存并应用", target: self, action: #selector(saveAllSettings))
        saveBtn.frame = NSRect(x: ww - 135, y: 12, width: 120, height: 28)
        saveBtn.bezelStyle = .rounded
        saveBtn.keyEquivalent = "\r"
        content.addSubview(saveBtn)

        // ---- 版本号（底部居中，极简不干扰 UI） ----
        let versionLabel = NSTextField(labelWithString: "ELTA \(APP_FULL_VERSION)")
        versionLabel.frame = NSRect(x: (ww - 160) / 2, y: 0, width: 160, height: 14)
        versionLabel.alignment = .center
        versionLabel.font = .systemFont(ofSize: 10, weight: .regular)
        versionLabel.textColor = .secondaryLabelColor
        content.addSubview(versionLabel)

        win.contentView = content
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // 避免 API Key 输入框默认成为 first responder 并自动选中全部文本，
        // 防止通用剪贴板（Handoff）意外把 Key 同步到其他设备。
        win.makeFirstResponder(content)
        self.window = win
    }

    // MARK: - Tab 1: 通用（滚动列表 + 动态卡片）

    private func buildGeneralTab(size: NSSize) -> NSView {
        let v = NSView(frame: NSRect(origin: .zero, size: size))
        let w = size.width
        var y: CGFloat = size.height - 30

        // --- 标题 ---
        let titleLabel = NSTextField(labelWithString: "AI 翻译引擎配置")
        titleLabel.frame = NSRect(x: 20, y: y, width: 300, height: 22)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        v.addSubview(titleLabel)
        y -= 28

        // --- 提供商下拉选择器 ---
        let providerLabel = NSTextField(labelWithString: "当前 AI 提供商：")
        providerLabel.frame = NSRect(x: 20, y: y, width: 200, height: 18)
        providerLabel.font = .systemFont(ofSize: 12, weight: .medium)
        v.addSubview(providerLabel)
        y -= 24

        let providerPopup = NSPopUpButton(frame: NSRect(x: 20, y: y, width: 280, height: 26), pullsDown: false)
        providerPopup.addItems(withTitles: AIProvider.allCases.map { $0.displayName })
        let currentProvider = SettingsManager.shared.apiProvider
        providerPopup.selectItem(at: AIProvider.allCases.firstIndex(of: currentProvider) ?? 0)
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged(_:))
        v.addSubview(providerPopup)
        self.providerPopup = providerPopup
        y -= 40

        // --- 分隔线 ---
        let sep = NSBox(frame: NSRect(x: 20, y: y, width: w - 40, height: 1))
        sep.boxType = .separator
        v.addSubview(sep)
        y -= 12

        // --- 动态卡片区域（根据选中提供商显示对应配置） ---
        let cardScroll = NSScrollView(frame: NSRect(x: 16, y: 10, width: w - 32, height: y - 10))
        cardScroll.hasVerticalScroller = true
        cardScroll.autohidesScrollers = false
        cardScroll.borderType = .noBorder
        cardScroll.drawsBackground = false
        v.addSubview(cardScroll)

        providerCardHeight = y - 10
        let cardView = buildProviderCard(width: w - 36, provider: currentProvider)
        cardScroll.documentView = cardView
        self.providerCardView = cardView
        scrollProviderCardToTop(scrollView: cardScroll)

        return v
    }

    /// 根据提供商构建动态配置卡片
    private func buildProviderCard(width w: CGFloat, provider: AIProvider) -> NSView {
        let settings = SettingsManager.shared
        let workingHeight: CGFloat = 800
        let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: workingHeight))
        var y: CGFloat = workingHeight - 16

        // --- API Key 区域 ---
        if provider.needsAPIKey {
            let apiTitle = NSTextField(labelWithString: "\(provider.displayName) API Key：")
            apiTitle.frame = NSRect(x: 4, y: y, width: w - 8, height: 18)
            apiTitle.font = .systemFont(ofSize: 12, weight: .semibold)
            v.addSubview(apiTitle)
            y -= 20

            let apiDesc = NSTextField(labelWithString: "注册地址：\(provider.registerURL)")
            apiDesc.frame = NSRect(x: 4, y: y, width: w - 8, height: 14)
            apiDesc.font = .systemFont(ofSize: 10)
            apiDesc.textColor = .secondaryLabelColor
            v.addSubview(apiDesc)
            self.providerDescLabel = apiDesc
            y -= 20

            // API Key 输入行：密文字段 + 明文字段（叠放） + 小眼睛切换按钮
            let keyRow = NSView(frame: NSRect(x: 4, y: y, width: w - 8, height: 26))
            let fieldWid = w - 8 - 32  // 为眼睛按钮留 32pt

            // 明文输入框（PasteTextField，支持 Cmd+V）
            let visibleField = PasteTextField(frame: NSRect(x: 0, y: 0, width: fieldWid, height: 26))
            visibleField.placeholderString = (provider == .anthropic) ? "sk-ant-..." : "sk-..."
            visibleField.stringValue = settings.apiKey(for: provider) ?? ""
            visibleField.isBordered = true
            visibleField.bezelStyle = .roundedBezel
            visibleField.isEditable = true
            visibleField.isSelectable = true
            visibleField.isHidden = true  // 默认隐藏（密文模式）
            keyRow.addSubview(visibleField)

            // 密文输入框（NSSecureTextField，默认显示）
            let hiddenField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: fieldWid, height: 26))
            hiddenField.placeholderString = (provider == .anthropic) ? "sk-ant-..." : "sk-..."
            hiddenField.stringValue = settings.apiKey(for: provider) ?? ""
            hiddenField.isBordered = true
            hiddenField.bezelStyle = .roundedBezel
            hiddenField.isEditable = true
            hiddenField.isSelectable = true
            keyRow.addSubview(hiddenField)

            // 小眼睛按钮
            let eyeBtn = NSButton(frame: NSRect(x: fieldWid + 4, y: 1, width: 26, height: 24))
            eyeBtn.bezelStyle = .regularSquare
            eyeBtn.isBordered = false
            eyeBtn.title = "🔐"
            eyeBtn.toolTip = "显示/隐藏 API Key"
            eyeBtn.font = .systemFont(ofSize: 16)
            eyeBtn.target = self
            eyeBtn.action = #selector(toggleApiKeyVisibility(_:))
            keyRow.addSubview(eyeBtn)

            v.addSubview(keyRow)
            apiKeyVisibleField = visibleField
            apiKeyHiddenField = hiddenField
            apiKeyEyeButton = eyeBtn
            apiKeyVisible = false
            y -= 36

            let testBtn = NSButton(title: "测试连接", target: self, action: #selector(testAPIKey))
            testBtn.frame = NSRect(x: 4, y: y, width: 90, height: 28)
            testBtn.bezelStyle = .rounded
            v.addSubview(testBtn)

            let statusLabel = NSTextField(labelWithString: "")
            statusLabel.frame = NSRect(x: 100, y: y + 4, width: w - 104, height: 18)
            statusLabel.font = .systemFont(ofSize: 11)
            statusLabel.textColor = .secondaryLabelColor
            v.addSubview(statusLabel)
            self.testStatusLabel = statusLabel
            y -= 42
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
            self.customModelField = mdlField
            y -= 40
        }

        // --- 分隔线 ---
        let sep2 = NSBox(frame: NSRect(x: 4, y: y, width: w - 8, height: 1))
        sep2.boxType = .separator
        v.addSubview(sep2)
        y -= 16

        // --- 其他提供商的 Key 列表 ---
        let otherTitle = NSTextField(labelWithString: "其他 AI 提供商的 API Key（填入后切换即可使用）：")
        otherTitle.frame = NSRect(x: 4, y: y, width: w - 8, height: 18)
        otherTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        v.addSubview(otherTitle)
        y -= 26

        for p in AIProvider.allCases where p != provider && p.needsAPIKey {
            let hasKey = (settings.apiKey(for: p) ?? "").isEmpty ? false : true
            let statusIcon = hasKey ? "✅" : "⬜"
            let rowLabel = NSTextField(labelWithString: "\(statusIcon)  \(p.displayName)")
            rowLabel.frame = NSRect(x: 8, y: y, width: 200, height: 18)
            rowLabel.font = .systemFont(ofSize: 11)
            rowLabel.textColor = hasKey ? .labelColor : .secondaryLabelColor
            v.addSubview(rowLabel)
            y -= 18
        }

        // --- 提示信息 ---
        let infoLabel = NSTextField(labelWithString: """
        💡 提示：Key 仅保存在本地，不会上传到任何第三方服务器。
        切换提供商后需点击底部「保存并应用」才能生效。
        """)
        let infoTop = max(y - 50, 20)
        infoLabel.frame = NSRect(x: 4, y: infoTop, width: w - 8, height: 50)
        infoLabel.font = .systemFont(ofSize: 10)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.lineBreakMode = .byWordWrapping
        v.addSubview(infoLabel)

        // 根据实际内容动态调整卡片高度，并整体下移内容，避免提示文字与列表重叠
        let requiredHeight = infoTop + 50 + 16
        let offset = workingHeight - requiredHeight
        for subview in v.subviews {
            var frame = subview.frame
            frame.origin.y -= offset
            subview.frame = frame
        }
        v.frame = NSRect(x: 0, y: 0, width: w, height: requiredHeight)

        return v
    }

    /// 将 AI 提供商配置卡片滚动到顶部，确保 API Key 输入区域默认可见
    private func scrollProviderCardToTop(scrollView: NSScrollView) {
        guard let documentView = scrollView.documentView else { return }
        let clipView = scrollView.contentView
        let targetY = documentView.frame.height - clipView.bounds.height
        clipView.scroll(to: NSPoint(x: 0, y: max(0, targetY)))
        scrollView.reflectScrolledClipView(clipView)
    }

    // MARK: - Tab 2: 快捷键

    private func buildHotkeyTab(size: NSSize) -> NSView {
        let contentHeight = size.height + 180
        let v = NSView(frame: NSRect(x: 0, y: 0, width: size.width, height: contentHeight))
        let w = size.width
        let y0: CGFloat = contentHeight - 30

        // ---- 1. 截图翻译 ----
        let titleLabel = NSTextField(labelWithString: "📷 截图翻译快捷键")
        titleLabel.frame = NSRect(x: 20, y: y0, width: 300, height: 22)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        v.addSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: "框选屏幕区域 → OCR 识别 → AI 翻译")
        descLabel.frame = NSRect(x: 20, y: y0 - 24, width: w - 40, height: 16)
        descLabel.font = .systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        v.addSubview(descLabel)

        let currentDisplay = SettingsManager.shared.hotkeyDisplay
        let recordBtn = NSButton(title: "    \(currentDisplay)    ", target: self, action: #selector(startRecordingHotkey))
        recordBtn.frame = NSRect(x: 20, y: y0 - 80, width: 180, height: 42)
        recordBtn.bezelStyle = .rounded
        recordBtn.font = .systemFont(ofSize: 20, weight: .medium)
        v.addSubview(recordBtn)
        hotkeyRecordBtn = recordBtn

        let statusLabel = NSTextField(labelWithString: "点击上方按钮开始录制新快捷键")
        statusLabel.frame = NSRect(x: 210, y: y0 - 70, width: w - 230, height: 30)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        v.addSubview(statusLabel)
        hotkeyStatusLabel = statusLabel

        // ---- 2. 划词翻译 ----
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
        let selRecordBtn = NSButton(title: "    \(selDisplay)    ", target: self, action: #selector(startRecordingSelectionHotkey))
        selRecordBtn.frame = NSRect(x: 20, y: selY - 80, width: 180, height: 42)
        selRecordBtn.bezelStyle = .rounded
        selRecordBtn.font = .systemFont(ofSize: 20, weight: .medium)
        v.addSubview(selRecordBtn)
        selectionHotkeyRecordBtn = selRecordBtn

        let selStatus = NSTextField(labelWithString: "点击上方按钮开始录制新快捷键")
        selStatus.frame = NSRect(x: 210, y: selY - 70, width: w - 230, height: 30)
        selStatus.font = .systemFont(ofSize: 12)
        selStatus.textColor = .secondaryLabelColor
        selStatus.lineBreakMode = .byWordWrapping
        v.addSubview(selStatus)
        selectionHotkeyStatusLabel = selStatus

        // ---- 3. 关闭翻译面板 ----
        let escY = selY - 150
        let escTitle = NSTextField(labelWithString: "📋 关闭翻译面板")
        escTitle.frame = NSRect(x: 20, y: escY, width: 300, height: 22)
        escTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        v.addSubview(escTitle)

        let escDesc = NSTextField(labelWithString: "翻译浮动面板显示时，按下自定义快捷键即可关闭")
        escDesc.frame = NSRect(x: 20, y: escY - 24, width: w - 40, height: 16)
        escDesc.font = .systemFont(ofSize: 11)
        escDesc.textColor = .secondaryLabelColor
        v.addSubview(escDesc)

        let closePanelBtn = NSButton(title: "  \(SettingsManager.shared.closePanelHotkeyDisplay)  ", target: self, action: #selector(startRecordingClosePanelHotkey))
        closePanelBtn.frame = NSRect(x: 20, y: escY - 65, width: 180, height: 32)
        closePanelBtn.font = .systemFont(ofSize: 18, weight: .medium)
        closePanelBtn.bezelStyle = .rounded
        v.addSubview(closePanelBtn)
        closePanelHotkeyRecordBtn = closePanelBtn

        let escStatus = NSTextField(labelWithString: "点击上方按钮开始录制新快捷键")
        escStatus.frame = NSRect(x: 210, y: escY - 60, width: w - 230, height: 30)
        escStatus.font = .systemFont(ofSize: 12)
        escStatus.textColor = .secondaryLabelColor
        escStatus.lineBreakMode = .byWordWrapping
        v.addSubview(escStatus)
        closePanelHotkeyStatusLabel = escStatus

        // ---- 4. 切换弹窗位置 ----
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

        let togglePanelBtn = NSButton(title: "  \(SettingsManager.shared.togglePanelHotkeyDisplay)  ", target: self, action: #selector(startRecordingTogglePanelHotkey))
        togglePanelBtn.frame = NSRect(x: 20, y: toggleY - 65, width: 180, height: 32)
        togglePanelBtn.font = .systemFont(ofSize: 18, weight: .medium)
        togglePanelBtn.bezelStyle = .rounded
        v.addSubview(togglePanelBtn)
        togglePanelHotkeyRecordBtn = togglePanelBtn

        let toggleStatus = NSTextField(labelWithString: "点击上方按钮开始录制新快捷键")
        toggleStatus.frame = NSRect(x: 210, y: toggleY - 60, width: w - 230, height: 30)
        toggleStatus.font = .systemFont(ofSize: 12)
        toggleStatus.textColor = .secondaryLabelColor
        toggleStatus.lineBreakMode = .byWordWrapping
        v.addSubview(toggleStatus)
        togglePanelHotkeyStatusLabel = toggleStatus

        // ---- 统一提示 ----
        let infoLabel = NSTextField(labelWithString: """
        💡 提示：
        • 截图翻译：任意位置按下快捷键 → 框选区域 → 自动翻译
        • 划词翻译：先选中文字 → 按下快捷键 → 自动翻译（更快捷）
        • 关闭面板：翻译浮动面板显示时，按下自定义快捷键即可关闭
        • 切换弹窗：翻译浮动面板显示时，按下快捷键可在左右侧之间切换
        • 默认组合键：⌃Control、⇧Shift + 任意按键（单个字母无效）
        • 关闭面板允许单独按 ESC，切换弹窗允许单独按 ` 键
        • 红色代表未保存，点击「保存并应用」立即生效
        • 录制时若检测到与系统快捷键冲突，会给出黄色提醒
        """)
        infoLabel.frame = NSRect(x: 20, y: toggleY - 220, width: w - 40, height: 140)
        infoLabel.font = .systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.lineBreakMode = .byWordWrapping
        v.addSubview(infoLabel)

        let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: size))
        scrollView.hasVerticalScroller = true
        scrollView.documentView = v
        return scrollView
    }

    @objc private func startRecordingHotkey() {
        guard !isRecordingHotkey else { return }
        isRecordingHotkey = true
        recordedKeyCode = 0
        recordedModifiers = 0

        hotkeyRecordBtn?.title = "  ... 按下组合键 ...  "
        hotkeyRecordBtn?.bezelColor = .systemOrange
        hotkeyStatusLabel?.stringValue = "请按下组合键..."

        // 监听全局按键（通过 NSEvent 本地监听）
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecordingHotkey else { return event }
            self.recordHotkey(event: event)
            return nil // 消费事件
        }

        // 如果 10 秒内没按，自动取消
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, self.isRecordingHotkey else { return }
            self.cancelRecording()
        }
    }

    private func recordHotkey(event: NSEvent) {
        let carbonModifiers = cocoaToCarbonModifiers(event.modifierFlags)
        let keyCode = Int(event.keyCode)

        // 必须有修饰键（禁止单个字母）
        guard hotkeyHasRequiredModifiers(carbonModifiers) else {
            cancelRecording()
            hotkeyStatusLabel?.stringValue = "❌ 单个字母不能作为快捷键\n请同时按住 ⌘ / ⌥ / ⌃ / ⇧ 之一再按字母"
            hotkeyRecordBtn?.bezelColor = .systemRed
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.hotkeyRecordBtn?.bezelColor = nil
            }
            return
        }

        recordedKeyCode = keyCode
        recordedModifiers = carbonModifiers
        isRecordingHotkey = false

        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }

        let display = hotkeyDisplayString(keyCode: recordedKeyCode, modifiers: recordedModifiers)
        hotkeyRecordBtn?.title = "    \(display)    "
        hotkeyRecordBtn?.bezelColor = .systemGreen
        var status = "✅ 已录制：\(display)\n点击「保存并应用」使快捷键生效"
        if let conflict = checkSystemHotkeyConflict(modifiers: recordedModifiers, keyCode: recordedKeyCode) {
            status += "\n⚠️ 可能与系统快捷键冲突：\(conflict)"
            hotkeyRecordBtn?.bezelColor = .systemOrange
        }
        hotkeyStatusLabel?.stringValue = status

        // 闪烁效果后恢复
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.hotkeyRecordBtn?.bezelColor = nil
        }
    }

    private func cancelRecording() {
        isRecordingHotkey = false
        if let monitor = hotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            hotkeyMonitor = nil
        }
        let display = SettingsManager.shared.hotkeyDisplay
        hotkeyRecordBtn?.title = "    \(display)    "
        hotkeyRecordBtn?.bezelColor = nil
        hotkeyStatusLabel?.stringValue = "录制超时，请重试"
    }

    // MARK: - 划词翻译快捷键录制

    @objc private func startRecordingSelectionHotkey() {
        guard !isRecordingSelectionHotkey, !isRecordingHotkey else { return }
        isRecordingSelectionHotkey = true
        recordedSelectionKeyCode = 0
        recordedSelectionModifiers = 0

        selectionHotkeyRecordBtn?.title = "  ... 按下组合键 ...  "
        selectionHotkeyRecordBtn?.bezelColor = .systemOrange
        selectionHotkeyStatusLabel?.stringValue = "请按下组合键..."

        selectionHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecordingSelectionHotkey else { return event }
            self.recordSelectionHotkey(event: event)
            return nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, self.isRecordingSelectionHotkey else { return }
            self.cancelSelectionRecording()
        }
    }

    private func recordSelectionHotkey(event: NSEvent) {
        let carbonModifiers = cocoaToCarbonModifiers(event.modifierFlags)
        let keyCode = Int(event.keyCode)

        // 必须有修饰键（禁止单个字母）
        guard hotkeyHasRequiredModifiers(carbonModifiers) else {
            cancelSelectionRecording()
            selectionHotkeyStatusLabel?.stringValue = "❌ 单个字母不能作为快捷键\n请同时按住 ⌘ / ⌥ / ⌃ / ⇧ 之一再按字母"
            selectionHotkeyRecordBtn?.bezelColor = .systemRed
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.selectionHotkeyRecordBtn?.bezelColor = nil
            }
            return
        }

        recordedSelectionKeyCode = keyCode
        recordedSelectionModifiers = carbonModifiers
        isRecordingSelectionHotkey = false

        if let monitor = selectionHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            selectionHotkeyMonitor = nil
        }

        let display = hotkeyDisplayString(keyCode: recordedSelectionKeyCode, modifiers: recordedSelectionModifiers)
        selectionHotkeyRecordBtn?.title = "    \(display)    "
        selectionHotkeyRecordBtn?.bezelColor = .systemGreen
        var status = "✅ 已录制：\(display)\n点击「保存并应用」使快捷键生效"
        if let conflict = checkSystemHotkeyConflict(modifiers: recordedSelectionModifiers, keyCode: recordedSelectionKeyCode) {
            status += "\n⚠️ 可能与系统快捷键冲突：\(conflict)"
            selectionHotkeyRecordBtn?.bezelColor = .systemOrange
        }
        selectionHotkeyStatusLabel?.stringValue = status

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.selectionHotkeyRecordBtn?.bezelColor = nil
        }
    }

    private func cancelSelectionRecording() {
        isRecordingSelectionHotkey = false
        if let monitor = selectionHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            selectionHotkeyMonitor = nil
        }
        let display = SettingsManager.shared.selectionHotkeyDisplay
        selectionHotkeyRecordBtn?.title = "    \(display)    "
        selectionHotkeyRecordBtn?.bezelColor = nil
        selectionHotkeyStatusLabel?.stringValue = "录制超时，请重试"
    }

    // MARK: - 关闭翻译面板快捷键录制

    @objc private func startRecordingClosePanelHotkey() {
        guard !isRecordingClosePanelHotkey, !isRecordingHotkey, !isRecordingSelectionHotkey, !isRecordingTogglePanelHotkey else { return }
        isRecordingClosePanelHotkey = true
        recordedClosePanelKeyCode = 0
        recordedClosePanelModifiers = 0

        closePanelHotkeyRecordBtn?.title = "  ... 按下快捷键 ...  "
        closePanelHotkeyRecordBtn?.bezelColor = .systemOrange
        closePanelHotkeyStatusLabel?.stringValue = "请按下快捷键（允许单独按 ESC）..."

        closePanelHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecordingClosePanelHotkey else { return event }
            self.recordClosePanelHotkey(event: event)
            return nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, self.isRecordingClosePanelHotkey else { return }
            self.cancelClosePanelRecording()
        }
    }

    private func recordClosePanelHotkey(event: NSEvent) {
        let carbonModifiers = cocoaToCarbonModifiers(event.modifierFlags)
        let keyCode = Int(event.keyCode)

        // 关闭面板允许单独 ESC；其他按键仍必须带修饰键
        guard keyCode == 0x35 || hotkeyHasRequiredModifiers(carbonModifiers) else {
            cancelClosePanelRecording()
            closePanelHotkeyStatusLabel?.stringValue = "❌ 单个字母不能作为快捷键\n请同时按住 ⌘ / ⌥ / ⌃ / ⇧ 之一，或直接按 ESC"
            closePanelHotkeyRecordBtn?.bezelColor = .systemRed
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.closePanelHotkeyRecordBtn?.bezelColor = nil
            }
            return
        }

        recordedClosePanelKeyCode = keyCode
        recordedClosePanelModifiers = carbonModifiers
        isRecordingClosePanelHotkey = false

        if let monitor = closePanelHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            closePanelHotkeyMonitor = nil
        }

        let display = hotkeyDisplayString(keyCode: recordedClosePanelKeyCode, modifiers: recordedClosePanelModifiers)
        closePanelHotkeyRecordBtn?.title = "    \(display)    "
        closePanelHotkeyRecordBtn?.bezelColor = .systemGreen
        var status = "✅ 已录制：\(display)\n点击「保存并应用」使快捷键生效"
        if let conflict = checkSystemHotkeyConflict(modifiers: recordedClosePanelModifiers, keyCode: recordedClosePanelKeyCode) {
            status += "\n⚠️ 可能与系统快捷键冲突：\(conflict)"
            closePanelHotkeyRecordBtn?.bezelColor = .systemOrange
        }
        closePanelHotkeyStatusLabel?.stringValue = status

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.closePanelHotkeyRecordBtn?.bezelColor = nil
        }
    }

    private func cancelClosePanelRecording() {
        isRecordingClosePanelHotkey = false
        if let monitor = closePanelHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            closePanelHotkeyMonitor = nil
        }
        let display = SettingsManager.shared.closePanelHotkeyDisplay
        closePanelHotkeyRecordBtn?.title = "    \(display)    "
        closePanelHotkeyRecordBtn?.bezelColor = nil
        closePanelHotkeyStatusLabel?.stringValue = "录制超时，请重试"
    }

    // MARK: - 切换弹窗位置快捷键录制

    @objc private func startRecordingTogglePanelHotkey() {
        guard !isRecordingTogglePanelHotkey, !isRecordingHotkey, !isRecordingSelectionHotkey, !isRecordingClosePanelHotkey else { return }
        isRecordingTogglePanelHotkey = true
        recordedTogglePanelKeyCode = 0
        recordedTogglePanelModifiers = 0

        togglePanelHotkeyRecordBtn?.title = "  ... 按下快捷键 ...  "
        togglePanelHotkeyRecordBtn?.bezelColor = .systemOrange
        togglePanelHotkeyStatusLabel?.stringValue = "请按下快捷键（允许单独按 ` 键）..."

        togglePanelHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecordingTogglePanelHotkey else { return event }
            self.recordTogglePanelHotkey(event: event)
            return nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, self.isRecordingTogglePanelHotkey else { return }
            self.cancelTogglePanelRecording()
        }
    }

    private func recordTogglePanelHotkey(event: NSEvent) {
        let carbonModifiers = cocoaToCarbonModifiers(event.modifierFlags)
        let keyCode = Int(event.keyCode)

        guard keyCode == 0x32 || hotkeyHasRequiredModifiers(carbonModifiers) else {
            cancelTogglePanelRecording()
            togglePanelHotkeyStatusLabel?.stringValue = "❌ 单个字母不能作为快捷键\n请同时按住 ⌘ / ⌥ / ⌃ / ⇧ 之一，或直接按 ` 键"
            togglePanelHotkeyRecordBtn?.bezelColor = .systemRed
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.togglePanelHotkeyRecordBtn?.bezelColor = nil
            }
            return
        }

        recordedTogglePanelKeyCode = keyCode
        recordedTogglePanelModifiers = carbonModifiers
        isRecordingTogglePanelHotkey = false

        if let monitor = togglePanelHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            togglePanelHotkeyMonitor = nil
        }

        let display = hotkeyDisplayString(keyCode: recordedTogglePanelKeyCode, modifiers: recordedTogglePanelModifiers)
        togglePanelHotkeyRecordBtn?.title = "    \(display)    "
        togglePanelHotkeyRecordBtn?.bezelColor = .systemGreen
        var status = "✅ 已录制：\(display)\n点击「保存并应用」使快捷键生效"
        if let conflict = checkSystemHotkeyConflict(modifiers: recordedTogglePanelModifiers, keyCode: recordedTogglePanelKeyCode) {
            status += "\n⚠️ 可能与系统快捷键冲突：\(conflict)"
            togglePanelHotkeyRecordBtn?.bezelColor = .systemOrange
        }
        togglePanelHotkeyStatusLabel?.stringValue = status

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.togglePanelHotkeyRecordBtn?.bezelColor = nil
        }
    }

    private func cancelTogglePanelRecording() {
        isRecordingTogglePanelHotkey = false
        if let monitor = togglePanelHotkeyMonitor {
            NSEvent.removeMonitor(monitor)
            togglePanelHotkeyMonitor = nil
        }
        let display = SettingsManager.shared.togglePanelHotkeyDisplay
        togglePanelHotkeyRecordBtn?.title = "    \(display)    "
        togglePanelHotkeyRecordBtn?.bezelColor = nil
        togglePanelHotkeyStatusLabel?.stringValue = "录制超时，请重试"
    }

    // MARK: - Tab 3: 翻译模板

    private func buildTemplateTab(size: NSSize) -> NSView {
        let v = NSView(frame: NSRect(origin: .zero, size: size))
        let w = size.width

        let titleLabel = NSTextField(labelWithString: "翻译提示词模板（可编辑）")
        titleLabel.frame = NSRect(x: 20, y: size.height - 30, width: 400, height: 22)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        v.addSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: "AI 将按此模板输出翻译结果。支持 Markdown 格式。")
        descLabel.frame = NSRect(x: 20, y: size.height - 52, width: w - 40, height: 16)
        descLabel.font = .systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        v.addSubview(descLabel)

        // 编辑器（左半边）
        let editorScroll = NSScrollView(frame: NSRect(x: 20, y: 20, width: w/2 - 30, height: size.height - 90))
        editorScroll.hasVerticalScroller = true
        editorScroll.borderType = .bezelBorder
        editorScroll.autohidesScrollers = true

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: editorScroll.contentSize.width, height: editorScroll.contentSize.height))
        tv.string = SettingsManager.shared.systemPrompt
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.isEditable = true
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.textContainerInset = NSSize(width: 8, height: 8)
        // 实时预览：编辑时更新
        tv.delegate = self
        editorScroll.documentView = tv
        v.addSubview(editorScroll)
        templateTextView = tv

        // 预览面板（右半边）
        let previewScroll = NSScrollView(frame: NSRect(x: w/2 + 10, y: 20, width: w/2 - 30, height: size.height - 90))
        previewScroll.hasVerticalScroller = true
        previewScroll.borderType = .bezelBorder
        previewScroll.autohidesScrollers = true

        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: previewScroll.contentSize.width, height: previewScroll.contentSize.height), configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        wv.loadHTMLString(templatePreviewHTML(), baseURL: nil)
        previewScroll.documentView = wv
        v.addSubview(previewScroll)
        templatePreviewWebView = wv

        return v
    }

    private func templatePreviewHTML() -> String {
        let prompt = templateTextView?.string ?? SettingsManager.shared.systemPrompt
        let escaped = prompt
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")

        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <style>
            :root{color-scheme:light dark}*{box-sizing:border-box;margin:0;padding:0}
            body{font-family:-apple-system,"PingFang SC",sans-serif;font-size:11px;line-height:1.5;color:#555;padding:10px 12px;background:#fff}
            @media(prefers-color-scheme:dark){body{color:#aaa;background:#2c2c2e}}
            .preview-title{font-size:12px;font-weight:600;color:#0071e3;margin-bottom:8px;border-bottom:1px solid #e5e5e7;padding-bottom:6px}
            @media(prefers-color-scheme:dark){.preview-title{color:#0a84ff;border-color:#3a3a3c}}
            .prompt-text{white-space:pre-wrap;word-break:break-word}
        </style>
        </head><body>
        <div class="preview-title">📋 模板预览（AI 将按此结构输出）</div>
        <div class="prompt-text">\(escaped)</div>
        </body></html>
        """
    }

    // MARK: - Actions

    /// 切换 API Key 输入框的显隐（明文 ↔ 密文）
    @objc private func toggleApiKeyVisibility(_ sender: NSButton) {
        apiKeyVisible.toggle()
        if apiKeyVisible {
            // 切到明文：密文框内容同步到明文框
            apiKeyVisibleField?.stringValue = apiKeyHiddenField?.stringValue ?? ""
            apiKeyVisibleField?.isHidden = false
            apiKeyHiddenField?.isHidden = true
            apiKeyEyeButton?.title = "🔓"
            apiKeyVisibleField?.window?.makeFirstResponder(apiKeyVisibleField)
        } else {
            // 切到密文：明文框内容同步到密文框
            apiKeyHiddenField?.stringValue = apiKeyVisibleField?.stringValue ?? ""
            apiKeyHiddenField?.isHidden = false
            apiKeyVisibleField?.isHidden = true
            apiKeyEyeButton?.title = "🔐"
            apiKeyHiddenField?.window?.makeFirstResponder(apiKeyHiddenField)
        }
    }

    /// 获取当前显示的 API Key 文本（无论明文/密文模式）
    private var activeApiKeyFieldValue: String {
        if apiKeyVisible {
            return apiKeyVisibleField?.stringValue ?? ""
        } else {
            return apiKeyHiddenField?.stringValue ?? ""
        }
    }

    @objc private func saveAllSettings() {
        let settings = SettingsManager.shared

        // API Key — 保存当前提供商的 Key
        let keyStr = activeApiKeyFieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        logi("保存设置: provider=\(settings.apiProvider.rawValue), keyLen=\(keyStr.count)")
        if !keyStr.isEmpty {
            settings.setApiKey(keyStr, for: settings.apiProvider)
        } else {
            // 清空 Key
            settings.setApiKey(nil, for: settings.apiProvider)
        }

        // 自定义 Endpoint & Model
        if let ep = customEndpointField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !ep.isEmpty {
            settings.customEndpoint = ep
        }
        if let mdl = customModelField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !mdl.isEmpty {
            if settings.apiProvider == .ollama {
                settings.ollamaModel = mdl
            } else {
                settings.customModel = mdl
            }
        }

        // 快捷键
        if recordedKeyCode != 0 {
            settings.hotkeyKeyCode = recordedKeyCode
            settings.hotkeyModifiers = recordedModifiers
            settings.hotkeyDisplay = hotkeyDisplayString(keyCode: recordedKeyCode, modifiers: recordedModifiers)
        }

        // 划词翻译快捷键
        if recordedSelectionKeyCode != 0 {
            settings.selectionHotkeyKeyCode = recordedSelectionKeyCode
            settings.selectionHotkeyModifiers = recordedSelectionModifiers
            settings.selectionHotkeyDisplay = hotkeyDisplayString(keyCode: recordedSelectionKeyCode, modifiers: recordedSelectionModifiers)
        }

        // 关闭翻译面板快捷键
        if recordedClosePanelKeyCode != 0 {
            settings.closePanelHotkeyKeyCode = recordedClosePanelKeyCode
            settings.closePanelHotkeyModifiers = recordedClosePanelModifiers
            settings.closePanelHotkeyDisplay = hotkeyDisplayString(keyCode: recordedClosePanelKeyCode, modifiers: recordedClosePanelModifiers)
        }

        // 切换弹窗位置快捷键
        if recordedTogglePanelKeyCode != 0 {
            settings.togglePanelHotkeyKeyCode = recordedTogglePanelKeyCode
            settings.togglePanelHotkeyModifiers = recordedTogglePanelModifiers
            settings.togglePanelHotkeyDisplay = hotkeyDisplayString(keyCode: recordedTogglePanelKeyCode, modifiers: recordedTogglePanelModifiers)
        }

        // 重新注册所有快捷键
        DispatchQueue.main.async {
            (NSApp.delegate as? AppDelegate)?.reregisterHotkey()
        }

        // 翻译模板
        if let template = templateTextView?.string, !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.systemPrompt = template
        }

        logi("设置已保存")
        window?.close()
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

        // 更新 UI
        templateTextView?.string = settings.defaultPrompt
        templatePreviewWebView?.loadHTMLString(templatePreviewHTML(), baseURL: nil)
        hotkeyRecordBtn?.title = "    ⌃T    "
        hotkeyStatusLabel?.stringValue = "已恢复默认快捷键 ⌃T"
        selectionHotkeyRecordBtn?.title = "    ⇧⌃T    "
        selectionHotkeyStatusLabel?.stringValue = "已恢复默认快捷键 ⇧⌃T"
        closePanelHotkeyRecordBtn?.title = "    Esc    "
        closePanelHotkeyStatusLabel?.stringValue = "已恢复默认快捷键 Esc"
        togglePanelHotkeyRecordBtn?.title = "    `    "
        togglePanelHotkeyStatusLabel?.stringValue = "已恢复默认快捷键 `"

        // 清除录制的临时值
        recordedKeyCode = 0
        recordedModifiers = 0
        recordedSelectionKeyCode = 0
        recordedSelectionModifiers = 0
        recordedClosePanelKeyCode = 0
        recordedClosePanelModifiers = 0
        recordedTogglePanelKeyCode = 0
        recordedTogglePanelModifiers = 0
    }

    // MARK: - 提供商切换

    @objc private func providerChanged(_ sender: NSPopUpButton) {
        guard let idx = AIProvider.allCases.firstIndex(where: { sender.titleOfSelectedItem == $0.displayName }) else { return }
        let newProvider = AIProvider.allCases[idx]
        let settings = SettingsManager.shared

        // 保存当前 Key 到当前提供商
        let currentKey = activeApiKeyFieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentKey.isEmpty {
            settings.setApiKey(currentKey, for: settings.apiProvider)
        }

        // 保存自定义 Endpoint/Model
        if let ep = customEndpointField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !ep.isEmpty {
            settings.customEndpoint = ep
        }
        if let mdl = customModelField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !mdl.isEmpty {
            if settings.apiProvider == .ollama {
                settings.ollamaModel = mdl
            } else {
                settings.customModel = mdl
            }
        }

        // 切换提供商
        settings.apiProvider = newProvider

        // 重建卡片（刷新 UI）
        guard let scrollView = providerCardView?.superview as? NSScrollView else { return }
        let cardWidth = scrollView.contentSize.width
        let newCard = buildProviderCard(width: cardWidth, provider: newProvider)
        scrollView.documentView = newCard
        self.providerCardView = newCard
        scrollProviderCardToTop(scrollView: scrollView)
    }

    @objc private func testAPIKey() {
        let settings = SettingsManager.shared
        let provider = settings.apiProvider
        let key = activeApiKeyFieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            let a = NSAlert(); a.messageText = "提示"; a.informativeText = "请先输入 API Key。"
            a.alertStyle = .informational; a.addButton(withTitle: "确定")
            a.layout(); a.window.level = .floating
            a.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            a.runModal(); return
        }

        testStatusLabel?.stringValue = "正在测试..."
        testStatusLabel?.textColor = .systemOrange

        let endpoint = provider.endpoint
        var body: [String: Any] = [:]
        guard let baseURL = URL(string: endpoint) else {
            testStatusLabel?.stringValue = "❌ API 地址无效，请检查设置"
            testStatusLabel?.textColor = .systemRed
            return
        }
        var req = URLRequest(url: baseURL)
        req.httpMethod = "POST"
        req.timeoutInterval = 15

        // 不同提供商的请求格式和认证方式
        switch provider {
        case .anthropic:
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            body = [
                "model": provider.defaultModel,
                "max_tokens": 5,
                "messages": [["role": "user", "content": "回复OK"]]
            ]
        case .googleAI:
            let baseEndpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
            guard let googleURL = URL(string: baseEndpoint) else {
                testStatusLabel?.stringValue = "❌ API 地址无效，请检查设置"
                testStatusLabel?.textColor = .systemRed
                return
            }
            req = URLRequest(url: googleURL)
            req.httpMethod = "POST"
            req.timeoutInterval = 15
            req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            body = [
                "contents": [["parts": [["text": "回复OK"]]]],
                "generationConfig": ["maxOutputTokens": 5]
            ]
        default:
            // OpenAI-compatible API（DeepSeek, OpenAI, 千问, Ollama 等）
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            body = [
                "model": provider.defaultModel,
                "messages": [["role": "user", "content": "回复OK"]],
                "max_tokens": 5
            ]
        }

        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let sem = DispatchSemaphore(value: 0)
        var success = false; var errMsg = ""
        URLSession.shared.dataTask(with: req) { data, resp, error in
            defer { sem.signal() }
            if let e = error { errMsg = e.localizedDescription; return }
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 { success = true }
            else { errMsg = "状态码 \((resp as? HTTPURLResponse)?.statusCode ?? 0)" }
        }.resume()
        sem.wait()

        DispatchQueue.main.async {
            if success {
                self.testStatusLabel?.stringValue = "✅ 连接成功"
                self.testStatusLabel?.textColor = .systemGreen
            } else {
                self.testStatusLabel?.stringValue = "❌ 失败：\(errMsg)"
                self.testStatusLabel?.textColor = .systemRed
            }
        }
    }
}

// MARK: - NSTextViewDelegate (实时模板预览)

extension SettingsWindowController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView, tv == templateTextView else { return }
        templatePreviewWebView?.loadHTMLString(templatePreviewHTML(), baseURL: nil)
    }
}
