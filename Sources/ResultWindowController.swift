import Cocoa
import WebKit
import Carbon

// MARK: - 可复制的 WebView（修复 .accessory 应用缺少 Edit 菜单导致 Cmd+C/A/V 无效）

final class ResultWebView: WKWebView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let realModifiers: NSEvent.ModifierFlags = [.command, .shift, .control, .option]
        guard f.intersection(realModifiers) == .command else { return super.performKeyEquivalent(with: event) }

        let sel: Selector?
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "v": sel = #selector(NSText.paste(_:))
        case "c": sel = #selector(NSText.copy(_:))
        case "x": sel = #selector(NSText.cut(_:))
        case "a": sel = #selector(NSText.selectAll(_:))
        default:  sel = nil
        }
        guard let s = sel else { return super.performKeyEquivalent(with: event) }
        // 先沿 WebView 自身响应链转发（覆盖浮动非激活面板非 key 的情况），失败再走全局 first responder
        if self.tryToPerform(s, with: self) { return true }
        if NSApp.sendAction(s, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - 结果窗口控制器

final class ResultWindowController: NSObject, NSWindowDelegate {
    static let shared = ResultWindowController()

    private var panel: NSPanel?

    var isPanelVisible: Bool { panel != nil }

    private var webView: WKWebView?
    private var escEventTap: CFMachPort?
    private var escRunLoopSource: CFRunLoopSource?
    private var togglePanelTap: CFMachPort?
    private var togglePanelRunLoopSource: CFRunLoopSource?
    private var splitTap: CFMachPort?
    private var splitRunLoopSource: CFRunLoopSource?
    private var splitControl: NSSegmentedControl?
    private var currentMarkdown = ""
    private var currentOriginalText = ""
    private var isSplitMode = false

    /// 共享 CGEventTap 创建与安装逻辑，消除 installEscTap / installToggleTap 的重复代码
    private func createAndInstallTap(
        callback: @escaping CGEventTapCallBack,
        tag: String
    ) -> (tap: CFMachPort?, source: CFRunLoopSource?) {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: callback,
            userInfo: selfPtr
        ) else {
            logi("\(tag) tap: 创建失败（可能缺少 Accessibility 权限）")
            return (nil, nil)
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        logi("\(tag) tap: 已安装")
        return (tap, runLoopSource)
    }

    private func installEscTap() {
        guard escEventTap == nil else { return }
        let callback: CGEventTapCallBack = { (proxy, type, event, info) -> Unmanaged<CGEvent>? in
            guard let info = info else { return Unmanaged.passUnretained(event) }
            let ctrl = Unmanaged<ResultWindowController>.fromOpaque(info).takeUnretainedValue()
            guard ctrl.panel != nil else { return Unmanaged.passUnretained(event) }

            let settings = SettingsManager.shared
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode != Int64(settings.closePanelHotkeyKeyCode) { return Unmanaged.passUnretained(event) }

            let expectedModifiers = settings.closePanelHotkeyModifiers
            let flags = event.flags
            var actualModifiers = 0
            if flags.contains(.maskCommand) { actualModifiers |= Int(cmdKey) }
            if flags.contains(.maskShift) { actualModifiers |= Int(shiftKey) }
            if flags.contains(.maskControl) { actualModifiers |= Int(controlKey) }
            if flags.contains(.maskAlternate) { actualModifiers |= Int(optionKey) }
            if actualModifiers != expectedModifiers { return Unmanaged.passUnretained(event) }

            DispatchQueue.main.async { ctrl.panel?.close() }
            return nil
        }
        let (tap, source) = createAndInstallTap(callback: callback, tag: "ESC")
        escEventTap = tap
        escRunLoopSource = source
    }

    /// 移除全局 ESC 事件拦截
    private func removeEscTap() {
        guard let tap = escEventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = escRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        escEventTap = nil
        escRunLoopSource = nil
        logi("ESC tap: 已移除")
    }

    private func togglePanelPosition() {
        guard let panel = panel,
              let screen = panel.screen ?? NSScreen.main else { return }

        let vf = screen.visibleFrame
        let midline = screen.frame.midX
        let isOnLeft = panel.frame.midX < midline

        var newFrame = panel.frame
        if isOnLeft {
            newFrame.origin.x = midline
            newFrame.size.width = vf.maxX - midline
        } else {
            newFrame.origin.x = vf.minX
            newFrame.size.width = midline - vf.minX
        }
        panel.setFrame(newFrame, display: true, animate: true)
    }

    private func installToggleTap() {
        guard togglePanelTap == nil else { return }
        let callback: CGEventTapCallBack = { (proxy, type, event, info) -> Unmanaged<CGEvent>? in
            guard let info = info else { return Unmanaged.passUnretained(event) }
            let ctrl = Unmanaged<ResultWindowController>.fromOpaque(info).takeUnretainedValue()
            guard ctrl.panel != nil else { return Unmanaged.passUnretained(event) }

            let settings = SettingsManager.shared
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode != Int64(settings.togglePanelHotkeyKeyCode) { return Unmanaged.passUnretained(event) }

            let expectedModifiers = settings.togglePanelHotkeyModifiers
            let flags = event.flags
            var actualModifiers = 0
            if flags.contains(.maskCommand) { actualModifiers |= Int(cmdKey) }
            if flags.contains(.maskShift) { actualModifiers |= Int(shiftKey) }
            if flags.contains(.maskControl) { actualModifiers |= Int(controlKey) }
            if flags.contains(.maskAlternate) { actualModifiers |= Int(optionKey) }
            if actualModifiers != expectedModifiers { return Unmanaged.passUnretained(event) }

            DispatchQueue.main.async { ctrl.togglePanelPosition() }
            return nil
        }
        let (tap, source) = createAndInstallTap(callback: callback, tag: "TogglePanel")
        togglePanelTap = tap
        togglePanelRunLoopSource = source
    }

    private func removeToggleTap() {
        guard let tap = togglePanelTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = togglePanelRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        togglePanelTap = nil
        togglePanelRunLoopSource = nil
        logi("TogglePanel tap: 已移除")
    }

    /// 拆分翻译快捷键（面板可见时生效，默认 ⌃D）
    private func installSplitTap() {
        guard splitTap == nil else { return }
        let callback: CGEventTapCallBack = { (proxy, type, event, info) -> Unmanaged<CGEvent>? in
            guard let info = info else { return Unmanaged.passUnretained(event) }
            let ctrl = Unmanaged<ResultWindowController>.fromOpaque(info).takeUnretainedValue()
            guard ctrl.panel != nil else { return Unmanaged.passUnretained(event) }

            let settings = SettingsManager.shared
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode != Int64(settings.splitHotkeyKeyCode) { return Unmanaged.passUnretained(event) }

            let expectedModifiers = settings.splitHotkeyModifiers
            let flags = event.flags
            var actualModifiers = 0
            if flags.contains(.maskCommand) { actualModifiers |= Int(cmdKey) }
            if flags.contains(.maskShift) { actualModifiers |= Int(shiftKey) }
            if flags.contains(.maskControl) { actualModifiers |= Int(controlKey) }
            if flags.contains(.maskAlternate) { actualModifiers |= Int(optionKey) }
            if actualModifiers != expectedModifiers { return Unmanaged.passUnretained(event) }

            DispatchQueue.main.async { ctrl.toggleSplitMode() }
            return nil
        }
        let (tap, source) = createAndInstallTap(callback: callback, tag: "SplitMode")
        splitTap = tap
        splitRunLoopSource = source
    }

    private func removeSplitTap() {
        guard let tap = splitTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = splitRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        splitTap = nil
        splitRunLoopSource = nil
        logi("SplitMode tap: 已移除")
    }

    /// 切换「整段 / 拆分」显示（供按钮与快捷键共用）
    func toggleSplitMode() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let seg = self.splitControl else { return }
            // 内容不适合拆分时忽略切换
            guard HTMLRenderer.canSplit(markdown: self.currentMarkdown, originalText: self.currentOriginalText) else { return }
            seg.selectedSegment = self.isSplitMode ? 0 : 1
            self.isSplitMode = (seg.selectedSegment == 1)
            self.reloadWebView()
        }
    }

    @objc private func splitModeChanged(_ sender: NSSegmentedControl) {
        isSplitMode = (sender.selectedSegment == 1)
        reloadWebView()
    }

    private func reloadWebView() {
        guard let wv = webView else { return }
        let isDark = NSApp.effectiveAppearance.name == .darkAqua
        let html: String
        if isSplitMode {
            html = HTMLRenderer.renderSplit(markdown: currentMarkdown, originalText: currentOriginalText, isDark: isDark)
        } else {
            html = HTMLRenderer.render(markdown: currentMarkdown, originalText: currentOriginalText, isDark: isDark)
        }
        wv.loadHTMLString(html, baseURL: nil)
    }

    func show(markdown: String, originalText: String, screenshotRect: NSRect) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.panel?.close()
            self.currentMarkdown = markdown
            self.currentOriginalText = originalText
            let startSplit = HTMLRenderer.shouldStartSplit(
                preferSplit: SettingsManager.shared.defaultSplitMode,
                canSplit: HTMLRenderer.canSplit(markdown: markdown, originalText: originalText)
            )
            self.isSplitMode = startSplit

            let frame = self.computeFrame(avoidRect: screenshotRect)

            let panel = NSPanel(contentRect: frame,
                                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.title = "翻译结果 — \(APP_DISPLAY_NAME)"
            panel.isMovableByWindowBackground = true
            panel.minSize = NSSize(width: 420, height: 400)
            panel.delegate = self

            let config = WKWebViewConfiguration()
            config.defaultWebpagePreferences.allowsContentJavaScript = false

            // 顶部工具栏：整段 / 拆分 切换
            let toolbarHeight: CGFloat = 36
            let container = NSView(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
            let toolbar = NSView(frame: NSRect(x: 0, y: frame.height - toolbarHeight, width: frame.width, height: toolbarHeight))
            toolbar.autoresizingMask = [.width, .minYMargin]

            let seg = NSSegmentedControl(labels: ["整段", "拆分"], trackingMode: .selectOne,
                                         target: self, action: #selector(self.splitModeChanged(_:)))
            seg.frame = NSRect(x: 12, y: 6, width: 150, height: 24)
            seg.segmentStyle = .rounded
            seg.selectedSegment = startSplit ? 1 : 0
            // 内容不适合拆分（表格/单词/单句）时禁用「拆分」段
            seg.setEnabled(HTMLRenderer.canSplit(markdown: markdown, originalText: originalText), forSegment: 1)
            toolbar.addSubview(seg)
            self.splitControl = seg

            let wv = ResultWebView(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height - toolbarHeight),
                                   configuration: config)
            wv.autoresizingMask = [.width, .height]
            wv.setValue(false, forKey: "drawsBackground")
            let isDark = NSApp.effectiveAppearance.name == .darkAqua
            wv.loadHTMLString(startSplit
                ? HTMLRenderer.renderSplit(markdown: markdown, originalText: originalText, isDark: isDark)
                : HTMLRenderer.render(markdown: markdown, originalText: originalText, isDark: isDark),
                baseURL: nil)

            container.addSubview(wv)
            container.addSubview(toolbar)
            panel.contentView = container
            panel.makeKeyAndOrderFront(nil)

            self.panel = panel
            self.webView = wv

            // 安装全局 ESC 拦截，确保无论焦点在哪里都能关闭弹窗
            self.installEscTap()
            // 安装切换弹窗位置快捷键
            self.installToggleTap()
            // 安装拆分翻译快捷键
            self.installSplitTap()
        }
    }

    func closeExistingPanel() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.panel?.close()
            self.panel = nil
            self.webView = nil
            self.splitControl = nil
            self.isSplitMode = false
        }
    }

    /// 弹窗铺满截图对侧半个屏幕（不越过中线）
    private func computeFrame(avoidRect: NSRect) -> NSRect {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(avoidRect) })
                ?? NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 620, height: 700)
        }
        let vf = screen.visibleFrame
        let midline = screen.frame.midX
        let onLeftSide = avoidRect.midX < midline

        let x: CGFloat = onLeftSide ? midline : vf.minX
        let w: CGFloat = onLeftSide ? (vf.maxX - midline) : (midline - vf.minX)

        if let saved = SettingsManager.shared.windowFrame {
            // 校验并夹紧保存的窗口位置/高度到当前可见区域，防止换显示器/分辨率后窗口跑到屏幕外
            let height = min(max(saved.height, 400), vf.height)
            let y = min(max(saved.origin.y, vf.minY), vf.maxY - height)
            return NSRect(x: x, y: y, width: w, height: height)
        }
        return NSRect(x: x, y: vf.minY, width: w, height: vf.height)
    }

    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow, win == panel else { return }
        removeEscTap()
        removeToggleTap()
        removeSplitTap()
        panel = nil
        webView = nil
        splitControl = nil
        isSplitMode = false
    }

    func windowDidMove(_ notification: Notification) {
        guard let win = notification.object as? NSWindow, win == panel else { return }
        SettingsManager.shared.windowFrame = win.frame
    }
}

