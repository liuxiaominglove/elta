import Cocoa
import Carbon

// MARK: - 翻译流水线

final class TranslationPipeline {
    static let shared = TranslationPipeline()

    private var loadingPanel: NSPanel?

    /// 划词翻译触发时，记录前台应用的 PID，用于通过 Accessibility API 读取该应用的选中文本
    var selectionSourcePID: pid_t?

    /// 是否已触发过屏幕录制权限预检（TCC 弹窗只出现一次）
    private static var screenCapturePrimed = false
    /// 是否已触发过辅助功能权限预检（TCC 弹窗只出现一次）
    private static var accessibilityPrimed = false

    /// 在首次截图或划词操作时，同时触发两个系统权限弹窗：
    /// 1. 辅助功能（Accessibility）— 划词翻译需要
    /// 2. 屏幕录制（Screen Recording）— 截图翻译需要
    /// 两者均使用非阻塞 API，确保无论用户先按哪个快捷键，两次 TCC 弹窗都会出现
    private func primePermissionsIfNeeded() {
        // 1. 屏幕录制权限（截图翻译需要）— 使用非阻塞 API 避免卡住后续的 Accessibility 弹窗
        if !Self.screenCapturePrimed {
            Self.screenCapturePrimed = true
            logi("Prime: 预触发屏幕录制权限")
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
                logi("屏幕录制权限: 未授权，TCC 弹窗已触发")
            } else {
                logi("屏幕录制权限: 已授权")
            }
        }

