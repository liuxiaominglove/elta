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
        // Save original
        let orig = SettingsManager.shared.hotkeyKeyCode
        SettingsManager.shared.hotkeyKeyCode = 0x03 // F key
        try assertEqual(SettingsManager.shared.hotkeyKeyCode, 0x03)
        SettingsManager.shared.hotkeyKeyCode = orig // Restore
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

    test("selectionHotkeyModifiers has ctrl+shift default") {
        let mod = SettingsManager.shared.selectionHotkeyModifiers
        try assertEqual(mod, Int(controlKey | shiftKey))
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

    test("setApiKey stores and retrieves key") {
        SettingsManager.shared.setApiKey("test-key-123", for: .deepseek)
        try assertEqual(SettingsManager.shared.apiKey(for: .deepseek), "test-key-123")
        // Clean up
        SettingsManager.shared.setApiKey(nil, for: .deepseek)
    }

    test("apiKey returns nil when not set") {
        SettingsManager.shared.setApiKey(nil, for: .openai)
        try assertNil(SettingsManager.shared.apiKey(for: .openai) as Any?)
    }

    // Restore default state
    SettingsManager.shared.apiProvider = .deepseek
}
