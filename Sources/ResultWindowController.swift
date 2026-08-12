import Cocoa
import WebKit
import Carbon

// MARK: - 可复制的 WebView（修复 .accessory 应用缺少 Edit 菜单导致 Cmd+C/A/V 无效）

final class ResultWebView: WKWebView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        let f = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard f == .command else { return super.performKeyEquivalent(with: event) }

        let sel: Selector?
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "v": sel = #selector(NSText.paste(_:))
        case "c": sel = #selector(NSText.copy(_:))
        case "x": sel = #selector(NSText.cut(_:))
        case "a": sel = #selector(NSText.selectAll(_:))
        default:  sel = nil
        }
        guard let s = sel else { return super.performKeyEquivalent(with: event) }
        if NSApp.sendAction(s, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - 结果窗口控制器

final class ResultWindowController: NSObject, NSWindowDelegate {
    static let shared = ResultWindowController()

    private var panel: NSPanel?

    /// 供外部查询：当前是否有翻译结果弹窗正在显示
    var isPanelVisible: Bool { panel != nil }

    private var webView: WKWebView?
    private var escEventTap: CFMachPort?
    private var escRunLoopSource: CFRunLoopSource?
    private var togglePanelTap: CFMachPort?
    private var togglePanelRunLoopSource: CFRunLoopSource?

    /// 安装全局关闭面板事件拦截（CGEventTap），翻译弹窗存在期间拦截用户自定义的关闭快捷键
    private func installEscTap() {
        guard escEventTap == nil else { return }
        let callback: CGEventTapCallBack = { (proxy, type, event, info) -> Unmanaged<CGEvent>? in
            guard let info = info else { return Unmanaged.passRetained(event) }
            let ctrl = Unmanaged<ResultWindowController>.fromOpaque(info).takeUnretainedValue()
            guard ctrl.panel != nil else {
                return Unmanaged.passRetained(event)
            }
            let settings = SettingsManager.shared
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let expectedKeyCode = Int64(settings.closePanelHotkeyKeyCode)
            if keyCode != expectedKeyCode {
                return Unmanaged.passRetained(event)
            }

            let expectedModifiers = settings.closePanelHotkeyModifiers
            // ESC 默认无修饰键，直接匹配；组合键需要比较 modifiers
            if expectedModifiers != 0 {
                let flags = event.flags
                var actualModifiers = 0
                if flags.contains(.maskCommand) { actualModifiers |= Int(cmdKey) }
                if flags.contains(.maskShift) { actualModifiers |= Int(shiftKey) }
                if flags.contains(.maskControl) { actualModifiers |= Int(controlKey) }
                if flags.contains(.maskAlternate) { actualModifiers |= Int(optionKey) }
                if actualModifiers != expectedModifiers {
                    return Unmanaged.passRetained(event)
                }
            }

            DispatchQueue.main.async {
                ctrl.panel?.close()
            }
            return nil
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: callback,
            userInfo: selfPtr
        ) else {
            logi("ESC tap: 创建失败（可能缺少 Accessibility 权限）")
            return
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        escEventTap = tap
        escRunLoopSource = runLoopSource
        logi("ESC tap: 已安装")
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
            guard let info = info else { return Unmanaged.passRetained(event) }
            let ctrl = Unmanaged<ResultWindowController>.fromOpaque(info).takeUnretainedValue()
            guard ctrl.panel != nil else {
                return Unmanaged.passRetained(event)
            }

            let settings = SettingsManager.shared
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let expectedKeyCode = Int64(settings.togglePanelHotkeyKeyCode)
            if keyCode != expectedKeyCode {
                return Unmanaged.passRetained(event)
            }

            let expectedModifiers = settings.togglePanelHotkeyModifiers
            if expectedModifiers != 0 {
                let flags = event.flags
                var actualModifiers = 0
                if flags.contains(.maskCommand) { actualModifiers |= Int(cmdKey) }
                if flags.contains(.maskShift) { actualModifiers |= Int(shiftKey) }
                if flags.contains(.maskControl) { actualModifiers |= Int(controlKey) }
                if flags.contains(.maskAlternate) { actualModifiers |= Int(optionKey) }
                if actualModifiers != expectedModifiers {
                    return Unmanaged.passRetained(event)
                }
            }

            DispatchQueue.main.async {
                ctrl.togglePanelPosition()
            }
            return nil
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: callback,
            userInfo: selfPtr
        ) else {
            logi("TogglePanel tap: 创建失败（可能缺少 Accessibility 权限）")
            return
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        togglePanelTap = tap
        togglePanelRunLoopSource = runLoopSource
        logi("TogglePanel tap: 已安装 (\(SettingsManager.shared.togglePanelHotkeyDisplay) 切换弹窗位置)")
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

    func show(markdown: String, originalText: String, screenshotRect: NSRect) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.panel?.close()
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
            let wv = ResultWebView(frame: NSRect(x: 0, y: 0, width: frame.width, height: frame.height),
                                   configuration: config)
            wv.autoresizingMask = [.width, .height]
            wv.setValue(false, forKey: "drawsBackground")
            let isDark = NSApp.effectiveAppearance.name == .darkAqua
            wv.loadHTMLString(HTMLRenderer.render(markdown: markdown, originalText: originalText, isDark: isDark), baseURL: nil)
            panel.contentView = wv
            panel.makeKeyAndOrderFront(nil)

            self.panel = panel
            self.webView = wv

            // 安装全局 ESC 拦截，确保无论焦点在哪里都能关闭弹窗
            self.installEscTap()
            // 安装切换弹窗位置快捷键
            self.installToggleTap()
        }
    }

    func closeExistingPanel() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.panel?.close()
            self.panel = nil
            self.webView = nil
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
            return NSRect(x: x, y: saved.origin.y, width: w, height: saved.height)
        }
        return NSRect(x: x, y: vf.minY, width: w, height: vf.height)
    }

    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow, win == panel else { return }
        removeEscTap()
        removeToggleTap()
        panel = nil
        webView = nil
    }

    func windowDidMove(_ notification: Notification) {
        guard let win = notification.object as? NSWindow, win == panel else { return }
        SettingsManager.shared.windowFrame = win.frame
    }
}

