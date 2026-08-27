import Cocoa
import Carbon

// MARK: - 翻译流水线

final class TranslationPipeline {
    static let shared = TranslationPipeline()

    private var loadingPanel: NSPanel?

    /// 翻译任务代号：每次新任务 +1，用于 ESC 取消后丢弃旧任务结果
    private var currentTaskGeneration = 0
    private var loadingEscTap: CFMachPort?
    private var loadingEscRunLoopSource: CFRunLoopSource?

    /// 划词翻译触发时，记录前台应用的 PID，用于通过 Accessibility API 读取该应用的选中文本
    var selectionSourcePID: pid_t?

    /// 是否已触发过屏幕录制权限预检（TCC 弹窗只出现一次）
    private static var screenCapturePrimed = false
    /// 是否已触发过辅助功能权限预检（TCC 弹窗只出现一次）
    private static var accessibilityPrimed = false

    /// 权限决策结果：根据「是否已授权」与「本次调用前是否已触发过 TCC 弹窗」决定动作
    enum PermissionAction: Equatable {
        case proceed          // 已授权，继续翻译
        case primeAndAbort    // 首次未授权：触发系统 TCC 弹窗后中止（静默，只留系统弹窗）
        case guideAndAbort    // 已触发过 TCC 仍未授权（用户拒绝）：引导去系统设置后中止
    }

    /// 纯决策函数：把「是否授权 + 是否已触发过 TCC」映射为动作。可单测。
    static func resolvePermissionAction(isGranted: Bool, wasPrimed: Bool) -> PermissionAction {
        if isGranted { return .proceed }
        return wasPrimed ? .guideAndAbort : .primeAndAbort
    }

    func start() {
        logi("===== 翻译流水线开始 =====")
        // 检查是否已有翻译弹窗
        guard !ResultWindowController.shared.isPanelVisible else {
            showAlert("请先关闭上一个翻译弹窗", "关闭后即可开始新翻译。\n按 ESC 或点击弹窗左上角关闭按钮即可。")
            return
        }
        // 屏幕录制权限（截图翻译）：首次未授权触发 TCC 后静默中止，只留系统弹窗
        switch Self.resolvePermissionAction(isGranted: CGPreflightScreenCaptureAccess(),
                                            wasPrimed: Self.screenCapturePrimed) {
        case .proceed:
            break
        case .primeAndAbort:
            Self.screenCapturePrimed = true
            CGRequestScreenCaptureAccess()
            logi("屏幕录制权限: 未授权，TCC 弹窗已触发")
            return
        case .guideAndAbort:
            logi("屏幕录制权限: 仍未授权，静默中止")
            return
        }
        currentTaskGeneration += 1
        let generation = currentTaskGeneration
        ScreenshotEngine.shared.start { [weak self] rect, cgImage in
            guard let cgImage = cgImage, rect != .zero else {
                logi("截图取消或失败"); return
            }
            logi("截图成功: \(cgImage.width)x\(cgImage.height) px, 选区@(\(Int(rect.origin.x)),\(Int(rect.origin.y)))")
            self?.showLoading()

            DispatchQueue.global(qos: .userInitiated).async {
                // OCR（含坐标，用于表格检测与还原）
                logi("[Step 2] OCR 识别（含坐标）...")
                guard let blocks = OCREngine.shared.recognizeWithPositions(cgImage: cgImage), !blocks.isEmpty else {
                    // OCR 失败：仅当仍是当前任务时才清理 loading 并报错，避免误清新任务的弹窗/弹过期错误
                    guard generation == self?.currentTaskGeneration else { return }
                    self?.hideLoading()
                    self?.showError("OCR 未能识别到文字。\n请确认框选区域包含清晰文字，且文字不过小/模糊。")
                    return
                }

                // 表格检测：OCR 坐标 → Markdown 表格（或纯文本）
                let rawText = TableExtractor.process(blocks: blocks)
                let text = TextPreprocessor.condenseCitation(rawText)
                let isTable = text.contains("| -")
                logi("表格检测: \(isTable ? "是表格" : "纯文本"), \(blocks.count) 块文本")

                // ESC 已取消则不再发起翻译
                guard generation == self?.currentTaskGeneration else { return }

                // 翻译
                logi("[Step 3] AI 翻译...")
                TranslationEngine.shared.translate(text: text) { [weak self] result in
                    guard let self = self, generation == self.currentTaskGeneration else { return }
                    guard let result = result else {
                        self.hideLoading()
                        self.showError("AI 翻译失败。\nOCR 已识别文本：\n\(text.prefix(200))")
                        return
                    }
                    self.hideLoading()
                    ResultWindowController.shared.show(markdown: result, originalText: text, screenshotRect: rect)
                    NotificationManager.shared.show(title: APP_DISPLAY_NAME, body: "翻译完成，点击查看结果")
                    logi("流水线完成")
                }
            }
        }
    }

