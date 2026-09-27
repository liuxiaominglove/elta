using System;
using Elta.Core;
using Xunit;

namespace Elta.Core.Tests
{
    public class SettingsManagerTests
    {
        private const int ControlKey = 0x1000;
        private const int ShiftKey = 0x0200;

        private static (SettingsManager mgr, InMemorySettingsStore store, InMemorySecretStore secrets) New()
        {
            var store = new InMemorySettingsStore();
            var secrets = new InMemorySecretStore();
            return (new SettingsManager(store, secrets, SettingsDefaults.MacParity), store, secrets);
        }

        [Fact]
        public void SharedInstance_IsNonNull()
        {
            var (mgr, _, _) = New();
            Assert.NotNull(mgr);
        }

        [Fact]
        public void DefaultProvider_IsDeepseek()
        {
            var (mgr, _, _) = New();
            Assert.Equal(AIProvider.Deepseek, mgr.ApiProvider);
        }

        [Fact]
        public void SetProvider_ToQwen_Works()
        {
            var (mgr, _, _) = New();
            mgr.ApiProvider = AIProvider.Qwen;
            Assert.Equal(AIProvider.Qwen, mgr.ApiProvider);
        }

        [Fact]
        public void InvalidProviderRawValue_FallsBackToDeepseek()
        {
            var (mgr, store, _) = New();
            store.SetString("snaptranslate.apiProvider", "nonexistent");
            Assert.Equal(AIProvider.Deepseek, mgr.ApiProvider);
        }

        [Fact]
        public void HotkeyKeyCode_HasValidDefault()
        {
            var (mgr, _, _) = New();
            int code = mgr.HotkeyKeyCode;
            Assert.True(code >= 0 && code < 128, $"KeyCode should be between 0 and 127, got {code}");
        }

        [Fact]
        public void HotkeyModifiers_HasNonZeroDefault()
        {
            var (mgr, _, _) = New();
            Assert.NotEqual(0, mgr.HotkeyModifiers);
        }

        [Fact]
        public void SettingHotkeyKeyCode_Works()
        {
            var (mgr, _, _) = New();
            mgr.HotkeyKeyCode = 0x03;
            Assert.Equal(0x03, mgr.HotkeyKeyCode);
        }

        [Fact]
        public void HotkeyKeyCodeZero_IsPreserved()
        {
            var (mgr, _, _) = New();
            mgr.HotkeyKeyCode = 0;
            Assert.Equal(0, mgr.HotkeyKeyCode);
        }

        [Fact]
        public void HotkeyModifiersZero_IsPreserved()
        {
            var (mgr, _, _) = New();
            mgr.HotkeyModifiers = 0;
            Assert.Equal(0, mgr.HotkeyModifiers);
        }

        [Fact]
        public void SelectionHotkeyKeyCodeZero_IsPreserved()
        {
            var (mgr, _, _) = New();
            mgr.SelectionHotkeyKeyCode = 0;
            Assert.Equal(0, mgr.SelectionHotkeyKeyCode);
        }

        [Fact]
        public void SelectionHotkeyModifiers_DefaultIsCtrlShift()
        {
            var (mgr, _, _) = New();
            Assert.Equal(ControlKey | ShiftKey, mgr.SelectionHotkeyModifiers);
        }

        [Fact]
        public void SelectionHotkeyModifiersZero_IsPreserved()
        {
            var (mgr, _, _) = New();
            mgr.SelectionHotkeyModifiers = 0;
            Assert.Equal(0, mgr.SelectionHotkeyModifiers);
        }

        [Fact]
        public void ClosePanelHotkeyKeyCodeZero_IsPreserved()
        {
            var (mgr, _, _) = New();
            mgr.ClosePanelHotkeyKeyCode = 0;
            Assert.Equal(0, mgr.ClosePanelHotkeyKeyCode);
        }

