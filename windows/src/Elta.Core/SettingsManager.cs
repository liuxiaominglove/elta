using System;

namespace Elta.Core
{
    /// <summary>
    /// 应用设置管理器，移植自 macOS 版 Sources/SettingsManager.swift。
    /// 平台差异全部下沉到 <see cref="ISettingsStore"/> / <see cref="ISecretStore"/> / <see cref="SettingsDefaults"/>：
    /// Windows 外壳注入注册表（或 JSON）存储、DPAPI（或凭据管理器）密钥库与 Windows 默认值；
    /// 单元测试注入内存双替与 <see cref="SettingsDefaults.MacParity"/>。
    /// 键名沿用 macOS 版的 "snaptranslate.*" 前缀。
    /// </summary>
    public sealed class SettingsManager
    {
        private static class Keys
        {
            public const string ApiProvider = "snaptranslate.apiProvider";
            public const string Prompt = "snaptranslate.prompt";
            public const string CustomPrompt = "snaptranslate.prompt.custom";
            public const string UsesDefaultPrompt = "snaptranslate.prompt.usesDefault";
            public const string WindowFrame = "snaptranslate.windowFrame";
            public const string HotkeyKeyCode = "snaptranslate.hotkeyKeyCode";
            public const string HotkeyModifiers = "snaptranslate.hotkeyModifiers";
            public const string HotkeyDisplay = "snaptranslate.hotkeyDisplay";
            public const string SelectionHotkeyKeyCode = "snaptranslate.selectionHotkeyKeyCode";
            public const string SelectionHotkeyModifiers = "snaptranslate.selectionHotkeyModifiers";
            public const string SelectionHotkeyDisplay = "snaptranslate.selectionHotkeyDisplay";
            public const string ClosePanelHotkeyKeyCode = "snaptranslate.closePanelHotkeyKeyCode";
            public const string ClosePanelHotkeyModifiers = "snaptranslate.closePanelHotkeyModifiers";
            public const string ClosePanelHotkeyDisplay = "snaptranslate.closePanelHotkeyDisplay";
            public const string TogglePanelHotkeyKeyCode = "snaptranslate.togglePanelHotkeyKeyCode";
            public const string TogglePanelHotkeyModifiers = "snaptranslate.togglePanelHotkeyModifiers";
            public const string TogglePanelHotkeyDisplay = "snaptranslate.togglePanelHotkeyDisplay";
            public const string SplitHotkeyKeyCode = "snaptranslate.splitHotkeyKeyCode";
            public const string SplitHotkeyModifiers = "snaptranslate.splitHotkeyModifiers";
            public const string SplitHotkeyDisplay = "snaptranslate.splitHotkeyDisplay";
            public const string DefaultSplitMode = "snaptranslate.defaultSplitMode";
            public const string PopupFontSize = "snaptranslate.popupFontSize";
            public const string SkipUpdateVersion = "snaptranslate.skipUpdateVersion";
            public const string InstallId = "snaptranslate.installID";
            public const string TelemetryEnabled = "snaptranslate.telemetryEnabled";
            public const string KeychainMigrated = "snaptranslate.keychain_migrated_v2";
        }

        private readonly ISettingsStore _store;
        private readonly ISecretStore _secrets;
        private readonly SettingsDefaults _defaults;
        private readonly Action<string>? _log;
        private readonly object _lock = new object();

        public SettingsManager(
            ISettingsStore store,
            ISecretStore secrets,
            SettingsDefaults? defaults = null,
            Action<string>? log = null)
        {
            _store = store ?? throw new ArgumentNullException(nameof(store));
            _secrets = secrets ?? throw new ArgumentNullException(nameof(secrets));
            _defaults = defaults ?? SettingsDefaults.MacParity;
            _log = log;

            MigrateApiKeysToSecretStore();
            MigrateLegacyPrompt();
        }

        public SettingsDefaults Defaults => _defaults;