// MARK: - HTML 渲染器

/// Markdown "## 章节" 的结构化表示
struct MarkdownSection {
    let heading: String?   // nil 表示无标题的前导内容
    let body: String
}

final class HTMLRenderer {
    static func render(markdown: String, originalText: String, isDark: Bool) -> String {
        let body = markdownBodyToHTML(markdown)
        return shell(body: body, originalBox: originalBoxHTML(originalText), isDark: isDark)
    }

    /// 拆分翻译视图：把「中文翻译」章节按句拆分，与原文逐句对照；其余章节（词汇/短语/核查）原样保留。
    /// 不重新请求 AI；若译文无「中文翻译」章节（自定义模板）或拆分结果为空，则回退整段渲染。
    static func renderSplit(markdown: String, originalText: String, isDark: Bool) -> String {
        guard canSplit(markdown: markdown, originalText: originalText) else {
            return render(markdown: markdown, originalText: originalText, isDark: isDark)
        }
        let sections = parseSections(markdown)
        guard let transSection = sections.first(where: { $0.heading?.contains("中文翻译") == true }) else {
            return render(markdown: markdown, originalText: originalText, isDark: isDark)
        }
        let pairs = SentenceSplitter.pair(original: originalText, translation: transSection.body)

        // 前导内容（无标题），渲染在最前
        let preambleHTML = sections
            .filter { $0.heading == nil }
            .map { markdownBodyToHTML($0.body) }
            .joined()

        var splitHTML = preambleHTML
        if !SentenceSplitter.sentenceCountsMatch(original: originalText, translation: transSection.body) {
            splitHTML += "<div class=\"split-warning\">⚠️ 原文与译文句数不一致，已自动对齐，请留意对照</div>"
        }
        splitHTML += "<h2>中文翻译</h2>"
        splitHTML += "<div class=\"split-list\">"
        for (idx, pair) in pairs.enumerated() {
            splitHTML += "<div class=\"split-pair\">"
            if !pair.original.isEmpty {
                splitHTML += "<div class=\"split-original\">\(idx + 1). \(inlineMarkdownToHTML(pair.original))</div>"
            }
            if !pair.translation.isEmpty {
                splitHTML += "<div class=\"split-translation\">\(inlineMarkdownToHTML(pair.translation))</div>"
            }
            splitHTML += "</div>"
        }
        splitHTML += "</div>"

        let otherSections = sections.filter { $0.heading != nil && $0.heading?.contains("中文翻译") != true }
        let otherMarkdown = otherSections.map { "## \($0.heading!)\n\($0.body)" }.joined(separator: "\n\n")
        let otherHTML = otherMarkdown.isEmpty ? "" : markdownBodyToHTML(otherMarkdown)

        return shell(body: splitHTML + otherHTML, originalBox: nil, isDark: isDark)
    }