        // 2. 辅助功能权限（划词翻译需要）— AXUIElement 调用是非阻塞的，不会互相干扰
        if !Self.accessibilityPrimed {
            Self.accessibilityPrimed = true
            logi("Prime: 预触发辅助功能权限")
            if !AXIsProcessTrusted() {
                let sys = AXUIElementCreateSystemWide()
                var ref: CFTypeRef?
                AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &ref)
                logi("Accessibility 权限: 未授权，TCC 弹窗已触发")
            } else {
                logi("Accessibility 权限: 已授权")
            }
        }

        if !Self.screenCapturePrimed || !Self.accessibilityPrimed {
            // 仍可能有一项未触发（首次调用时两者都会设为 true，所以这个分支实际只在异常情况进入）
            logi("Prime: 权限弹窗已触发，请在系统设置中授权")
        }
    }

    func start() {
        logi("===== 翻译流水线开始 =====")
        primePermissionsIfNeeded()
        ScreenshotEngine.shared.start { [weak self] rect, cgImage in
            guard let cgImage = cgImage, rect != .zero else {
                logi("截图取消或失败"); return
            }
            logi("截图成功: \(cgImage.width)x\(cgImage.height) px, 选区@(\(Int(rect.origin.x)),\(Int(rect.origin.y)))")
            self?.showLoading()

            DispatchQueue.global(qos: .userInitiated).async {
                // OCR（直接传原始 CGImage，不做 NSImage 包装）
                logi("[Step 2] OCR 识别...")
                guard let text = OCREngine.shared.recognize(cgImage: cgImage) else {
                    self?.hideLoading()
                    self?.showError("OCR 未能识别到文字。\n请确认框选区域包含清晰文字，且文字不过小/模糊。")
                    return
                }

                // 翻译
                logi("[Step 3] AI 翻译...")
                guard let result = TranslationEngine.shared.translate(text: text) else {
                    self?.hideLoading()
                    self?.showError("AI 翻译失败。\nOCR 已识别文本：\n\(text.prefix(200))")
                    return
                }

                self?.hideLoading()
                ResultWindowController.shared.show(markdown: result, originalText: text, screenshotRect: rect)
                NotificationManager.shared.show(title: APP_DISPLAY_NAME, body: "翻译完成，点击查看结果")
                logi("流水线完成")
            }
        }
    }

    /// 通过 macOS Accessibility API 读取指定应用（或系统全局）当前聚焦元素中的选中文本
    /// - Parameter pid: 目标应用的进程 PID；传 nil 则回退为系统全局聚焦元素（兼容旧逻辑）
    /// 不依赖剪贴板，也不需要模拟 Cmd+C，兼容性更好
    private func getSelectedTextViaAccessibility(pid: pid_t? = nil) -> String? {
        // 检查辅助功能权限
        guard AXIsProcessTrusted() else {
            logi("Accessibility：未获得辅助功能权限，提示用户授权")
            DispatchQueue.main.async {
                self.promptAccessibilityPermission()
            }
            return nil
        }

        // 定位聚焦元素：优先按 PID 定位目标 App，再读取其焦点元素
        let focusedElement: AXUIElement
        if let pid = pid, pid != 0 {
            let app = AXUIElementCreateApplication(pid)
            var ref: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &ref) == .success,
                  let element = ref else {
                logi("Accessibility：无法获取 PID=\(pid) 的聚焦元素，回退系统全局")
                // 回退：使用系统全局
                let sys = AXUIElementCreateSystemWide()
                var sysRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &sysRef) == .success,
                      let sysElement = sysRef else {
                    logi("Accessibility：系统全局也无法获取聚焦元素")
                    return nil
                }
                focusedElement = sysElement as! AXUIElement
                return extractSelectedText(from: focusedElement)
            }
            focusedElement = element as! AXUIElement
        } else {
            let system = AXUIElementCreateSystemWide()
            var focusedRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
                  let element = focusedRef else {
                logi("Accessibility：无法获取聚焦元素")
                return nil
            }
            focusedElement = element as! AXUIElement
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
               let rangeValue = selectedRangeRef,
               CFGetTypeID(rangeValue) == AXValueGetTypeID() {
                let axValue = rangeValue as! AXValue
                var range = CFRange(location: 0, length: 0)
                if AXValueGetValue(axValue, .cfRange, &range) {
                    let nsRange = NSRange(location: range.location, length: range.length)
                    if nsRange.location != NSNotFound,
                       nsRange.location >= 0,
                       nsRange.location + nsRange.length <= fullText.count {
                        let start = fullText.index(fullText.startIndex, offsetBy: nsRange.location)
                        let end = fullText.index(start, offsetBy: nsRange.length)
                        let selected = String(fullText[start..<end])
                        if !selected.isEmpty {
                            logi("Accessibility：按范围截取选中文本 \(selected.count) 字符")
                            return selected
                        }
                    }
                }
            }
            logi("Accessibility：未拿到范围，使用完整文本兜底 \(fullText.count) 字符")
            return fullText
        }

        logi("Accessibility：未找到任何文本")
        return nil
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
        primePermissionsIfNeeded()

        // 0. 记录触发时的鼠标位置（用于弹窗左右判断）
        let mouseLocation = NSEvent.mouseLocation

        // 1. 等待用户释放快捷键按键（Cmd/Shift）
        usleep(300_000)  // 300ms

        // 2. 优先使用 Accessibility API 读取选中文本（最可靠）
        //    传入快捷键触发时捕获的前台应用 PID，确保从正确的应用读取焦点元素
        var selectedText: String? = getSelectedTextViaAccessibility(pid: selectionSourcePID)

        // 3. Accessibility 失败时，兜底使用 Cmd+C + 剪贴板
        if selectedText == nil || selectedText!.isEmpty {
            logi("Accessibility 未获取到文本，尝试 Cmd+C 兜底")
            selectedText = getSelectedTextViaCopyPasteboard()
        }

        guard let text = selectedText, !text.isEmpty else {
            showError("未能获取选中文本。\n可能原因：\n1. 未选中文本\n2. 未授予【辅助功能】权限（系统设置 → 隐私与安全性 → 辅助功能）")
            return
        }

        logi("划词获取文本: \(text.prefix(100))...")
        showTextLoading()

        // 4. 直接翻译
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let result = TranslationEngine.shared.translate(text: text) else {
                self?.hideLoading()
                self?.showError("AI 翻译失败。\n选中文本：\n\(text.prefix(200))")
                return
            }
            self?.hideLoading()
            // 用鼠标位置构造一个小矩形，让弹窗知道用户在哪一侧屏幕
            let mouseRect = NSRect(x: mouseLocation.x - 5, y: mouseLocation.y - 5, width: 10, height: 10)
            ResultWindowController.shared.show(markdown: result, originalText: text, screenshotRect: mouseRect)
            NotificationManager.shared.show(title: APP_DISPLAY_NAME, body: "划词翻译完成，点击查看结果")
            logi("划词翻译流水线完成")
        }
    }

    /// Cmd+C + 剪贴板兜底方案
    private func getSelectedTextViaCopyPasteboard() -> String? {
        let pasteboard = NSPasteboard.general
        let oldChangeCount = pasteboard.changeCount
        let oldItems = pasteboard.pasteboardItems?.compactMap { $0.string(forType: .string) } ?? []

        // 模拟 Cmd+C 复制选中文本
        // 关键：cmdDown 的 flags 必须为空（不能设 .maskCommand），否则系统认为事件矛盾
        let src = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
        let cDown   = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
        cDown?.flags = .maskCommand
        let cUp     = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        cUp?.flags  = .maskCommand
        let cmdUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)

        cmdDown?.post(tap: .cghidEventTap)
        usleep(30_000)
        cDown?.post(tap: .cghidEventTap)
        usleep(40_000)
        cUp?.post(tap: .cghidEventTap)
        usleep(30_000)
        cmdUp?.post(tap: .cghidEventTap)

        // 读取剪贴板（重试等待目标 App 处理 Cmd+C）
        var selectedText: String? = nil
        let maxRetries = 15
        for i in 0..<maxRetries {
            usleep(100_000)  // 每次等待 100ms，总计最多 1.5 秒
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
           !oldItems.contains(newText) {
            selectedText = newText
            logi("Cmd+C 获取成功（兜底读取）")
        }

        // 恢复旧剪贴板（如果可能）
        if !oldItems.isEmpty {
            pasteboard.clearContents()
            pasteboard.writeObjects(oldItems as [NSPasteboardWriting])
        }

        return selectedText
    }

    private func showTextLoading() {
        DispatchQueue.main.async { [weak self] in self?.showTextLoadingPanel() }
    }

    private func showTextLoadingPanel() {
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
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        let spinner = NSProgressIndicator(frame: NSRect(x: (w - 40) / 2, y: 60, width: 40, height: 40))
        spinner.style = .spinning; spinner.startAnimation(nil); v.addSubview(spinner)

        let label = NSTextField(labelWithString: "正在翻译...")
        label.frame = NSRect(x: 0, y: 30, width: w, height: 24); label.alignment = .center
        label.font = .systemFont(ofSize: 14); v.addSubview(label)

        let sub = NSTextField(labelWithString: "划词翻译 → AI 翻译分析")
        sub.frame = NSRect(x: 0, y: 12, width: w, height: 18); sub.alignment = .center
        sub.font = .systemFont(ofSize: 11); sub.textColor = .secondaryLabelColor; v.addSubview(sub)

        panel.contentView = v
        loadingPanel = panel
    }

    private func showLoading() {
        DispatchQueue.main.async { [weak self] in self?.showLoadingPanel() }
    }

    private func hideLoading() {
        DispatchQueue.main.async { [weak self] in
            self?.loadingPanel?.close()
            self?.loadingPanel = nil
        }
    }

    private func showLoadingPanel() {
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
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        let v = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        let spinner = NSProgressIndicator(frame: NSRect(x: (w - 40) / 2, y: 60, width: 40, height: 40))
        spinner.style = .spinning; spinner.startAnimation(nil); v.addSubview(spinner)

        let label = NSTextField(labelWithString: "正在识别与翻译...")
        label.frame = NSRect(x: 0, y: 30, width: w, height: 24); label.alignment = .center
        label.font = .systemFont(ofSize: 14); v.addSubview(label)

        let sub = NSTextField(labelWithString: "OCR 识别 → AI 翻译分析")
        sub.frame = NSRect(x: 0, y: 12, width: w, height: 18); sub.alignment = .center
        sub.font = .systemFont(ofSize: 11); sub.textColor = .secondaryLabelColor; v.addSubview(sub)

        panel.contentView = v
        loadingPanel = panel
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async {
            // 临时切换激活策略为 regular，确保在全屏 Space 中能获取焦点
            let currentPolicy = NSApp.activationPolicy()
            if currentPolicy != .regular { NSApp.setActivationPolicy(.regular) }
            usleep(80_000)  // 等待系统处理策略切换

            let alert = NSAlert()
            alert.messageText = "翻译失败"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.window.level = .screenSaver
            alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            NSApp.deactivate()
            // 恢复原来的激活策略
            if currentPolicy != .regular { NSApp.setActivationPolicy(currentPolicy) }
        }
    }
}