        [Fact]
        public void TogglePanelHotkeyKeyCodeZero_IsPreserved()
        {
            var (mgr, _, _) = New();
            mgr.TogglePanelHotkeyKeyCode = 0;
            Assert.Equal(0, mgr.TogglePanelHotkeyKeyCode);
        }

        [Fact]
        public void SettingHotkeyModifiers_Works()
        {
            var (mgr, _, _) = New();
            const int cmdOption = 0x0100 | 0x0800;
            mgr.HotkeyModifiers = cmdOption;
            Assert.Equal(cmdOption, mgr.HotkeyModifiers);
        }

        [Fact]
        public void SelectionHotkeyKeyCode_HasValidDefault()
        {
            var (mgr, _, _) = New();
            int code = mgr.SelectionHotkeyKeyCode;
            Assert.True(code >= 0 && code < 128, $"KeyCode should be between 0 and 127, got {code}");
        }

        [Fact]
        public void HotkeyDisplay_DefaultIsControlT()
        {
            var (mgr, _, _) = New();
            Assert.Equal("⌃T", mgr.HotkeyDisplay);
        }

        // MARK: 默认模板

        [Fact]
        public void DefaultPrompt_ContainsExpectedSections()
        {
            string prompt = SettingsManager.DefaultPrompt;
            Assert.Contains("中文翻译", prompt);
            Assert.Contains("重要词汇", prompt);
            Assert.Contains("常用短语与习语", prompt);
            Assert.Contains("音标", prompt);
        }

        [Fact]
        public void DefaultPrompt_RemovedCheckAndTableNote()
        {
            string prompt = SettingsManager.DefaultPrompt;
            Assert.DoesNotContain("核查", prompt);
            Assert.DoesNotContain("Markdown 表格", prompt);
        }

        [Fact]
        public void DefaultPrompt_ContainsSentenceBySentenceHint()
        {
            Assert.Contains("逐句", SettingsManager.DefaultPrompt);
        }

        [Fact]
        public void SystemPrompt_ReturnsDefaultWhenNotCustomized()
        {
            var (mgr, _, _) = New();
            Assert.Equal(SettingsManager.DefaultPrompt, mgr.SystemPrompt);
        }

        [Fact]
        public void SystemPrompt_ReturnsCustomWhenCustomized()
        {
            var (mgr, _, _) = New();
            mgr.CustomPrompt = "Custom prompt";
            mgr.UsesDefaultPrompt = false;
            Assert.Equal("Custom prompt", mgr.SystemPrompt);
        }

        [Fact]
        public void UsesDefaultPrompt_DefaultsToTrue()
        {
            var (mgr, _, _) = New();
            Assert.True(mgr.UsesDefaultPrompt);
        }

        [Fact]
        public void UsesDefaultPrompt_Roundtrip()
        {
            var (mgr, _, _) = New();
            mgr.UsesDefaultPrompt = false;
            Assert.False(mgr.UsesDefaultPrompt);
            mgr.UsesDefaultPrompt = true;
            Assert.True(mgr.UsesDefaultPrompt);
        }

        [Fact]
        public void CustomPrompt_DefaultsToNull()
        {
            var (mgr, _, _) = New();
            Assert.Null(mgr.CustomPrompt);
        }

        [Fact]
        public void CustomPrompt_Roundtrip()
        {
            var (mgr, _, _) = New();
            mgr.CustomPrompt = "my custom template";
            Assert.Equal("my custom template", mgr.CustomPrompt);
        }

        [Fact]
        public void CustomPrompt_EmptyStringClearsToNull()
        {
            var (mgr, _, _) = New();
            mgr.CustomPrompt = "x";
            mgr.CustomPrompt = "";
            Assert.Null(mgr.CustomPrompt);
        }

        [Fact]
        public void SystemPrompt_ReturnsDefaultWhenUsesDefaultTrueEvenIfCustomSet()
        {
            var (mgr, _, _) = New();
            mgr.CustomPrompt = "custom";
            mgr.UsesDefaultPrompt = true;
            Assert.Equal(SettingsManager.DefaultPrompt, mgr.SystemPrompt);
        }