    /// 判定当前内容是否适合拆分翻译：有「中文翻译」章节、非表格、且能拆出 ≥2 句
    static func canSplit(markdown: String, originalText: String) -> Bool {
        let sections = parseSections(markdown)
        guard let transSection = sections.first(where: { $0.heading?.contains("中文翻译") == true }) else {
            return false
        }
        guard !isTableBody(transSection.body) else { return false }
        let pairs = SentenceSplitter.pair(original: originalText, translation: transSection.body)
        return pairs.count >= 2
    }

    /// 弹窗初始模式决策：用户偏好拆分且内容可拆分时才从拆分起步，否则落回整段
    static func shouldStartSplit(preferSplit: Bool, canSplit: Bool) -> Bool {
        preferSplit && canSplit
    }

    /// 判断译文正文是否包含 Markdown 表格分隔行（|----|），含则视为表格内容
    private static func isTableBody(_ body: String) -> Bool {
        body.components(separatedBy: "\n").contains { isTableSeparatorLine($0) }
    }

    /// Markdown 正文 → HTML（转义 + 标题/加粗/行内代码/表格/段落）
    private static func markdownBodyToHTML(_ markdown: String) -> String {
        var html = escapeHTML(markdown)
        for keyword in ["中文翻译", "重要词汇", "常用短语与习语", "核查"] {
            html = html.replacingOccurrences(of: "## \(keyword)", with: "<h2>\(keyword)</h2>")
        }
        html = html.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        html = html.replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)