    /// 通过 macOS Accessibility API 读取指定应用（或系统全局）当前聚焦元素中的选中文本
    /// - Parameter pid: 目标应用的进程 PID；传 nil 则回退为系统全局聚焦元素（兼容旧逻辑）
    /// 不依赖剪贴板，也不需要模拟 Cmd+C，兼容性更好
    func getSelectedTextViaAccessibility(pid: pid_t? = nil) -> String? {
        // 检查辅助功能权限（权限提示已在 startTextTranslation 上游统一处理）
        guard AXIsProcessTrusted() else {
            logi("Accessibility：未获得辅助功能权限")
            return nil
        }

        // 定位聚焦元素：优先按 PID 定位目标 App，再读取其焦点元素
        let focusedElement: AXUIElement
        if let pid = pid, pid != 0 {
            let app = AXUIElementCreateApplication(pid)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
                  let _ = ref else {
                logi("Accessibility：无法获取 PID=\(pid) 的聚焦元素，回退系统全局")
                // 回退：使用系统全局
                let sys = AXUIElementCreateSystemWide()
                var sysRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &sysRef) == .success,
                      let _ = sysRef else {
                    logi("Accessibility：系统全局也无法获取聚焦元素")
                    return nil
                }
                focusedElement = sysRef as! AXUIElement
                return extractSelectedText(from: focusedElement)
            }
            focusedElement = ref as! AXUIElement
        } else {
            let system = AXUIElementCreateSystemWide()
            var focusedRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
                  let _ = focusedRef else {
                logi("Accessibility：无法获取聚焦元素")
                return nil
            }
            focusedElement = focusedRef as! AXUIElement
        }