        [Fact]
        public void SystemPrompt_ReturnsCustomWhenUsesDefaultFalseAndCustomSet()
        {
            var (mgr, _, _) = New();
            mgr.CustomPrompt = "custom template";
            mgr.UsesDefaultPrompt = false;
            Assert.Equal("custom template", mgr.SystemPrompt);
        }

        [Fact]
        public void SystemPrompt_FallsBackToDefaultWhenCustomEmpty()
        {
            var (mgr, _, _) = New();
            mgr.CustomPrompt = null;
            mgr.UsesDefaultPrompt = false;
            Assert.Equal(SettingsManager.DefaultPrompt, mgr.SystemPrompt);
        }

        // MARK: 旧数据迁移

        [Fact]
        public void MigrateLegacyPrompt_MigratesAndDeactivatesDefault()
        {
            var (mgr, store, _) = New();
            store.SetString("snaptranslate.prompt", "old-custom");
            mgr.MigrateLegacyPrompt();
            Assert.Equal("old-custom", mgr.CustomPrompt);
            Assert.False(mgr.UsesDefaultPrompt);
            Assert.Null(store.GetString("snaptranslate.prompt"));
        }

        [Fact]
        public void MigrateLegacyPrompt_NoOpWhenOldPromptEmpty()
        {
            var (mgr, _, _) = New();
            mgr.MigrateLegacyPrompt();
            Assert.Null(mgr.CustomPrompt);
            Assert.True(mgr.UsesDefaultPrompt);
        }

        // MARK: API Key

        [Fact]
        public void SetApiKey_StoresAndRetrieves()
        {
            var (mgr, _, _) = New();
            mgr.SetApiKey("test-key-123", AIProvider.Deepseek);
            Assert.Equal("test-key-123", mgr.ApiKey(AIProvider.Deepseek));
        }

        [Fact]
        public void SetApiKey_DoesNotWritePlaintextToSettings()
        {
            const string udKey = "snaptranslate.apikey.deepseek";
            var (mgr, store, _) = New();
            mgr.SetApiKey(null, AIProvider.Deepseek);
            store.Remove(udKey);
            mgr.SetApiKey("sk-secure-only", AIProvider.Deepseek);
            Assert.Null(store.GetString(udKey));
        }

        [Fact]
        public void ActiveApiKey_ReflectsCurrentProvider()
        {
            var (mgr, _, _) = New();
            mgr.ApiProvider = AIProvider.Qwen;
            mgr.SetApiKey("sk-qwen-test", AIProvider.Qwen);
            Assert.Equal("sk-qwen-test", mgr.ActiveApiKey);
        }

        [Fact]
        public void ApiKey_ReturnsNullWhenNotSet()
        {
            var (mgr, _, _) = New();
            mgr.SetApiKey(null, AIProvider.Qwen);
            Assert.Null(mgr.ApiKey(AIProvider.Qwen));
        }

        [Fact]
        public void ActiveApiKey_ReadsFromSecretNotStalePlaintext()
        {
            const string udKey = "snaptranslate.apikey.deepseek";
            var (mgr, store, _) = New();
            mgr.SetApiKey("sk-test-active", AIProvider.Deepseek);
            store.SetString(udKey, "sk-stale-plaintext");
            Assert.Equal("sk-test-active", mgr.ActiveApiKey);
        }

        [Fact]
        public void ActiveApiKey_ReturnsNullWhenBothEmpty()
        {
            var (mgr, _, _) = New();
            mgr.SetApiKey(null, AIProvider.Deepseek);
            Assert.Null(mgr.ActiveApiKey);
        }

