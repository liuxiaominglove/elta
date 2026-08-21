import Cocoa
import Carbon
import UserNotifications

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkeyRef: EventHotKeyRef?
    private var selectionHotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let settings = SettingsManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 常规应用模式：有 Dock 图标 + 顶部菜单栏（退出通道可靠）
        NSApp.setActivationPolicy(.regular)
        buildMainMenu()

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

        logi("\(APP_DISPLAY_NAME) 就绪 — Cmd+T 截图翻译 | Shift+Cmd+T 划词翻译 | 点击菜单栏 📖 操作")

        // 后台检查更新
        UpdateChecker.shared.check()
    }

    /// 构建顶部菜单栏 App 菜单（含「退出」），确保常规退出通道可用
    private func buildMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        let appName = APP_DISPLAY_NAME
        appMenu.addItem(withTitle: "关于 \(appName)",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 \(appName)",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 \(appName)",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        NSApp.mainMenu = mainMenu
    }

    /// 点击 Dock 图标时弹出设置窗口
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

        // 事件处理器 — 先移除旧的再安装新的，防止重复累积
        if let oldHandler = eventHandlerRef {
            RemoveEventHandler(oldHandler)
            eventHandlerRef = nil
        }
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(GetApplicationEventTarget(),
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
                    } else {
                        TranslationPipeline.shared.start()
                    }
                }
            }
            return noErr
        }, 1, &eventSpec, nil, &eventHandlerRef)
        if installStatus != noErr {
            loge("键盘事件处理器安装失败: OSStatus=\(installStatus)")
            failures.append((name: "键盘事件处理器", display: "", reason: "安装失败 OSStatus=\(installStatus)"))
            // 处理器安装失败：注销已注册的热键，避免「占用按键却不触发」的残留状态
            if let ref = hotkeyRef { UnregisterEventHotKey(ref); hotkeyRef = nil }
            if let ref = selectionHotkeyRef { UnregisterEventHotKey(ref); selectionHotkeyRef = nil }
        }

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

    @objc func openSettings() {
        SettingsWindowController.shared.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        ScreenshotEngine.shared.cleanup()
        if let ref = hotkeyRef { UnregisterEventHotKey(ref) }
        if let ref = selectionHotkeyRef { UnregisterEventHotKey(ref) }
        if let ref = eventHandlerRef { RemoveEventHandler(ref) }
        logi("\(APP_DISPLAY_NAME) 已退出")
    }
}