        private static string ApiKeyAccount(AIProvider provider)
            => $"snaptranslate.apikey.{AIProviders.RawValue(provider)}";

        private static string ModelOverrideKey(AIProvider provider)
            => $"snaptranslate.model.{AIProviders.RawValue(provider)}";

        // MARK: AI 提供商

        public AIProvider ApiProvider
        {
            get { lock (_lock) { return ApiProviderUnlocked(); } }
            set { lock (_lock) { _store.SetString(Keys.ApiProvider, AIProviders.RawValue(value)); } }
        }

        private AIProvider ApiProviderUnlocked()
        {
            string? raw = _store.GetString(Keys.ApiProvider);
            return AIProviders.ParseRaw(raw) ?? _defaults.ApiProvider;
        }

        // MARK: API Keys（密钥库优先，明文回退）

        public string? ApiKey(AIProvider provider)
        {
            lock (_lock) { return ApiKeyUnlocked(provider); }
        }

        private string? ApiKeyUnlocked(AIProvider provider)
        {
            string account = ApiKeyAccount(provider);
            string? fromSecret = _secrets.Read(account);
            if (fromSecret != null)
            {
                _log?.Invoke($"Keychain 读取: provider={AIProviders.RawValue(provider)}, hit=true");
                return fromSecret;
            }
            _log?.Invoke($"Keychain 读取: provider={AIProviders.RawValue(provider)}, hit=false, fallback to settings");
            return _store.GetString(account);
        }

        /// <summary>保存密钥；空/ null 表示删除。返回是否成功；写失败须保留旧值。</summary>
        public bool SetApiKey(string? key, AIProvider provider)
        {
            lock (_lock)
            {
                string account = ApiKeyAccount(provider);
                if (!string.IsNullOrEmpty(key))
                {
                    _log?.Invoke($"Keychain 写入: provider={AIProviders.RawValue(provider)}, len={key!.Length}");
                    bool ok = _secrets.Save(account, key!);
                    if (ok)
                    {
                        _store.Remove(account);
                        return true;
                    }
                    _log?.Invoke($"Keychain 写入失败: provider={AIProviders.RawValue(provider)} — 新 key 未被保存，旧 key 仍生效");
                    return false;
                }

                _log?.Invoke($"Keychain 删除: provider={AIProviders.RawValue(provider)}");
                bool deleted = _secrets.Delete(account);
                _store.Remove(account);
                if (!deleted)
                {
                    _log?.Invoke($"Keychain 删除失败: provider={AIProviders.RawValue(provider)} — 旧 key 可能仍残留");
                }
                return deleted;
            }
        }

        /// <summary>当前激活的 API Key（一次锁定读取 provider + key）。</summary>
        public string? ActiveApiKey
        {
            get { lock (_lock) { return ApiKeyUnlocked(ApiProviderUnlocked()); } }
        }

        /// <summary>迁移单个 provider：save 成功才移除设置明文，避免写失败丢 key。</summary>
        public static bool MigrateKey(string value, string udKey, Func<string, string, bool> save, Action remove)
        {
            bool ok = save(value, udKey);
            if (ok) remove();
            return ok;
        }

        /// <summary>一次性迁移：把误存到设置明文的 API Key 迁移到密钥库，全部成功才标记。</summary>
        public void MigrateApiKeysToSecretStore()
        {
            if (_store.GetBool(Keys.KeychainMigrated) == true) return;

            bool allMigrated = true;
            foreach (AIProvider provider in new[] { AIProvider.Deepseek, AIProvider.Qwen })
            {
                string udKey = ApiKeyAccount(provider);
                string? value = _store.GetString(udKey);
                if (string.IsNullOrEmpty(value)) continue;

                bool ok = MigrateKey(value!, udKey,
                    save: (v, acct) => _secrets.Save(acct, v),
                    remove: () =>
                    {
                        _store.Remove(udKey);
                        _log?.Invoke($"迁移：{AIProviders.DisplayName(provider)} Key 从设置明文 → 密钥库");
                    });
                if (!ok)
                {
                    _log?.Invoke($"迁移失败：{AIProviders.DisplayName(provider)} Key 保留在设置明文，下次启动重试");
                    allMigrated = false;
                }
            }

            if (allMigrated) _store.SetBool(Keys.KeychainMigrated, true);
        }