        [Fact]
        public void SetApiKey_PersistsAndReadsBackAfterProviderRoundtrip()
        {
            var (mgr, _, _) = New();
            mgr.ApiProvider = AIProvider.Deepseek;
            mgr.SetApiKey("sk-persist-test", AIProvider.Deepseek);
            Assert.Equal("sk-persist-test", mgr.ActiveApiKey);
            Assert.Equal("sk-persist-test", mgr.ApiKey(AIProvider.Deepseek));
            mgr.SetApiKey(null, AIProvider.Deepseek);
            Assert.Null(mgr.ActiveApiKey);
        }

        [Fact]
        public void SetApiKey_ClearsPlaintextFallbackAfterSave()
        {
            const string udKey = "snaptranslate.apikey.deepseek";
            var (mgr, store, _) = New();
            mgr.SetApiKey(null, AIProvider.Deepseek);
            store.SetString(udKey, "legacy-plaintext");
            mgr.SetApiKey("sk-new", AIProvider.Deepseek);
            Assert.Null(store.GetString(udKey));
        }

        [Fact]
        public void SetApiKey_OverwritesExistingKey()
        {
            var (mgr, _, _) = New();
            mgr.SetApiKey("sk-first", AIProvider.Deepseek);
            mgr.SetApiKey("sk-second", AIProvider.Deepseek);
            Assert.Equal("sk-second", mgr.ApiKey(AIProvider.Deepseek));
        }

        // MARK: 迁移写失败丢 key

        [Fact]
        public void MigrateKey_RemovesWhenSaveSucceeds()
        {
            bool removed = false;
            SettingsManager.MigrateKey("k", "x", (_, _) => true, () => removed = true);
            Assert.True(removed, "save 成功时应移除明文");
        }

        [Fact]
        public void MigrateKey_DoesNotRemoveWhenSaveFails()
        {
            bool removed = false;
            SettingsManager.MigrateKey("k", "x", (_, _) => false, () => removed = true);
            Assert.False(removed, "save 失败时不应移除明文，否则丢 key");
        }

        [Fact]
        public void MigrateKey_ReturnsTrueWhenSaveSucceeds()
        {
            Assert.True(SettingsManager.MigrateKey("k", "x", (_, _) => true, () => { }));
        }

        [Fact]
        public void MigrateKey_ReturnsFalseWhenSaveFails()
        {
            Assert.False(SettingsManager.MigrateKey("k", "x", (_, _) => false, () => { }));
        }

        // MARK: 模型选择

        [Fact]
        public void ModelOverride_Roundtrip()
        {
            var (mgr, _, _) = New();
            mgr.SetModelOverride("deepseek-v4-pro", AIProvider.Deepseek);
            Assert.Equal("deepseek-v4-pro", mgr.ModelOverride(AIProvider.Deepseek));
        }

        [Fact]
        public void SetModelOverride_EmptyStringClears()
        {
            var (mgr, _, _) = New();
            mgr.SetModelOverride("x", AIProvider.Deepseek);
            mgr.SetModelOverride("", AIProvider.Deepseek);
            Assert.Null(mgr.ModelOverride(AIProvider.Deepseek));
        }

        [Fact]
        public void SetModelOverride_NullClears()
        {
            var (mgr, _, _) = New();
            mgr.SetModelOverride("x", AIProvider.Deepseek);
            mgr.SetModelOverride(null, AIProvider.Deepseek);
            Assert.Null(mgr.ModelOverride(AIProvider.Deepseek));
        }

        [Fact]
        public void ModelOverride_DoesNotLeakAcrossProviders()
        {
            var (mgr, _, _) = New();
            mgr.SetModelOverride("a", AIProvider.Deepseek);
            mgr.SetModelOverride("b", AIProvider.Qwen);
            Assert.Equal("a", mgr.ModelOverride(AIProvider.Deepseek));
            Assert.Equal("b", mgr.ModelOverride(AIProvider.Qwen));
        }

        [Fact]
        public void EffectiveModel_ReflectsOverride()
        {
            var (mgr, _, _) = New();
            mgr.SetModelOverride("deepseek-v4-pro", AIProvider.Deepseek);
            Assert.Equal("deepseek-v4-pro", mgr.EffectiveModel(AIProvider.Deepseek));
        }

