import Cocoa
import Carbon
import Foundation

func runSettingsManagerTests() {
    print("\n--- SettingsManager Tests ---")

    test("SettingsManager shared instance is non-nil") {
        let _ = try assertNotNil(SettingsManager.shared as Any?)
    }

    test("default provider is deepseek") {
        SettingsManager.shared.apiProvider = .deepseek
        try assertEqual(SettingsManager.shared.apiProvider, .deepseek)
    }

    test("set provider to openai works") {
        SettingsManager.shared.apiProvider = .openai
        try assertEqual(SettingsManager.shared.apiProvider, .openai)
    }

    test("set provider to google_ai works") {
        SettingsManager.shared.apiProvider = .googleAI
        try assertEqual(SettingsManager.shared.apiProvider, .googleAI)
    }

    test("invalid provider rawValue falls back to deepseek") {
        // Setting the raw value directly to an invalid string
        UserDefaults.standard.set("nonexistent", forKey: "snaptranslate.apiProvider")
        try assertEqual(SettingsManager.shared.apiProvider, .deepseek)
    }

    test("hotkeyKeyCode has valid default between 0-127") {
        let code = SettingsManager.shared.hotkeyKeyCode
        try assertTrue(code >= 0 && code < 128, "KeyCode should be between 0 and 127, got \(code)")
    }

    test("hotkeyModifiers has valid default (non-zero)") {
        let mod = SettingsManager.shared.hotkeyModifiers
        try assertTrue(mod >= 0, "Modifiers should be >= 0")
    }

    test("setting hotkey keyCode works") {
        let orig = SettingsManager.shared.hotkeyKeyCode
        SettingsManager.shared.hotkeyKeyCode = 0x03 // F key
        try assertEqual(SettingsManager.shared.hotkeyKeyCode, 0x03)
        SettingsManager.shared.hotkeyKeyCode = orig // Restore
    }

    test("hotkeyKeyCode=0 (A key) is preserved, NOT default T key") {
        let orig = SettingsManager.shared.hotkeyKeyCode
        SettingsManager.shared.hotkeyKeyCode = 0
        try assertEqual(SettingsManager.shared.hotkeyKeyCode, 0)
        SettingsManager.shared.hotkeyKeyCode = orig
    }

    test("hotkeyModifiers=0 preserved, NOT replaced by controlKey") {
        let orig = SettingsManager.shared.hotkeyModifiers
        SettingsManager.shared.hotkeyModifiers = 0
        try assertEqual(SettingsManager.shared.hotkeyModifiers, 0)
        SettingsManager.shared.hotkeyModifiers = orig
    }

    test("selectionHotkeyKeyCode=0 preserved, NOT default") {
        let orig = SettingsManager.shared.selectionHotkeyKeyCode
        SettingsManager.shared.selectionHotkeyKeyCode = 0
        try assertEqual(SettingsManager.shared.selectionHotkeyKeyCode, 0)
        SettingsManager.shared.selectionHotkeyKeyCode = orig
    }

    test("selectionHotkeyModifiers has ctrl+shift default") {
        UserDefaults.standard.removeObject(forKey: "snaptranslate.selectionHotkeyModifiers")
        let mod = SettingsManager.shared.selectionHotkeyModifiers
        try assertEqual(mod, Int(controlKey | shiftKey))
    }

    test("selectionHotkeyModifiers=0 preserved, NOT ctrl+shift") {
        let orig = SettingsManager.shared.selectionHotkeyModifiers
        SettingsManager.shared.selectionHotkeyModifiers = 0
        try assertEqual(SettingsManager.shared.selectionHotkeyModifiers, 0)
        // 恢复原始值；若 orig 也是 0 则清空 key 避免污染后续默认值测试
        if orig == 0 {
            UserDefaults.standard.removeObject(forKey: "snaptranslate.selectionHotkeyModifiers")
        } else {
            SettingsManager.shared.selectionHotkeyModifiers = orig
        }
    }

    test("closePanelHotkeyKeyCode=0 preserved, NOT ESC 0x35") {
        let orig = SettingsManager.shared.closePanelHotkeyKeyCode
        SettingsManager.shared.closePanelHotkeyKeyCode = 0
        try assertEqual(SettingsManager.shared.closePanelHotkeyKeyCode, 0)
        SettingsManager.shared.closePanelHotkeyKeyCode = orig
    }

    test("togglePanelHotkeyKeyCode=0 preserved, NOT backtick 0x32") {
        let orig = SettingsManager.shared.togglePanelHotkeyKeyCode
        SettingsManager.shared.togglePanelHotkeyKeyCode = 0
        try assertEqual(SettingsManager.shared.togglePanelHotkeyKeyCode, 0)
        SettingsManager.shared.togglePanelHotkeyKeyCode = orig
    }

    test("setting hotkey modifiers works") {
        let orig = SettingsManager.shared.hotkeyModifiers
        let cmdValue = Int(cmdKey | optionKey)
        SettingsManager.shared.hotkeyModifiers = cmdValue
        try assertEqual(SettingsManager.shared.hotkeyModifiers, cmdValue)
        SettingsManager.shared.hotkeyModifiers = orig // Restore
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
        try assertTrue(prompt.contains("核查"), "Should contain verification section")
    }

    test("systemPrompt returns default when not customized") {
        // Ensure no custom prompt is set
        UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt")
        try assertEqual(SettingsManager.shared.systemPrompt, SettingsManager.shared.defaultPrompt)
    }

    test("systemPrompt returns custom when set") {
        let custom = "Custom prompt"
        SettingsManager.shared.systemPrompt = custom
        try assertEqual(SettingsManager.shared.systemPrompt, custom)
        // Clean up
        UserDefaults.standard.removeObject(forKey: "snaptranslate.prompt")
    }

    test("setApiKey stores to Keychain and retrieves via activeApiKey") {
        SettingsManager.shared.setApiKey("test-key-123", for: .deepseek)
        try assertEqual(SettingsManager.shared.apiKey(for: .deepseek), "test-key-123")
        SettingsManager.shared.setApiKey(nil, for: .deepseek)
    }

    test("setApiKey does NOT write to UserDefaults") {
        let udKey = "snaptranslate.apikey.deepseek"
        SettingsManager.shared.setApiKey(nil, for: .deepseek)
        UserDefaults.standard.removeObject(forKey: udKey)
        SettingsManager.shared.setApiKey("sk-secure-only", for: .deepseek)
        try assertNil(UserDefaults.standard.string(forKey: udKey) as Any?)
        SettingsManager.shared.setApiKey(nil, for: .deepseek)
    }

    test("activeApiKey reflects current provider's key") {
        SettingsManager.shared.apiProvider = .openai
        SettingsManager.shared.setApiKey("sk-openai-test", for: .openai)
        try assertEqual(SettingsManager.shared.activeApiKey, "sk-openai-test")
        SettingsManager.shared.setApiKey(nil, for: .openai)
        SettingsManager.shared.apiProvider = .deepseek
    }

    test("apiKey returns nil when not set") {
        SettingsManager.shared.setApiKey(nil, for: .openai)
        try assertNil(SettingsManager.shared.apiKey(for: .openai) as Any?)
    }

    // WI-B2: 验证 activeApiKey 优先读取当前 provider 的 key
    test("activeApiKey reads from Keychain, not stale UserDefaults") {
        SettingsManager.shared.setApiKey("sk-test-active", for: .deepseek)
        try assertEqual(SettingsManager.shared.activeApiKey, "sk-test-active")
        SettingsManager.shared.setApiKey(nil, for: .deepseek)
    }

    test("activeApiKey returns nil when Keychain and UserDefaults both empty") {
        SettingsManager.shared.setApiKey(nil, for: .deepseek)
        try assertNil(SettingsManager.shared.activeApiKey as Any?)
    }

    // WI-C3: API Key 存储往返回归（保存后重开应能读回）
    test("setApiKey persists and activeApiKey reads back after provider roundtrip") {
        SettingsManager.shared.apiProvider = .deepseek
        SettingsManager.shared.setApiKey("sk-persist-test", for: .deepseek)
        try assertEqual(SettingsManager.shared.activeApiKey, "sk-persist-test")
        try assertEqual(SettingsManager.shared.apiKey(for: .deepseek), "sk-persist-test")
        SettingsManager.shared.setApiKey(nil, for: .deepseek)
        try assertNil(SettingsManager.shared.activeApiKey as Any?)
    }
}
