import Cocoa
import Carbon
import UserNotifications

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyRef: EventHotKeyRef?
    private var selectionHotkeyRef: EventHotKeyRef?
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
        if settings.activeApiKey == nil || settings.activeApiKey!.isEmpty {
            logi("首次运行，API Key 未配置")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSApp.activate(ignoringOtherApps: true)
            SettingsWindowController.shared.show()
        }

        logi("\(APP_DISPLAY_NAME) 就绪 — Cmd+T 截图翻译 | Shift+Cmd+T 划词翻译 | 点击菜单栏 📖 操作")

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

        // ---- 截图翻译热键（id=1） ----
        var hotkeyID1 = EventHotKeyID(signature: 0x534E5452, id: 1)  // "SNTR"
        let keyCode = settings.hotkeyKeyCode
        let modifiers = settings.hotkeyModifiers
        let s1 = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotkeyID1,
                                      GetApplicationEventTarget(), 0, &hotkeyRef)
        if s1 != noErr {
            hotkeyID1.id = 2
            let fbStatus = RegisterEventHotKey(0x78, UInt32(controlKey), hotkeyID1,
                                                GetApplicationEventTarget(), 0, &hotkeyRef)
            if fbStatus == noErr {
                settings.hotkeyKeyCode = 0x78; settings.hotkeyModifiers = Int(controlKey)
                settings.hotkeyDisplay = "⌃F2"
                logi("截图快捷键降级为 Ctrl+F2")
            } else { loge("截图快捷键注册失败") }
        } else {
            settings.hotkeyDisplay = hotkeyDisplayString(keyCode: keyCode, modifiers: modifiers)
            logi("截图快捷键: \(settings.hotkeyDisplay)")
        }

        // ---- 划词翻译热键（id=10） ----
        var hotkeyID10 = EventHotKeyID(signature: 0x534E5452, id: 10)
        let selKeyCode = settings.selectionHotkeyKeyCode
        let selMods = settings.selectionHotkeyModifiers
        let s10 = RegisterEventHotKey(UInt32(selKeyCode), UInt32(selMods), hotkeyID10,
                                       GetApplicationEventTarget(), 0, &selectionHotkeyRef)
        if s10 == noErr {
            settings.selectionHotkeyDisplay = hotkeyDisplayString(keyCode: selKeyCode, modifiers: selMods)
            logi("划词快捷键: \(settings.selectionHotkeyDisplay)")
        } else {
            // 降级：Ctrl+Shift+F2
            hotkeyID10.id = 11
            let fb2 = RegisterEventHotKey(0x78, UInt32(controlKey | shiftKey), hotkeyID10,
                                           GetApplicationEventTarget(), 0, &selectionHotkeyRef)
            if fb2 == noErr {
                settings.selectionHotkeyKeyCode = 0x78
                settings.selectionHotkeyModifiers = Int(controlKey | shiftKey)
                settings.selectionHotkeyDisplay = "⇧⌃F2"
                logi("划词快捷键降级为 ⇧⌃F2")
            } else { loge("划词快捷键注册失败") }
        }

        // 事件处理器（只安装一次，按 id 分发）
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
                // 在快捷键事件上下文中立即捕获前台应用的 PID，
                // 避免 dispatch async 之后焦点已转移到自身导致读取失败
                let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                // 如果当前前台应用是 ELTA 自己（比如旧弹窗在最前），
                // 传 nil 给划词翻译，让它回退到系统全局聚焦元素读取文本。
                let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)
                let effectivePID: pid_t? = (frontPID == ownPID) ? nil : frontPID
                DispatchQueue.main.async {
                    if hkID.id == 10 || hkID.id == 11 {
                        // 划词翻译
                        TranslationPipeline.shared.selectionSourcePID = effectivePID
                        TranslationPipeline.shared.startTextTranslation()
                    } else {
                        // 截图翻译
                        TranslationPipeline.shared.start()
                    }
                }
            }
            return noErr
        }, 1, &eventSpec, nil, nil)
    }

    @objc func screenshotTranslate() {
        TranslationPipeline.shared.start()
    }

    @objc func selectionTranslate() {
        TranslationPipeline.shared.startTextTranslation()
    }

    @objc func openSettings() {
        SettingsWindowController.shared.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ScreenshotEngine.shared.cleanup()
        if let ref = hotkeyRef { UnregisterEventHotKey(ref) }
        if let ref = selectionHotkeyRef { UnregisterEventHotKey(ref) }
        logi("\(APP_DISPLAY_NAME) 已退出")
    }
}