        // MD 表格 → HTML 表格（在换行处理前，因为表格是多行的）
        html = Self.convertMarkdownTables(in: html)

        html = html.replacingOccurrences(of: "\n\n", with: "</p><p>")
        html = html.replacingOccurrences(of: "\n", with: "<br>")
        html = "<p>" + html + "</p>"
        html = html.replacingOccurrences(of: "<p></p>", with: "")
        html = html.replacingOccurrences(of: "<p><br></p>", with: "")
        return html
    }

    /// 原文盒 HTML（拆分模式下不显示，原文已逐句内联）
    private static func originalBoxHTML(_ originalText: String) -> String {
        let normalized = TextNormalizer.normalizeLineBreaks(originalText)
        let escaped = normalized
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n\n", with: "<br><br>")
        return "<strong>📝 原文：</strong><br>\(escaped)"
    }

    /// 公共 HTML 外壳（head/CSS/body 结构 + footer）
    private static func shell(body: String, originalBox: String?, isDark: Bool) -> String {
        let themeClass = isDark ? "dark" : "light"
        let originalBoxHTML = originalBox.map { "<div class=\"original-box\">\($0)</div>" } ?? ""
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
        <style>
            :root{color-scheme:light dark}*{box-sizing:border-box;margin:0;padding:0}
            body{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC","Microsoft YaHei",sans-serif;font-size:14px;line-height:1.7;padding:0}
            body.light{color:#1d1d1f;background:#fff}
            body.dark{color:#e5e5e7;background:#1c1c1e}
            .original-box{position:sticky;top:0;z-index:10;border-bottom:1px solid;padding:14px 24px;font-size:15px;font-style:italic;max-height:50vh;overflow-y:auto;overflow-wrap:break-word}
            body.light .original-box{background:#e8f0fe;border-bottom-color:#b8d4fe;color:#1a3a6b}
            body.dark .original-box{background:#1c1c1e;border-bottom-color:#3a3a3c;color:#e5e5e7}
            .content{padding:18px 24px 20px}
            h2{font-size:17px;font-weight:600;margin:20px 0 12px;padding-bottom:8px;border-bottom:2px solid #0071e3}
            body.dark h2{color:#fff;border-bottom-color:#0a84ff}
            code{padding:2px 6px;border-radius:4px;font-family:"SF Mono",Menlo,monospace;font-size:13px}
            body.light code{background:#f0f0f2;color:#9b4d1c}
            body.dark code{background:#3a3a3c;color:#ff9f0a}
            body.light strong{color:#0071e3}
            body.dark strong{color:#5eafff}
            blockquote{border-left:4px solid;padding:10px 16px;margin:8px 0 12px;border-radius:0 8px 8px 0;font-size:15px}
            body.light blockquote{background:#f9f9fb;border-left-color:#0071e3;color:#3a3a3c}
            body.dark blockquote{background:#2c2c2e;border-left-color:#0a84ff;color:#c0c0c5}
            .split-list{display:flex;flex-direction:column;gap:10px;margin:8px 0 4px}
            .split-pair{border:1px solid;border-radius:8px;padding:10px 14px}
            body.light .split-pair{background:#f5f5f7;border-color:#e5e5e7}
            body.dark .split-pair{background:#2c2c2e;border-color:#3a3a3c}
            .split-original{font-style:italic;margin-bottom:4px;overflow-wrap:break-word}
            body.light .split-original{color:#1a3a6b}
            body.dark .split-original{color:#8ab4f8}
            .split-translation{overflow-wrap:break-word}
            body.light .split-translation{color:#1d1d1f}
            body.dark .split-translation{color:#e5e5e7}
            .split-warning{padding:10px 14px;margin:0 0 8px;border-radius:8px;font-size:13px;border:1px solid}
            body.light .split-warning{background:#fff3cd;color:#8a6d3b;border-color:#ffe08a}
            body.dark .split-warning{background:#3a2f00;color:#ffd75e;border-color:#5c4a00}
            table{width:100%;border-collapse:collapse;margin:10px 0 16px;font-size:13px}th{padding:10px 12px;text-align:left;font-weight:600}td{padding:8px 12px;border-bottom:1px solid;vertical-align:top}
            body.light th{background:#f5f5f7;color:#1d1d1f}body.light td{border-color:#e5e5e7;color:#1d1d1f}
            body.dark th{background:#2c2c2e;color:#fff}body.dark td{border-color:#3a3a3c;color:#e5e5e7}
            p{margin:6px 0}ul,ol{margin:8px 0;padding-left:20px}li{margin:4px 0}.footer{margin-top:20px;padding-top:12px;border-top:1px solid;font-size:11px;text-align:center}
            body.light .footer{border-top-color:#e5e5e7;color:#86868b}
            body.dark .footer{border-top-color:#3a3a3c;color:#8e8e93}
        </style>
        </head><body class="\(themeClass)">
        \(originalBoxHTML)
        <div class="content">
        \(body)
        <div class="footer">Powered by \(SettingsManager.shared.apiProvider.shortName) AI · ELTA — 截图即译，精读利器</div>
        </div>
        </body></html>
        """
    }

    /// 解析 Markdown 的 "## 章节" 结构为 [标题, 正文]
    static func parseSections(_ markdown: String) -> [MarkdownSection] {
        var sections: [MarkdownSection] = []
        let lines = markdown.components(separatedBy: "\n")
        var currentHeading: String?
        var currentBody: [String] = []

        func flush() {
            let body = currentBody.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                sections.append(MarkdownSection(heading: currentHeading, body: body))
            }
            currentBody = []
        }

        for line in lines {
            if line.hasPrefix("## ") {
                flush()
                currentHeading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else {
                currentBody.append(line)
            }
        }
        flush()
        return sections
    }

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// 句子级 Markdown 富文本 → HTML：转义 + 加粗 + 行内代码（不做标题/表格/段落，句子已是单行）
    static func inlineMarkdownToHTML(_ text: String) -> String {
        var html = escapeHTML(text)
        html = html.replacingOccurrences(of: "\n", with: "<br>")
        html = html.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        html = html.replacingOccurrences(of: "`([^`]+)`", with: "<code>$1</code>", options: .regularExpression)
        return html
    }

    // MARK: - Markdown 表格 → HTML 表格

    /// 在文本中检测 Markdown 表格块并转为 HTML <table>
    private static func convertMarkdownTables(in html: String) -> String {
        let lines = html.components(separatedBy: "\n")
        var result: [String] = []
        var i = 0

        while i < lines.count {
            // 检测表格起始：当前行是 |...| 格式，且下一行是分隔线
            if isTableHeaderCandidate(lines[i]) &&
                i + 1 < lines.count && isTableSeparatorLine(lines[i + 1]) {
                var tableLines: [String] = []
                while i < lines.count && isTableLine(lines[i]) {
                    tableLines.append(lines[i])
                    i += 1
                }
                if tableLines.count >= 2 {
                    result.append(renderHTMLTable(from: tableLines))
                } else {
                    result.append(contentsOf: tableLines)
                }
            } else {
                result.append(lines[i])
                i += 1
            }
        }

        return result.joined(separator: "\n")
    }

    /// 是否可能是表头行（以 | 开头和结尾）
    private static func isTableHeaderCandidate(_ line: String) -> Bool {
        isTableLine(line)
    }

    /// 是否为表格行（以 | 开头且以 | 结尾）
    private static func isTableLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.hasSuffix("|")
    }

    /// 是否为表格分隔行（|:---|:---:| 等）
    private static func isTableSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard isTableLine(trimmed) else { return false }
        let cells = trimmed.components(separatedBy: "|").filter { !$0.isEmpty }
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let stripped = cell.trimmingCharacters(in: .whitespaces)
            return !stripped.isEmpty && stripped.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    /// 解析单行表格为单元格数组（还原 TableExtractor 对单元格内 | 与 \ 的转义）
    private static func parseTableCells(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var cells = splitUnescapedPipes(trimmed)
        // 去除首尾空串（| 在收尾时产生）
        if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty ?? false { cells.removeFirst() }
        if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty ?? false { cells.removeLast() }
        return cells.map { unescapeMarkdownTableCell($0.trimmingCharacters(in: .whitespaces)) }
    }

    /// 按「未转义」的 | 切分单元格：TableExtractor 用 \| 转义单元格内的管道符，偶数个反斜杠后的 | 才是分隔符
    private static func splitUnescapedPipes(_ line: String) -> [String] {
        let chars = Array(line)
        var cells: [String] = []
        var current = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "\\" {
                var slashCount = 0
                var j = i
                while j < chars.count, chars[j] == "\\" { slashCount += 1; j += 1 }
                current.append(contentsOf: chars[i..<j])
                if j < chars.count, chars[j] == "|" {
                    if slashCount % 2 == 0 {
                        cells.append(current)   // 偶数反斜杠：| 是分隔符
                        current = ""
                    } else {
                        current.append("|")     // 奇数反斜杠：\| 是转义管道
                    }
                    i = j + 1
                    continue
                }
                i = j
                continue
            }
            if chars[i] == "|" {
                cells.append(current)
                current = ""
            } else {
                current.append(chars[i])
            }
            i += 1
        }
        cells.append(current)
        return cells
    }

    /// 还原 TableExtractor 的单元格转义（\| → |，\\ → \）
    private static func unescapeMarkdownTableCell(_ text: String) -> String {
        text.replacingOccurrences(of: "\\|", with: "|")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// 将 Markdown 表格行数组转换为 HTML <table>
    private static func renderHTMLTable(from lines: [String]) -> String {
        guard lines.count >= 2 else { return lines.first ?? "" }

        let headerCells = parseTableCells(lines[0])
        let colCount = headerCells.count
        var tableHTML = "<table>"

        // 表头
        tableHTML += "<thead><tr>"
        for cell in headerCells {
            tableHTML += "<th>\(cell)</th>"
        }
        tableHTML += "</tr></thead>"

        // 数据行（跳过第二行分隔线）
        tableHTML += "<tbody>"
        for rowIdx in 2..<lines.count {
            let cells = parseTableCells(lines[rowIdx])
            tableHTML += "<tr>"
            for c in 0..<colCount {
                let content = c < cells.count ? cells[c] : ""
                tableHTML += "<td>\(content)</td>"
            }
            tableHTML += "</tr>"
        }
        tableHTML += "</tbody></table>"

        return tableHTML
    }
}