        // MARK: 模型选择（所有 provider 统一）

        public string? ModelOverride(AIProvider provider)
        {
            lock (_lock) { return _store.GetString(ModelOverrideKey(provider)); }
        }

        public void SetModelOverride(string? value, AIProvider provider)
        {
            lock (_lock)
            {
                string key = ModelOverrideKey(provider);
                if (!string.IsNullOrEmpty(value)) _store.SetString(key, value);
                else _store.Remove(key);
            }
        }

        /// <summary>生效模型：覆盖值非空则用覆盖值，否则回落内置默认。</summary>
        public string EffectiveModel(AIProvider provider)
            => AIProviders.DefaultModel(provider, ModelOverride(provider));

        // MARK: 翻译模板（双态：默认模板只读 / 自定义模板可编辑）

        /// <summary>用户自定义模板（null / 空白表示未自定义）。</summary>
        public string? CustomPrompt
        {
            get { lock (_lock) { return CustomPromptUnlocked(); } }
            set
            {
                lock (_lock)
                {
                    if (value != null && value.Trim().Length > 0) _store.SetString(Keys.CustomPrompt, value);
                    else _store.Remove(Keys.CustomPrompt);
                }
            }
        }

        /// <summary>当前生效模板是否为内置默认（true=默认，false=自定义）。</summary>
        public bool UsesDefaultPrompt
        {
            get { lock (_lock) { return UsesDefaultPromptUnlocked(); } }
            set { lock (_lock) { _store.SetBool(Keys.UsesDefaultPrompt, value); } }
        }

        /// <summary>实际生效的翻译模板（只读派生）。</summary>
        public string SystemPrompt
        {
            get
            {
                lock (_lock)
                {
                    if (!UsesDefaultPromptUnlocked())
                    {
                        string? c = CustomPromptUnlocked();
                        if (c != null) return c;
                    }
                    return DefaultPrompt;
                }
            }
        }

        private string? CustomPromptUnlocked()
        {
            string? v = _store.GetString(Keys.CustomPrompt);
            return (v == null || v.Trim().Length == 0) ? null : v;
        }

        private bool UsesDefaultPromptUnlocked()
            => _store.GetBool(Keys.UsesDefaultPrompt) ?? _defaults.UsesDefaultPrompt;

        /// <summary>
        /// 把旧版单一 prompt（snaptranslate.prompt）一次性迁移为「自定义模板 + 激活自定义」。
        /// 幂等：迁移后删除旧 key，下次不再触发。
        /// </summary>
        public void MigrateLegacyPrompt()
        {
            string? old = _store.GetString(Keys.Prompt);
            if (old == null || old.Trim().Length == 0) return;
            _store.SetString(Keys.CustomPrompt, old);
            _store.SetBool(Keys.UsesDefaultPrompt, false);
            _store.Remove(Keys.Prompt);
        }

        /// <summary>用户可编辑的默认翻译模板。</summary>
        public static string DefaultPrompt =>
            """
            我会给你一段英文文本。请你按以下结构输出：

            ## 中文翻译
            （遵循"信达雅"原则，自然流畅的中文翻译，尽量逐句翻译、保持句数与原文一致）

            ## 重要词汇
            单词：音标 ｜ 词性 ｜ 中文释义
            （列出句中较重要的词汇，跳过高中大纲基础词汇）
            （动词一律以原形列出（如 went → go）；原文为过去式 / 过去分词 / 现在分词时，请在释义中注明原文形态（如「went：go 的过去式」））

            ## 常用短语与习语
            短语 / 习语：中文释义
            （习语请标注【习语】）
            """;

