import Cocoa
import Carbon
import UserNotifications

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyRef: EventHotKeyRef?
    private var selectionHotkeyRef: EventHotKeyRef?
    private var hoverHotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let settings = SettingsManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 后台应用模式（菜单栏运行）— 保障全局热键 + 全屏 Space 截图正常
        NSApp.setActivationPolicy(.accessory)

        // 稍后显示 Dock 图标（使用 kCurrentProcess 常量，避免已废弃的 GetCurrentProcess）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kCurrentProcess))
            TransformProcessType(&psn, ProcessApplicationTransformState(kProcessTransformToForegroundApplication))
        }

        // 注册通知
        _ = NotificationManager.shared

        // 设置菜单栏
        StatusBarController.shared.setup()

        // 注册全局快捷键
        registerHotkey()

        // 启动时弹出设置窗口
        if settings.activeApiKey?.isEmpty ?? true {
            logi("首次运行，API Key 未配置")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSApp.activate(ignoringOtherApps: true)
            SettingsWindowController.shared.show()
        }

        logi("\(APP_DISPLAY_NAME) 就绪 — Cmd+T 截图翻译 | Shift+Cmd+T 划词翻译 | ⌥⌘T 悬停翻译 | 点击菜单栏 📖 操作")

        // 后台检查更新
        UpdateChecker.shared.check()
    }

    /// 点击 Dock 图标时弹出设置窗口（保持 .accessory，不切换策略）
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    private func registerHotkey() {
        reregisterHotkey()
    }

    /// 重新注册快捷键（用户更改设置后调用）
    func reregisterHotkey() {
        // 先注销旧的
        if let ref = hotkeyRef { UnregisterEventHotKey(ref); hotkeyRef = nil }
        if let ref = selectionHotkeyRef { UnregisterEventHotKey(ref); selectionHotkeyRef = nil }
        if let ref = hoverHotkeyRef { UnregisterEventHotKey(ref); hoverHotkeyRef = nil }

        // 收集注册失败的热键：不再降级、不覆盖用户偏好，改为提示用户去修改
        var failures: [(name: String, display: String, reason: String)] = []

        // ---- 截图翻译热键（id=1） ----
        let hotkeyID1 = EventHotKeyID(signature: 0x534E5452, id: 1)  // "SNTR"
        let keyCode = settings.hotkeyKeyCode
        let modifiers = settings.hotkeyModifiers
        let s1 = RegisterEventHotKey(sanitizeHotkeyCode(keyCode), sanitizeHotkeyCode(modifiers), hotkeyID1,
                                      GetApplicationEventTarget(), 0, &hotkeyRef)
        if s1 != noErr {
            failures.append((name: "截图翻译",
                             display: hotkeyDisplayString(keyCode: keyCode, modifiers: modifiers),
                             reason: checkSystemHotkeyConflict(modifiers: modifiers, keyCode: keyCode) ?? "该键已被其他程序占用"))
            loge("截图快捷键注册失败")
        } else {
            settings.hotkeyDisplay = hotkeyDisplayString(keyCode: keyCode, modifiers: modifiers)
            logi("截图快捷键: \(settings.hotkeyDisplay)")
        }

        // ---- 划词翻译热键（id=10） ----
        let hotkeyID10 = EventHotKeyID(signature: 0x534E5452, id: 10)
        let selKeyCode = settings.selectionHotkeyKeyCode
        let selMods = settings.selectionHotkeyModifiers
        let s10 = RegisterEventHotKey(sanitizeHotkeyCode(selKeyCode), sanitizeHotkeyCode(selMods), hotkeyID10,
                                       GetApplicationEventTarget(), 0, &selectionHotkeyRef)
        if s10 == noErr {
            settings.selectionHotkeyDisplay = hotkeyDisplayString(keyCode: selKeyCode, modifiers: selMods)
            logi("划词快捷键: \(settings.selectionHotkeyDisplay)")
        } else {
            failures.append((name: "划词翻译",
                             display: hotkeyDisplayString(keyCode: selKeyCode, modifiers: selMods),
                             reason: checkSystemHotkeyConflict(modifiers: selMods, keyCode: selKeyCode) ?? "该键已被其他程序占用"))
            loge("划词快捷键注册失败")
        }

        // ---- 悬停翻译热键（id=20） ----
        let hotkeyID20 = EventHotKeyID(signature: 0x534E5452, id: 20)
        let hoverKeyCode = settings.hoverHotkeyKeyCode
        let hoverMods = settings.hoverHotkeyModifiers
        let s20 = RegisterEventHotKey(sanitizeHotkeyCode(hoverKeyCode), sanitizeHotkeyCode(hoverMods), hotkeyID20,
                                       GetApplicationEventTarget(), 0, &hoverHotkeyRef)
        if s20 == noErr {
            settings.hoverHotkeyDisplay = hotkeyDisplayString(keyCode: hoverKeyCode, modifiers: hoverMods)
            logi("悬停快捷键: \(settings.hoverHotkeyDisplay)")
        } else {
            failures.append((name: "悬停翻译",
                             display: hotkeyDisplayString(keyCode: hoverKeyCode, modifiers: hoverMods),
                             reason: checkSystemHotkeyConflict(modifiers: hoverMods, keyCode: hoverKeyCode) ?? "该键已被其他程序占用"))
            loge("悬停快捷键注册失败")
        }

        // 事件处理器 — 先移除旧的再安装新的，防止重复累积
        if let oldHandler = eventHandlerRef {
            RemoveEventHandler(oldHandler)
            eventHandlerRef = nil
        }
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(),
        { (_, evt, _) -> OSStatus in
            var hkID = EventHotKeyID()
            let err = GetEventParameter(evt, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            if err == noErr {
                let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
                let effectivePID: pid_t? = (frontPID == ownPID) ? nil : frontPID
                DispatchQueue.main.async {
                    if hkID.id == 10 || hkID.id == 11 {
                        TranslationPipeline.shared.selectionSourcePID = effectivePID
                        TranslationPipeline.shared.startTextTranslation()
                    } else if hkID.id == 20 || hkID.id == 21 {
                        TranslationPipeline.shared.startHoverTranslation()
                    } else {
                        TranslationPipeline.shared.start()
                    }
                }
            }
            return noErr
        }, 1, &eventSpec, nil, &eventHandlerRef)

        // 注册失败时提示用户去设置修改（启动与保存设置时均触发）
        if !failures.isEmpty {
            presentHotkeyConflictAlert(failures)
        }
    }

    /// 弹出「快捷键注册失败」汇总提示，引导用户去设置修改，不静默降级、不覆盖用户偏好
    private func presentHotkeyConflictAlert(_ failures: [(name: String, display: String, reason: String)]) {
        let details = failures.map { "\($0.name)「\($0.display)」：\($0.reason)" }.joined(separator: "\n")
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "快捷键注册失败"
            alert.informativeText = "以下快捷键无法使用：\n\n\(details)\n\n请前往 设置 → 快捷键，修改为其他组合。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "知道了")
            alert.window.level = .floating
            alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc func screenshotTranslate() {
        TranslationPipeline.shared.start()
    }

    @objc func selectionTranslate() {
        TranslationPipeline.shared.startTextTranslation()
    }

    @objc func hoverTranslate() {
        TranslationPipeline.shared.startHoverTranslation()
    }

    @objc func openSettings() {
        SettingsWindowController.shared.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ScreenshotEngine.shared.cleanup()
        if let ref = hotkeyRef { UnregisterEventHotKey(ref) }
        if let ref = selectionHotkeyRef { UnregisterEventHotKey(ref) }
        if let ref = hoverHotkeyRef { UnregisterEventHotKey(ref) }
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
        logi("\(APP_DISPLAY_NAME) 已退出")
    }
}
