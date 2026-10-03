using System;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Elta.Core;

namespace Elta.Windows
{
    /// <summary>
    /// B4：基于 `%APPDATA%\ELTA\settings.json` 的 <see cref="ISettingsStore"/> 实现（对应 mac UserDefaults）。
    /// 每次写操作整文件原子落盘（设置写入低频，简单优先）；解析失败自动备份为 `.corrupt-*` 并从空开始。
    /// </summary>
    internal sealed class JsonSettingsStore : ISettingsStore
    {
        // .NET 8：JsonNode.ToJsonString(options) 首次使用会冻结 options，复用前必须显式给 TypeInfoResolver
        private static readonly JsonSerializerOptions WriteOptions = new()
        {
            WriteIndented = true,
            TypeInfoResolver = new System.Text.Json.Serialization.Metadata.DefaultJsonTypeInfoResolver(),
        };

        private readonly object _lock = new();
        private readonly string _filePath;
        private JsonObject _data;
        private bool _loadFailed;

        public JsonSettingsStore(string? filePath = null)
        {
            _filePath = filePath ?? Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ELTA", "settings.json");
            _data = Load();
        }

        public string FilePath => _filePath;

        private JsonObject Load()
        {
            try
            {
                if (!File.Exists(_filePath)) return new JsonObject();
                string json = File.ReadAllText(_filePath, Encoding.UTF8);
                if (string.IsNullOrWhiteSpace(json)) return new JsonObject();
                return JsonNode.Parse(json) as JsonObject ?? new JsonObject();
            }
            catch (JsonException ex)
            {
                Log.Error("settings parse failed, backing up and starting fresh", ex);
                try
                {
                    File.Move(_filePath, _filePath + ".corrupt-" + DateTime.Now.ToString("yyyyMMddHHmmss"), overwrite: true);
                }
                catch { }
                return new JsonObject();
            }
            catch (Exception ex)
            {
                // 瞬时 IO 错误（AV/同步持锁）≠ 损坏：不动原文件，且禁止后续 Save 覆盖
                Log.Error("settings load failed (file kept intact)", ex);
                _loadFailed = true;
                return new JsonObject();
            }
        }

        private void Save()
        {
            if (_loadFailed)
            {
                Log.Error("settings save skipped: initial load failed, refusing to overwrite intact file");
                return;
            }
            try
            {
                // 裸文件名（无目录分量）时 GetDirectoryName 返回 ""，CreateDirectory("") 会抛异常 → 先判空
                string? dir = Path.GetDirectoryName(_filePath);
                if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
                string json = _data.ToJsonString(WriteOptions);
                string tmp = _filePath + ".tmp";
                File.WriteAllText(tmp, json, new UTF8Encoding(false));
                File.Move(tmp, _filePath, overwrite: true);
            }
            catch (Exception ex)
            {
                Log.Error("settings save failed", ex);
            }
        }

        // 注意：不能用泛型 `T? GetValue<T>`——对 int/bool，泛型 T? 只是注解，缺失时会返回 0/false
        // 而非 null，导致上层 `?? 默认值` 永远不触发（曾实测踩坑）。这里按类型显式实现。

        public string? GetString(string key)
        {
            lock (_lock)
            {
                return _data.TryGetPropertyValue(key, out JsonNode? node)
                    && node is JsonValue value
                    && value.TryGetValue(out string? typed)
                    ? typed
                    : null;
            }
        }

        public bool? GetBool(string key)
        {
            lock (_lock)
            {
                return _data.TryGetPropertyValue(key, out JsonNode? node)
                    && node is JsonValue value
                    && value.TryGetValue(out bool typed)
                    ? typed
                    : null;
            }
        }

        public int? GetInt(string key)
        {
            lock (_lock)
            {
                return _data.TryGetPropertyValue(key, out JsonNode? node)
                    && node is JsonValue value
                    && value.TryGetValue(out int typed)
                    ? typed
                    : null;
            }
        }

        public void SetString(string key, string? value)
        {
            lock (_lock) { SetValue(key, value); }
        }

        public void SetBool(string key, bool value)
        {
            lock (_lock) { SetValue(key, value); }
        }

        public void SetInt(string key, int value)
        {
            lock (_lock) { SetValue(key, value); }
        }

        private void SetValue<T>(string key, T? value)
        {
            if (value is null) _data.Remove(key);
            else _data[key] = JsonValue.Create(value);
            Save();
        }

        public void Remove(string key)
        {
            lock (_lock) { _data.Remove(key); Save(); }
        }

        public bool Contains(string key)
        {
            lock (_lock) { return _data.ContainsKey(key); }
        }
    }
}