        [Fact]
        public void EffectiveModel_FallsBackToHardcodedWhenOverrideEmpty()
        {
            var (mgr, _, _) = New();
            mgr.SetModelOverride("", AIProvider.Deepseek);
            Assert.Equal("deepseek-v4-flash", mgr.EffectiveModel(AIProvider.Deepseek));
        }

        // MARK: 匿名使用统计

        [Fact]
        public void InstallId_IsValidUuid()
        {
            var (mgr, _, _) = New();
            Assert.True(Guid.TryParse(mgr.InstallId, out _));
        }

        [Fact]
        public void InstallId_IsStableAcrossReads()
        {
            var (mgr, _, _) = New();
            Assert.Equal(mgr.InstallId, mgr.InstallId);
        }

        [Fact]
        public void InstallId_GeneratesOnceAndPersists()
        {
            var (mgr, store, _) = New();
            string first = mgr.InstallId;
            Assert.Equal(first, store.GetString("snaptranslate.installID"));
        }

        [Fact]
        public void TelemetryEnabled_DefaultsToTrue()
        {
            var (mgr, _, _) = New();
            Assert.True(mgr.TelemetryEnabled);
        }

        [Fact]
        public void TelemetryEnabled_PersistsFalse()
        {
            var (mgr, _, _) = New();
            mgr.TelemetryEnabled = false;
            Assert.False(mgr.TelemetryEnabled);
        }

        // MARK: 默认优先弹窗

        [Fact]
        public void DefaultSplitMode_DefaultsToTrue()
        {
            var (mgr, _, _) = New();
            Assert.True(mgr.DefaultSplitMode);
        }

        [Fact]
        public void DefaultSplitMode_PersistsFalse()
        {
            var (mgr, _, _) = New();
            mgr.DefaultSplitMode = false;
            Assert.False(mgr.DefaultSplitMode);
        }

        [Fact]
        public void DefaultSplitMode_PersistsTrue()
        {
            var (mgr, _, _) = New();
            mgr.DefaultSplitMode = true;
            Assert.True(mgr.DefaultSplitMode);
        }

        // MARK: 弹窗字号

        [Fact]
        public void PopupFontSize_DefaultsTo14()
        {
            var (mgr, _, _) = New();
            Assert.Equal(14, mgr.PopupFontSize);
        }

        [Fact]
        public void PopupFontSize_PersistsInRange()
        {
            var (mgr, _, _) = New();
            mgr.PopupFontSize = 18;
            Assert.Equal(18, mgr.PopupFontSize);
        }

        [Fact]
        public void PopupFontSize_ClampsHighTo22()
        {
            var (mgr, _, _) = New();
            mgr.PopupFontSize = 30;
            Assert.Equal(22, mgr.PopupFontSize);
        }

        [Fact]
        public void PopupFontSize_ClampsLowTo12()
        {
            var (mgr, _, _) = New();
            mgr.PopupFontSize = 1;
            Assert.Equal(12, mgr.PopupFontSize);
        }

        // MARK: 窗口矩形

        [Fact]
        public void WindowFrame_DefaultsToNull()
        {
            var (mgr, _, _) = New();
            Assert.Null(mgr.WindowFrame);
        }

        [Fact]
        public void WindowFrame_Roundtrip()
        {
            var (mgr, _, _) = New();
            mgr.WindowFrame = new WindowFrame(10, 20, 640, 480);
            Assert.Equal(new WindowFrame(10, 20, 640, 480), mgr.WindowFrame);
        }

        [Fact]
        public void WindowFrame_InvalidStoredValueReturnsNull()
        {
            var (mgr, store, _) = New();
            store.SetString("snaptranslate.windowFrame", "not-a-frame");
            Assert.Null(mgr.WindowFrame);
        }
    }
}