        // MARK: 快捷键

        public int HotkeyKeyCode
        {
            get { lock (_lock) { return _store.GetInt(Keys.HotkeyKeyCode) ?? _defaults.HotkeyKeyCode; } }
            set { lock (_lock) { _store.SetInt(Keys.HotkeyKeyCode, value); } }
        }

        public int HotkeyModifiers
        {
            get { lock (_lock) { return _store.GetInt(Keys.HotkeyModifiers) ?? _defaults.HotkeyModifiers; } }
            set { lock (_lock) { _store.SetInt(Keys.HotkeyModifiers, value); } }
        }

        public string HotkeyDisplay
        {
            get { lock (_lock) { return _store.GetString(Keys.HotkeyDisplay) ?? _defaults.HotkeyDisplay; } }
            set { lock (_lock) { _store.SetString(Keys.HotkeyDisplay, value); } }
        }

        public int SelectionHotkeyKeyCode
        {
            get { lock (_lock) { return _store.GetInt(Keys.SelectionHotkeyKeyCode) ?? _defaults.SelectionHotkeyKeyCode; } }
            set { lock (_lock) { _store.SetInt(Keys.SelectionHotkeyKeyCode, value); } }
        }

        public int SelectionHotkeyModifiers
        {
            get { lock (_lock) { return _store.GetInt(Keys.SelectionHotkeyModifiers) ?? _defaults.SelectionHotkeyModifiers; } }
            set { lock (_lock) { _store.SetInt(Keys.SelectionHotkeyModifiers, value); } }
        }

        public string SelectionHotkeyDisplay
        {
            get { lock (_lock) { return _store.GetString(Keys.SelectionHotkeyDisplay) ?? _defaults.SelectionHotkeyDisplay; } }
            set { lock (_lock) { _store.SetString(Keys.SelectionHotkeyDisplay, value); } }
        }

        public int ClosePanelHotkeyKeyCode
        {
            get { lock (_lock) { return _store.GetInt(Keys.ClosePanelHotkeyKeyCode) ?? _defaults.ClosePanelHotkeyKeyCode; } }
            set { lock (_lock) { _store.SetInt(Keys.ClosePanelHotkeyKeyCode, value); } }
        }

        public int ClosePanelHotkeyModifiers
        {
            get { lock (_lock) { return _store.GetInt(Keys.ClosePanelHotkeyModifiers) ?? _defaults.ClosePanelHotkeyModifiers; } }
            set { lock (_lock) { _store.SetInt(Keys.ClosePanelHotkeyModifiers, value); } }
        }

        public string ClosePanelHotkeyDisplay
        {
            get { lock (_lock) { return _store.GetString(Keys.ClosePanelHotkeyDisplay) ?? _defaults.ClosePanelHotkeyDisplay; } }
            set { lock (_lock) { _store.SetString(Keys.ClosePanelHotkeyDisplay, value); } }
        }

        public int TogglePanelHotkeyKeyCode
        {
            get { lock (_lock) { return _store.GetInt(Keys.TogglePanelHotkeyKeyCode) ?? _defaults.TogglePanelHotkeyKeyCode; } }
            set { lock (_lock) { _store.SetInt(Keys.TogglePanelHotkeyKeyCode, value); } }
        }

        public int TogglePanelHotkeyModifiers
        {
            get { lock (_lock) { return _store.GetInt(Keys.TogglePanelHotkeyModifiers) ?? _defaults.TogglePanelHotkeyModifiers; } }
            set { lock (_lock) { _store.SetInt(Keys.TogglePanelHotkeyModifiers, value); } }
        }

        public string TogglePanelHotkeyDisplay
        {
            get { lock (_lock) { return _store.GetString(Keys.TogglePanelHotkeyDisplay) ?? _defaults.TogglePanelHotkeyDisplay; } }
            set { lock (_lock) { _store.SetString(Keys.TogglePanelHotkeyDisplay, value); } }
        }