// MARK: - HTML 渲染器

final class HTMLRenderer {
    static func render(markdown: String, originalText: String, isDark: Bool) -> String {
        var html = escapeHTML(markdown)
        // MD 标题 → HTML 标题
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

        let normalized = TextNormalizer.normalizeLineBreaks(originalText)
        let escaped = normalized
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n\n", with: "<br><br>")

        let themeClass = isDark ? "dark" : "light"
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
        <style>
            :root{color-scheme:light dark}*{box-sizing:border-box;margin:0;padding:0}
            body{font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","PingFang SC","Microsoft YaHei",sans-serif;font-size:14px;line-height:1.7;padding:20px 24px}
            body.light{color:#1d1d1f;background:#fff}
            body.dark{color:#e5e5e7;background:#1c1c1e}
            .original-box{border:1px solid;border-radius:10px;padding:14px 18px;margin-bottom:18px;font-size:15px;font-style:italic}
            body.light .original-box{background:#e8f0fe;border-color:#b8d4fe;color:#1a3a6b}
            body.dark .original-box{background:#1c1c1e;border-color:#3a3a3c;color:#e5e5e7}
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
            table{width:100%;border-collapse:collapse;margin:10px 0 16px;font-size:13px}th{padding:10px 12px;text-align:left;font-weight:600}td{padding:8px 12px;border-bottom:1px solid;vertical-align:top}
            body.light th{background:#f5f5f7;color:#1d1d1f}body.light td{border-color:#e5e5e7;color:#1d1d1f}
            body.dark th{background:#2c2c2e;color:#fff}body.dark td{border-color:#3a3a3c;color:#e5e5e7}
            p{margin:6px 0}ul,ol{margin:8px 0;padding-left:20px}li{margin:4px 0}.footer{margin-top:20px;padding-top:12px;border-top:1px solid;font-size:11px;text-align:center}
            body.light .footer{border-top-color:#e5e5e7;color:#86868b}
            body.dark .footer{border-top-color:#3a3a3c;color:#8e8e93}
        </style>
        </head><body class="\(themeClass)">
        <div class="original-box"><strong>📝 原文：</strong><br>\(escaped)</div>
        \(html)
        <div class="footer">Powered by \(SettingsManager.shared.apiProvider.shortName) AI · ELTA — 截图即译，精读利器</div>
        </body></html>
        """
    }

    static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
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

    /// 解析单行表格为单元格数组
    private static func parseTableCells(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var cells = trimmed.components(separatedBy: "|")
        // 去除首尾空串（| 在收尾时产生）
        if cells.first?.trimmingCharacters(in: .whitespaces).isEmpty ?? false { cells.removeFirst() }
        if cells.last?.trimmingCharacters(in: .whitespaces).isEmpty ?? false { cells.removeLast() }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
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