        return extractSelectedText(from: focusedElement)
    }

    /// 从指定元素提取选中文本（通用逻辑）
    private func extractSelectedText(from element: AXUIElement) -> String? {
        // 先尝试 kAXSelectedTextAttribute
        var selectedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedValue) == .success,
           let text = selectedValue as? String, !text.isEmpty {
            logi("Accessibility：直接获取选中文本 \(text.count) 字符")
            return text
        }

        // 兜底：尝试 kAXValueAttribute，再过滤选中的部分
        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
           let fullText = valueRef as? String, !fullText.isEmpty {
            var selectedRangeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeRef) == .success,
               let rangeValue = selectedRangeRef {
                let axValue = rangeValue as! AXValue
                var range = CFRange(location: 0, length: 0)
                if AXValueGetValue(axValue, .cfRange, &range),
                   let selected = Self.substringInRange(fullText, cfLocation: range.location, cfLength: range.length) {
                    logi("Accessibility：按范围截取选中文本 \(selected.count) 字符")
                    return selected
                }
            }
            logi("Accessibility：无选中范围，回退到 Cmd+C")
            return nil
        }

        logi("Accessibility：未找到任何文本")
        return nil
    }

    /// 从 fullText 按 CFRange 截取子串，范围无效时返回 nil
    /// 注意：Accessibility API 的 CFRange 用 UTF-16 代码单元（NSString 语义），
    /// 不能直接用 Swift 的 String.count（grapheme cluster），否则含 emoji/生僻字时偏移错。
    static func substringInRange(_ fullText: String, cfLocation: Int, cfLength: Int) -> String? {
        let ns = fullText as NSString
        guard cfLocation >= 0,
              cfLength > 0,
              cfLocation + cfLength <= ns.length else {
            return nil
        }
        let selected = ns.substring(with: NSRange(location: cfLocation, length: cfLength))
        return selected.isEmpty ? nil : selected
    }

    /// 引导用户前往系统设置开启辅助功能权限
    /// 引导用户前往系统设置开启辅助功能权限（同一会话仅提示一次）
    private static var accessibilityPrompted = false

    private func promptAccessibilityPermission() {
        guard !Self.accessibilityPrompted else { return }
        Self.accessibilityPrompted = true
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "为了获取您在任意应用中选中的文本（划词翻译），ELTA 需要【辅助功能】权限。\n\n请前往 系统设置 → 隐私与安全性 → 辅助功能，找到并启用 ELTA。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    /// 划词翻译：读取选中文本 → 直接翻译（跳过截图+OCR）
    func startTextTranslation() {
        logi("===== 划词翻译流水线开始 =====")
        // 检查是否已有翻译弹窗
        guard !ResultWindowController.shared.isPanelVisible else {
            showAlert("请先关闭上一个翻译弹窗", "关闭后即可开始新翻译。\n按 ESC 或点击弹窗左上角关闭按钮即可。")
            return
        }
        // 辅助功能权限（划词翻译）：首次未授权触发 TCC 后静默中止，只留系统弹窗；
        // 已触发过仍未授权（用户拒绝）则弹引导框去系统设置
        switch Self.resolvePermissionAction(isGranted: AXIsProcessTrusted(),
                                            wasPrimed: Self.accessibilityPrimed) {
        case .proceed:
            break
        case .primeAndAbort:
            Self.accessibilityPrimed = true
            let sys = AXUIElementCreateSystemWide()
            var ref: CFTypeRef?
            AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &ref)
            logi("Accessibility 权限: 未授权，TCC 弹窗已触发")
            return
        case .guideAndAbort:
            promptAccessibilityPermission()
            return
        }
        currentTaskGeneration += 1
        let generation = currentTaskGeneration

        // 0. 记录触发时的鼠标位置（用于弹窗左右判断）
        let mouseLocation = NSEvent.mouseLocation

        // 1. 等待用户释放快捷键按键（Cmd/Shift）
        // 使用 RunLoop 而非 usleep：不彻底冻结主线程，事件循环可处理系统消息
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.3))

        // 2. 优先使用 Accessibility API 读取选中文本（最可靠）
        //    过滤掉 ELTA 自己的 PID：当旧弹窗在前台时，frontmost 可能是 ELTA 自己，
        //    此时应回退到系统全局聚焦元素，避免从弹窗里读取空文本。
        let effectivePID: pid_t?
        if let pid = selectionSourcePID, pid != pid_t(ProcessInfo.processInfo.processIdentifier) {
            effectivePID = pid
        } else {
            effectivePID = nil
        }
        var selectedText: String? = getSelectedTextViaAccessibility(pid: effectivePID)

        // 3. Accessibility 失败时，兜底使用 Cmd+C + 剪贴板
        if selectedText == nil || selectedText!.isEmpty {
            logi("Accessibility 未获取到文本，尝试 Cmd+C 兜底")
            selectedText = getSelectedTextViaCopyPasteboard()
        }

        guard let rawText = selectedText, !rawText.isEmpty else {
            showError("未能获取选中文本。\n可能原因：\n1. 未选中文本\n2. 未授予【辅助功能】权限（系统设置 → 隐私与安全性 → 辅助功能）")
            return
        }

        // 预处理：压缩 Apple Books 多行引用块为单行
        let text = TextPreprocessor.condenseCitation(rawText)

        logi("划词获取文本: len=\(text.count)")
        showTextLoading()

        // 4. 表格检测：Tab 分隔符（Excel/Sheets）→ Markdown 表格
        let processedText = TableExtractor.detectAndConvertTabSeparated(text)
        if processedText != text {
            logi("划词翻译: 检测到 Tab 分隔，已转为 Markdown 表格")
        }

        // 5. 直接翻译
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            TranslationEngine.shared.translate(text: processedText) { [weak self] result in
                guard let self = self, generation == self.currentTaskGeneration else { return }
                guard let result = result else {
                    self.hideLoading()
                    self.showError("AI 翻译失败。\n选中文本长度：\(text.count)")
                    return
                }
                self.hideLoading()
                let mouseRect = NSRect(x: mouseLocation.x - 5, y: mouseLocation.y - 5, width: 10, height: 10)
                ResultWindowController.shared.show(markdown: result, originalText: text, screenshotRect: mouseRect)
                NotificationManager.shared.show(title: APP_DISPLAY_NAME, body: "划词翻译完成，点击查看结果")
                logi("划词翻译流水线完成")
            }
        }
    }

    /// Cmd+C + 剪贴板兜底方案
    private func getSelectedTextViaCopyPasteboard() -> String? {
        let pasteboard = NSPasteboard.general
        let oldChangeCount = pasteboard.changeCount
        let oldSnapshot = PasteboardSnapshot.capture(from: pasteboard)
        let oldTextItems = oldSnapshot.items.compactMap { item -> String? in
            guard let data = item.types.first(where: { $0.type == .string })?.data else { return nil }
            return String(data: data, encoding: .utf8)
        }

        // 模拟 Cmd+C 复制选中文本
        // 关键：cmdDown 的 flags 必须为空（不能设 .maskCommand），否则系统认为事件矛盾
        let src = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
        let cDown   = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
        cDown?.flags = .maskCommand
        let cUp     = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        cUp?.flags  = .maskCommand
        let cmdUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)

        // 按键间隔：确保系统正确处理每个按键事件
        let keyPressDelay: useconds_t = 30_000
        let keyHoldDelay: useconds_t = 40_000

        // 用 RunLoop 而非 usleep 等待：不冻结主线程，事件循环可继续处理剪贴板更新
        func pump(_ us: useconds_t) {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: Double(us) / 1_000_000))
        }

        cmdDown?.post(tap: .cghidEventTap)
        pump(keyPressDelay)
        cDown?.post(tap: .cghidEventTap)
        pump(keyHoldDelay)
        cUp?.post(tap: .cghidEventTap)
        pump(keyPressDelay)
        cmdUp?.post(tap: .cghidEventTap)

        // 读取剪贴板（重试等待目标 App 处理 Cmd+C）
        var selectedText: String? = nil
        let maxRetries = 15
        for i in 0..<maxRetries {
            pump(100_000)  // 每次等待 100ms，总计最多 1.5 秒
            if pasteboard.changeCount != oldChangeCount,
               let newText = pasteboard.string(forType: .string),
               !newText.isEmpty {
                selectedText = newText
                logi("Cmd+C 获取成功（重试 \(i + 1) 次）")
                break
            }
        }
        // 兜底：changeCount 没变但内容确实变了（部分 App 不更新 changeCount）
        if selectedText == nil,
           let newText = pasteboard.string(forType: .string),
           !newText.isEmpty,
           !oldTextItems.contains(newText) {
            selectedText = newText
            logi("Cmd+C 获取成功（兜底读取）")
        }

        // 恢复旧剪贴板（保留所有类型；空快照则恢复成空，清除 Cmd+C 残留）
        oldSnapshot.restore(to: pasteboard)
        logi("剪贴板已恢复（\(oldSnapshot.items.count) 个条目）")

        return selectedText
    }

    private func showTextLoading() {
        DispatchQueue.main.async { [weak self] in
            self?.showLoadingPanel(title: "正在翻译...", subtitle: "划词翻译 → AI 翻译分析")
        }
    }

    private func showLoading() {
        DispatchQueue.main.async { [weak self] in
            self?.showLoadingPanel(title: "正在识别与翻译...", subtitle: "OCR 识别 → AI 翻译分析")
        }
    }

    private func hideLoading() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.removeLoadingEscTap()
            self.loadingPanel?.close()
            self.loadingPanel = nil
        }
    }

    private func showLoadingPanel(title: String, subtitle: String) {
        guard loadingPanel == nil else { return }
        let w: CGFloat = 300, h: CGFloat = 140
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                            styleMask: [.titled, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = APP_DISPLAY_NAME
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.setFrameOrigin(loadingPanelOrigin(size: NSSize(width: w, height: h)))
        panel.makeKeyAndOrderFront(nil)

        let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        let spinner = NSProgressIndicator(frame: NSRect(x: (w - 40) / 2, y: 60, width: 40, height: 40))
        spinner.style = .spinning; spinner.startAnimation(nil); v.addSubview(spinner)

        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 0, y: 30, width: w, height: 24); label.alignment = .center
        label.font = .systemFont(ofSize: 14); v.addSubview(label)

        let sub = NSTextField(labelWithString: subtitle)
        sub.frame = NSRect(x: 0, y: 12, width: w, height: 18); sub.alignment = .center
        sub.font = .systemFont(ofSize: 11); sub.textColor = .secondaryLabelColor; v.addSubview(sub)

        panel.contentView = v
        loadingPanel = panel
        installLoadingEscTap()
    }

    /// 取消当前翻译：代号失效 + 取消网络请求 + 关闭 loading 面板
    private func cancelCurrentTranslation() {
        currentTaskGeneration += 1
        TranslationEngine.shared.cancelCurrentTask()
        hideLoading()
        logi("用户 ESC 取消了翻译任务")
    }

    /// 安装 loading 期间的 ESC 拦截（裸 ESC，无修饰键）
    private func installLoadingEscTap() {
        guard loadingEscTap == nil else { return }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { (proxy, type, event, info) -> Unmanaged<CGEvent>? in
            guard let info = info else { return Unmanaged.passUnretained(event) }
            let pipeline = Unmanaged<TranslationPipeline>.fromOpaque(info).takeUnretainedValue()
            guard pipeline.loadingPanel != nil else { return Unmanaged.passUnretained(event) }

            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            guard keyCode == 0x35 else { return Unmanaged.passUnretained(event) }  // ESC

            let flags = event.flags
            if flags.contains(.maskCommand) || flags.contains(.maskControl)
                || flags.contains(.maskAlternate) || flags.contains(.maskShift) {
                return Unmanaged.passUnretained(event)
            }

            DispatchQueue.main.async { pipeline.cancelCurrentTranslation() }
            return nil
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: callback,
            userInfo: selfPtr
        ) else {
            logi("Loading ESC tap: 创建失败（可能缺少 Accessibility 权限）")
            return
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        loadingEscTap = tap
        loadingEscRunLoopSource = runLoopSource
        logi("Loading ESC tap: 已安装")
    }

    private func removeLoadingEscTap() {
        guard let tap = loadingEscTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = loadingEscRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        loadingEscTap = nil
        loadingEscRunLoopSource = nil
        logi("Loading ESC tap: 已移除")
    }

    private func loadingPanelOrigin(size: NSSize) -> NSPoint {
        let pos = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pos) }) ?? NSScreen.main else {
            return NSPoint(x: 100, y: 100)
        }
        let vf = screen.visibleFrame
        let x = vf.midX - size.width / 2
        let y = vf.midY - size.height / 2
        return NSPoint(x: x, y: y)
    }

    private func showAlert(_ title: String, _ message: String) {
        DispatchQueue.main.async {
            // 临时切换激活策略为 regular，确保在全屏 Space 中能获取焦点
            let currentPolicy = NSApp.activationPolicy()
            if currentPolicy != .regular { NSApp.setActivationPolicy(.regular) }

            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "确定")
            // 确保弹窗在所有空间（含全屏）的顶层显示
            alert.window.level = .floating
            alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSApp.deactivate()
            if currentPolicy != .regular { NSApp.setActivationPolicy(currentPolicy) }
        }
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            // 临时切换激活策略为 regular，确保在全屏 Space 中能获取焦点
            let currentPolicy = NSApp.activationPolicy()
            if currentPolicy != .regular { NSApp.setActivationPolicy(.regular) }

            let alert = NSAlert()
            alert.messageText = "翻译失败"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            // 确保弹窗在所有空间（含全屏）的顶层显示
            alert.window.level = .floating
            alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSApp.deactivate()
            // 恢复原来的激活策略
            if currentPolicy != .regular { NSApp.setActivationPolicy(currentPolicy) }
        }
    }
}
