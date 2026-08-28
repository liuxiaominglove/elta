import Cocoa
import Carbon
import Foundation

func runSettingsManagerTests() {
    print("\n--- SettingsManager Tests ---")

    test("SettingsManager shared instance is non-nil") {
        let _ = try assertNotNil(SettingsManager.shared as Any?)
    }

    test("default provider is deepseek") {
        UserDefaults.standard.removeObject(forKey: "snaptranslate.apiProvider")
        defer { UserDefaults.standard.removeObject(forKey: "snaptranslate.apiProvider") }
        try assertEqual(SettingsManager.shared.apiProvider, .deepseek)
    }

    test("set provider to qwen works") {
        SettingsManager.shared.apiProvider = .qwen
        try assertEqual(SettingsManager.shared.apiProvider, .qwen)
    }

    test("invalid provider rawValue falls back to deepseek") {
        // Setting the raw value directly to an invalid string
        UserDefaults.standard.set("nonexistent", forKey: "snaptranslate.apiProvider")
        defer { UserDefaults.standard.removeObject(forKey: "snaptranslate.apiProvider") }
        try assertEqual(SettingsManager.shared.apiProvider, .deepseek)
    }

    test("hotkeyKeyCode has valid default between 0-127") {
        let code = SettingsManager.shared.hotkeyKeyCode
        try assertTrue(code >= 0 && code < 128, "KeyCode should be between 0 and 127, got \(code)")
    }

    test("hotkeyModifiers has valid default (non-zero)") {
        let mod = SettingsManager.shared.hotkeyModifiers
        try assertTrue(mod != 0, "Modifiers should be non-zero")
    }

    test("setting hotkey keyCode works") {
        let orig = SettingsManager.shared.hotkeyKeyCode
        defer { SettingsManager.shared.hotkeyKeyCode = orig }
        SettingsManager.shared.hotkeyKeyCode = 0x03 // F key
        try assertEqual(SettingsManager.shared.hotkeyKeyCode, 0x03)
    }

    test("hotkeyKeyCode=0 (A key) is preserved, NOT default T key") {
        let orig = SettingsManager.shared.hotkeyKeyCode
        defer { SettingsManager.shared.hotkeyKeyCode = orig }
        SettingsManager.shared.hotkeyKeyCode = 0
        try assertEqual(SettingsManager.shared.hotkeyKeyCode, 0)
    }

    test("hotkeyModifiers=0 preserved, NOT replaced by controlKey") {
        let orig = SettingsManager.shared.hotkeyModifiers
        defer { SettingsManager.shared.hotkeyModifiers = orig }
        SettingsManager.shared.hotkeyModifiers = 0
        try assertEqual(SettingsManager.shared.hotkeyModifiers, 0)
    }

    test("selectionHotkeyKeyCode=0 preserved, NOT default") {
        let orig = SettingsManager.shared.selectionHotkeyKeyCode
        defer { SettingsManager.shared.selectionHotkeyKeyCode = orig }
        SettingsManager.shared.selectionHotkeyKeyCode = 0
        try assertEqual(SettingsManager.shared.selectionHotkeyKeyCode, 0)
    }

    test("selectionHotkeyModifiers has ctrl+shift default") {
        UserDefaults.standard.removeObject(forKey: "snaptranslate.selectionHotkeyModifiers")
        let mod = SettingsManager.shared.selectionHotkeyModifiers
        try assertEqual(mod, Int(controlKey | shiftKey))
    }

    test("selectionHotkeyModifiers=0 preserved, NOT ctrl+shift") {
        let orig = SettingsManager.shared.selectionHotkeyModifiers
        defer {
            // 恢复原始值；若 orig 也是 0 则清空 key 避免污染后续默认值测试
            if orig == 0 {
                UserDefaults.standard.removeObject(forKey: "snaptranslate.selectionHotkeyModifiers")
            } else {
                SettingsManager.shared.selectionHotkeyModifiers = orig
            }
        }
        SettingsManager.shared.selectionHotkeyModifiers = 0
        try assertEqual(SettingsManager.shared.selectionHotkeyModifiers, 0)
    }

    test("closePanelHotkeyKeyCode=0 preserved, NOT ESC 0x35") {
        let orig = SettingsManager.shared.closePanelHotkeyKeyCode
        defer { SettingsManager.shared.closePanelHotkeyKeyCode = orig }
        SettingsManager.shared.closePanelHotkeyKeyCode = 0
        try assertEqual(SettingsManager.shared.closePanelHotkeyKeyCode, 0)
    }

    test("togglePanelHotkeyKeyCode=0 preserved, NOT backtick 0x32") {
        let orig = SettingsManager.shared.togglePanelHotkeyKeyCode
        defer { SettingsManager.shared.togglePanelHotkeyKeyCode = orig }
        SettingsManager.shared.togglePanelHotkeyKeyCode = 0
        try assertEqual(SettingsManager.shared.togglePanelHotkeyKeyCode, 0)
    }

    test("setting hotkey modifiers works") {
        let orig = SettingsManager.shared.hotkeyModifiers
        defer { SettingsManager.shared.hotkeyModifiers = orig }
        let cmdValue = Int(cmdKey | optionKey)
        SettingsManager.shared.hotkeyModifiers = cmdValue
        try assertEqual(SettingsManager.shared.hotkeyModifiers, cmdValue)
    }

    test("selectionHotkeyKeyCode has valid default") {
        let code = SettingsManager.shared.selectionHotkeyKeyCode
        try assertTrue(code >= 0 && code < 128, "KeyCode should be between 0 and 127, got \(code)")
    }

    test("hotkeyDisplay default is ⌃T") {
        try assertEqual(SettingsManager.shared.hotkeyDisplay, "⌃T")
    }

    test("defaultPrompt contains expected sections") {
        let prompt = SettingsManager.shared.defaultPrompt
        try assertTrue(prompt.contains("中文翻译"), "Should contain translation section")
        try assertTrue(prompt.contains("重要词汇"), "Should contain vocabulary section")
        try assertTrue(prompt.contains("常用短语与习语"), "Should contain phrases section")
        try assertTrue(prompt.contains("音标"), "Should contain phonetic field in vocab")
    }

    test("defaultPrompt removed 核查 and table note") {
        let prompt = SettingsManager.shared.defaultPrompt
        try assertFalse(prompt.contains("核查"), "Should NOT contain verification section")
        try assertFalse(prompt.contains("Markdown 表格"), "Should NOT contain table note")
    }

    test("defaultPrompt contains sentence-by-sentence hint") {
        let prompt = SettingsManager.shared.defaultPrompt
        try assertTrue(prompt.contains("逐句"), "Should contain sentence-by-sentence hint")
    }

    test("systemPrompt returns default when not customized") {
        UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt")
        UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt.custom")
        UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt.usesDefault")
        try assertEqual(SettingsManager.shared.systemPrompt, SettingsManager.shared.defaultPrompt)
    }

    test("systemPrompt returns custom when customized via customPrompt") {
        defer {
            UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt.custom")
            UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt.usesDefault")
        }
        SettingsManager.shared.customPrompt = "Custom prompt"
        SettingsManager.shared.usesDefaultPrompt = false
        try assertEqual(SettingsManager.shared.systemPrompt, "Custom prompt")
    }

    // ━━━ 模板双态：默认模板（只读）vs 自定义模板（可编辑）━━━━

    test("usesDefaultPrompt defaults to true when unset") {
        UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt.usesDefault")
        defer { UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt.usesDefault") }
        try assertTrue(SettingsManager.shared.usesDefaultPrompt, "未设置时应默认使用默认模板")
    }

    test("usesDefaultPrompt roundtrip") {
        defer { UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt.usesDefault") }
        SettingsManager.shared.usesDefaultPrompt = false
        try assertFalse(SettingsManager.shared.usesDefaultPrompt)
        SettingsManager.shared.usesDefaultPrompt = true
        try assertTrue(SettingsManager.shared.usesDefaultPrompt)
    }

    test("customPrompt defaults to nil when unset") {
        UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt.custom")
        defer { UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt.custom") }
        try assertNil(SettingsManager.shared.customPrompt as Any?)
    }

    test("customPrompt roundtrip") {
        defer { UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt.custom") }
        SettingsManager.shared.customPrompt = "my custom template"
        try assertEqual(SettingsManager.shared.customPrompt, "my custom template")
    }

    test("customPrompt empty string clears to nil") {
        defer { UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt.custom") }
        SettingsManager.shared.customPrompt = "x"
        SettingsManager.shared.customPrompt = ""
        try assertNil(SettingsManager.shared.customPrompt as Any?)
    }

    test("systemPrompt returns default when usesDefaultPrompt true even if customPrompt set") {
        defer {
            UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt.custom")
            UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt.usesDefault")
        }
        SettingsManager.shared.customPrompt = "custom"
        SettingsManager.shared.usesDefaultPrompt = true
        try assertEqual(SettingsManager.shared.systemPrompt, SettingsManager.shared.defaultPrompt)
    }

    test("systemPrompt returns custom when usesDefaultPrompt false and customPrompt set") {
        defer {
            UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt.custom")
            UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt.usesDefault")
        }
        SettingsManager.shared.customPrompt = "custom template"
        SettingsManager.shared.usesDefaultPrompt = false
        try assertEqual(SettingsManager.shared.systemPrompt, "custom template")
    }

    test("systemPrompt falls back to default when usesDefaultPrompt false but customPrompt empty") {
        defer {
            UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt.custom")
            UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt.usesDefault")
        }
        SettingsManager.shared.customPrompt = nil
        SettingsManager.shared.usesDefaultPrompt = false
        try assertEqual(SettingsManager.shared.systemPrompt, SettingsManager.shared.defaultPrompt)
    }

    // ━━━ 旧数据迁移：snaptranslate.prompt → customPrompt + usesDefault=false ━━━

    test("migrateLegacyPrompt migrates old prompt and deactivates default") {
        let ud = UserDefaults.standard
        defer {
            ud.removeObject(forKey: "snaptranslate.prompt")
            ud.removeObject(forKey: "snaptranslate.prompt.custom")
            ud.removeObject(forKey: "snaptranslate.prompt.usesDefault")
        }
        ud.set("old-custom", forKey: "snaptranslate.prompt")
        SettingsManager.migrateLegacyPrompt()
        try assertEqual(SettingsManager.shared.customPrompt, "old-custom")
        try assertFalse(SettingsManager.shared.usesDefaultPrompt, "迁移后应激活自定义模板")
        try assertNil(ud.string(forKey: "snaptranslate.prompt") as Any?, "迁移后应删除旧 key")
    }

    test("migrateLegacyPrompt no-op when old prompt empty") {
        let ud = UserDefaults.standard
        defer {
            ud.removeObject(forKey: "snaptranslate.prompt")
            ud.removeObject(forKey: "snaptranslate.prompt.custom")
            ud.removeObject(forKey: "snaptranslate.prompt.usesDefault")
        }
        ud.removeObject(forKey: "snaptranslate.prompt")
        SettingsManager.migrateLegacyPrompt()
        try assertNil(SettingsManager.shared.customPrompt as Any?, "无旧数据时不应产生自定义模板")
        try assertTrue(SettingsManager.shared.usesDefaultPrompt, "无旧数据时仍应默认使用默认模板")
    }

    test("setApiKey stores to Keychain and retrieves via activeApiKey") {
        defer { SettingsManager.shared.setApiKey(nil, for: .deepseek) }
        SettingsManager.shared.setApiKey("test-key-123", for: .deepseek)
        try assertEqual(SettingsManager.shared.apiKey(for: .deepseek), "test-key-123")
    }

    test("setApiKey does NOT write to UserDefaults") {
        let udKey = "snaptranslate.apikey.deepseek"
        defer { SettingsManager.shared.setApiKey(nil, for: .deepseek) }
        SettingsManager.shared.setApiKey(nil, for: .deepseek)
        UserDefaults.standard.removeObject(forKey: udKey)
        SettingsManager.shared.setApiKey("sk-secure-only", for: .deepseek)
        try assertNil(UserDefaults.standard.string(forKey: udKey) as Any?)
    }

    test("activeApiKey reflects current provider's key") {
        defer {
            SettingsManager.shared.setApiKey(nil, for: .qwen)
            SettingsManager.shared.apiProvider = .deepseek
        }
        SettingsManager.shared.apiProvider = .qwen
        SettingsManager.shared.setApiKey("sk-qwen-test", for: .qwen)
        try assertEqual(SettingsManager.shared.activeApiKey, "sk-qwen-test")
    }

    test("apiKey returns nil when not set") {
        SettingsManager.shared.setApiKey(nil, for: .qwen)
        try assertNil(SettingsManager.shared.apiKey(for: .qwen) as Any?)
    }

    // WI-B2: 验证 activeApiKey 优先读取当前 provider 的 key（Keychain 优先于 UserDefaults 陈旧明文）
    test("activeApiKey reads from Keychain, not stale UserDefaults") {
        let ud = UserDefaults.standard
        let udKey = "snaptranslate.apikey.deepseek"
        SettingsManager.shared.setApiKey("sk-test-active", for: .deepseek)
        // 注入陈旧明文（模拟旧版遗留），若实现误读 UserDefaults 优先，此测试会失败
        ud.set("sk-stale-plaintext", forKey: udKey)
        defer {
            ud.removeObject(forKey: udKey)
            SettingsManager.shared.setApiKey(nil, for: .deepseek)
        }
        try assertEqual(SettingsManager.shared.activeApiKey, "sk-test-active")
    }

    test("activeApiKey returns nil when Keychain and UserDefaults both empty") {
        SettingsManager.shared.setApiKey(nil, for: .deepseek)
        try assertNil(SettingsManager.shared.activeApiKey as Any?)
    }

    // WI-C3: API Key 存储往返回归（保存后重开应能读回）
    test("setApiKey persists and activeApiKey reads back after provider roundtrip") {
        defer { SettingsManager.shared.setApiKey(nil, for: .deepseek) }
        SettingsManager.shared.apiProvider = .deepseek
        SettingsManager.shared.setApiKey("sk-persist-test", for: .deepseek)
        try assertEqual(SettingsManager.shared.activeApiKey, "sk-persist-test")
        try assertEqual(SettingsManager.shared.apiKey(for: .deepseek), "sk-persist-test")
        SettingsManager.shared.setApiKey(nil, for: .deepseek)
        try assertNil(SettingsManager.shared.activeApiKey as Any?)
    }

    // ━━━ 审计修复 1：迁移写失败丢 key ━━━

    test("migrateKey removes UserDefaults when save succeeds") {
        var removed = false
        SettingsManager.migrateKey(value: "k", udKey: "x", save: { _, _ in true }, remove: { removed = true })
        try assertTrue(removed, "save 成功时应移除 UserDefaults 明文")
    }

    test("migrateKey does NOT remove UserDefaults when save fails") {
        var removed = false
        SettingsManager.migrateKey(value: "k", udKey: "x", save: { _, _ in false }, remove: { removed = true })
        try assertFalse(removed, "save 失败时不应移除 UserDefaults，否则丢 key")
    }

    // ━━━ 审计修复：migrateKey 返回 save 结果，供迁移 flag 判断是否全部成功 ━━━

    test("migrateKey returns true when save succeeds") {
        let ok = SettingsManager.migrateKey(value: "k", udKey: "x", save: { _, _ in true }, remove: {})
        try assertTrue(ok, "save 成功时应返回 true")
    }

    test("migrateKey returns false when save fails") {
        let ok = SettingsManager.migrateKey(value: "k", udKey: "x", save: { _, _ in false }, remove: {})
        try assertFalse(ok, "save 失败时应返回 false")
    }

    // ━━━ 审计修复：测试连接应使用用户在输入框键入的 endpoint/model，而非 provider 默认 ━━━

    test("resolveConnectionTarget prefers typed model") {
        let (endpoint, model) = SettingsWindowController.resolveConnectionTarget(
            modelInput: "qwen-max",
            provider: .qwen
        )
        try assertEqual(endpoint, AIProvider.qwen.endpoint)
        try assertEqual(model, "qwen-max")
    }

    test("resolveConnectionTarget falls back to provider when model empty") {
        let (endpoint, model) = SettingsWindowController.resolveConnectionTarget(
            modelInput: "  ",
            provider: .deepseek
        )
        try assertEqual(endpoint, AIProvider.deepseek.endpoint)
        try assertEqual(model, AIProvider.deepseek.defaultModel)
    }

    // ━━━ 审计修复 2：setApiKey 应清除明文回退 ━━━

    test("setApiKey clears plaintext UserDefaults fallback after save") {
        let udKey = "snaptranslate.apikey.deepseek"
        defer { SettingsManager.shared.setApiKey(nil, for: .deepseek) }
        SettingsManager.shared.setApiKey(nil, for: .deepseek)
        UserDefaults.standard.set("legacy-plaintext", forKey: udKey)
        SettingsManager.shared.setApiKey("sk-new", for: .deepseek)
        try assertNil(UserDefaults.standard.string(forKey: udKey) as Any?, "保存新 key 后应清除明文回退")
    }

    // ━━━ 审计修复 3：keychain 覆盖写（更新路径）━━━━

    test("setApiKey overwrites existing key via update path") {
        defer { SettingsManager.shared.setApiKey(nil, for: .deepseek) }
        SettingsManager.shared.setApiKey("sk-first", for: .deepseek)
        SettingsManager.shared.setApiKey("sk-second", for: .deepseek)
        try assertEqual(SettingsManager.shared.apiKey(for: .deepseek), "sk-second")
    }

    // ━━━ 审计修复 4：连接状态分类 ━━━

    test("ConnectionResult.classify treats 2xx as success") {
        if case .success = ConnectionResult.classify(200) {} else { throw TestFailure("200 应判 success") }
        if case .success = ConnectionResult.classify(299) {} else { throw TestFailure("299 应判 success") }
    }

    test("ConnectionResult.classify treats 401/403 as authFailure") {
        if case .authFailure = ConnectionResult.classify(401) {} else { throw TestFailure("401 应判 authFailure") }
        if case .authFailure = ConnectionResult.classify(403) {} else { throw TestFailure("403 应判 authFailure") }
    }

    test("ConnectionResult.classify treats other codes as serverError") {
        if case .serverError = ConnectionResult.classify(500) {} else { throw TestFailure("500 应判 serverError") }
        if case .serverError = ConnectionResult.classify(404) {} else { throw TestFailure("404 应判 serverError") }
    }

    // ━━━ 审计修复 5：keyCode 哨兵改 Optional（nil=未录制，keyCode 0 = A 键是合法值）━━━━

    test("HotkeyRecorder.recordedKeyCode is nil when not recorded (not sentinel 0)") {
        let r = HotkeyRecorder(allowedSoloKeyCodes: [0x35], soloKeyHint: "Esc", defaultDisplay: { "Esc" })
        try assertNil(r.recordedKeyCode)
        r.reset()
        try assertNil(r.recordedKeyCode)
    }

    // ━━━ 审计修复：reset() 应完整复位录制状态 ━━━

    test("HotkeyRecorder.reset clears isRecording") {
        let r = HotkeyRecorder(allowedSoloKeyCodes: [0x35], soloKeyHint: "Esc", defaultDisplay: { "Esc" })
        r.isRecording = true
        r.reset()
        try assertFalse(r.isRecording, "reset 后 isRecording 应为 false")
    }

    // ━━━ 模型选择：modelOverride 统一存储 ━━━

    test("modelOverride roundtrip via setModelOverride") {
        defer { SettingsManager.shared.setModelOverride(nil, for: .deepseek) }
        SettingsManager.shared.setModelOverride("deepseek-v4-pro", for: .deepseek)
        try assertEqual(SettingsManager.shared.modelOverride(for: .deepseek), "deepseek-v4-pro")
    }

    test("setModelOverride empty string clears override") {
        SettingsManager.shared.setModelOverride("x", for: .deepseek)
        SettingsManager.shared.setModelOverride("", for: .deepseek)
        try assertNil(SettingsManager.shared.modelOverride(for: .deepseek) as Any?)
    }

    test("setModelOverride nil clears override") {
        SettingsManager.shared.setModelOverride("x", for: .deepseek)
        SettingsManager.shared.setModelOverride(nil, for: .deepseek)
        try assertNil(SettingsManager.shared.modelOverride(for: .deepseek) as Any?)
    }

    test("modelOverride does not leak across providers") {
        defer {
            SettingsManager.shared.setModelOverride(nil, for: .deepseek)
            SettingsManager.shared.setModelOverride(nil, for: .qwen)
        }
        SettingsManager.shared.setModelOverride("a", for: .deepseek)
        SettingsManager.shared.setModelOverride("b", for: .qwen)
        try assertEqual(SettingsManager.shared.modelOverride(for: .deepseek), "a")
        try assertEqual(SettingsManager.shared.modelOverride(for: .qwen), "b")
    }

    test("defaultModel reflects override when set") {
        defer { SettingsManager.shared.setModelOverride(nil, for: .deepseek) }
        SettingsManager.shared.setModelOverride("deepseek-v4-pro", for: .deepseek)
        try assertEqual(AIProvider.deepseek.defaultModel, "deepseek-v4-pro")
    }

    test("defaultModel falls back to hardcoded when override empty") {
        SettingsManager.shared.setModelOverride("", for: .deepseek)
        try assertEqual(AIProvider.deepseek.defaultModel, "deepseek-v4-flash")
    }

    // ━━━ 匿名使用统计：installID + 开关 ━━━

    test("installID is a valid UUID string") {
        let id = SettingsManager.shared.installID
        try assertNotNil(UUID(uuidString: id) as UUID?)
    }

    test("installID is stable across reads") {
        let a = SettingsManager.shared.installID
        let b = SettingsManager.shared.installID
        try assertEqual(a, b)
    }

    test("installID generates once and persists") {
        UserDefaults.standard.removeObject(forKey: "snaptranslate.installID")
        let first = SettingsManager.shared.installID
        let stored = UserDefaults.standard.string(forKey: "snaptranslate.installID")
        try assertEqual(first, stored)
    }

    test("telemetryEnabled defaults to true when unset") {
        UserDefaults.standard.removeObject(forKey: "snaptranslate.telemetryEnabled")
        try assertTrue(SettingsManager.shared.telemetryEnabled)
    }

    test("telemetryEnabled persists false") {
        SettingsManager.shared.telemetryEnabled = false
        try assertFalse(SettingsManager.shared.telemetryEnabled)
        UserDefaults.standard.removeObject(forKey: "snaptranslate.telemetryEnabled")
    }

    // ━━━ 默认优先弹窗（defaultSplitMode，默认拆分）━━━━

    test("defaultSplitMode defaults to true (split) when unset") {
        UserDefaults.standard.removeObject(forKey: "snaptranslate.defaultSplitMode")
        try assertTrue(SettingsManager.shared.defaultSplitMode, "未设置时默认应为拆分")
    }

    test("defaultSplitMode persists false (whole)") {
        SettingsManager.shared.defaultSplitMode = false
        try assertFalse(SettingsManager.shared.defaultSplitMode)
        UserDefaults.standard.removeObject(forKey: "snaptranslate.defaultSplitMode")
    }

    test("defaultSplitMode persists true (split)") {
        SettingsManager.shared.defaultSplitMode = true
        try assertTrue(SettingsManager.shared.defaultSplitMode)
        UserDefaults.standard.removeObject(forKey: "snaptranslate.defaultSplitMode")
    }
}