        public int SplitHotkeyKeyCode
        {
            get { lock (_lock) { return _store.GetInt(Keys.SplitHotkeyKeyCode) ?? _defaults.SplitHotkeyKeyCode; } }
            set { lock (_lock) { _store.SetInt(Keys.SplitHotkeyKeyCode, value); } }
        }

        public int SplitHotkeyModifiers
        {
            get { lock (_lock) { return _store.GetInt(Keys.SplitHotkeyModifiers) ?? _defaults.SplitHotkeyModifiers; } }
            set { lock (_lock) { _store.SetInt(Keys.SplitHotkeyModifiers, value); } }
        }

        public string SplitHotkeyDisplay
        {
            get { lock (_lock) { return _store.GetString(Keys.SplitHotkeyDisplay) ?? _defaults.SplitHotkeyDisplay; } }
            set { lock (_lock) { _store.SetString(Keys.SplitHotkeyDisplay, value); } }
        }

        /// <summary>弹窗默认优先模式：true=拆分，false=整段（默认拆分）。</summary>
        public bool DefaultSplitMode
        {
            get { lock (_lock) { return _store.GetBool(Keys.DefaultSplitMode) ?? _defaults.DefaultSplitMode; } }
            set { lock (_lock) { _store.SetBool(Keys.DefaultSplitMode, value); } }
        }

        /// <summary>弹窗字号：最小 12，最大 22，默认 14（超出范围自动夹紧）。</summary>
        public int PopupFontSize
        {
            get
            {
                lock (_lock)
                {
                    int v = _store.GetInt(Keys.PopupFontSize) ?? _defaults.PopupFontSizeDefault;
                    return Math.Min(Math.Max(v, _defaults.PopupFontSizeMin), _defaults.PopupFontSizeMax);
                }
            }
            set
            {
                lock (_lock)
                {
                    int clamped = Math.Min(Math.Max(value, _defaults.PopupFontSizeMin), _defaults.PopupFontSizeMax);
                    _store.SetInt(Keys.PopupFontSize, clamped);
                }
            }
        }

        // MARK: 窗口

        public WindowFrame? WindowFrame
        {
            get
            {
                lock (_lock)
                {
                    string? s = _store.GetString(Keys.WindowFrame);
                    return Elta.Core.WindowFrame.TryParse(s, out WindowFrame? f) ? f : null;
                }
            }
            set
            {
                lock (_lock)
                {
                    if (value == null) _store.Remove(Keys.WindowFrame);
                    else _store.SetString(Keys.WindowFrame, value.ToString());
                }
            }
        }

        // MARK: 更新跳过

        /// <summary>用户选择跳过的版本号，此版本不再提醒更新。</summary>
        public string? SkipUpdateVersion
        {
            get { lock (_lock) { return _store.GetString(Keys.SkipUpdateVersion); } }
            set
            {
                lock (_lock)
                {
                    if (value == null) _store.Remove(Keys.SkipUpdateVersion);
                    else _store.SetString(Keys.SkipUpdateVersion, value);
                }
            }
        }

        // MARK: 匿名使用统计

        /// <summary>匿名安装标识：首次读取时生成随机 UUID 并持久化，不含任何设备/个人信息。</summary>
        public string InstallId
        {
            get
            {
                lock (_lock)
                {
                    string? existing = _store.GetString(Keys.InstallId);
                    if (!string.IsNullOrEmpty(existing)) return existing!;
                    string id = Guid.NewGuid().ToString();
                    _store.SetString(Keys.InstallId, id);
                    return id;
                }
            }
        }

        /// <summary>是否参与匿名使用统计（默认开启）。</summary>
        public bool TelemetryEnabled
        {
            get { lock (_lock) { return _store.GetBool(Keys.TelemetryEnabled) ?? _defaults.TelemetryEnabled; } }
            set { lock (_lock) { _store.SetBool(Keys.TelemetryEnabled, value); } }
        }
    }
}
