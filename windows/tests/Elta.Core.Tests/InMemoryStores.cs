using System.Collections.Generic;
using Elta.Core;

namespace Elta.Core.Tests
{
    /// <summary>内存设置存储双替（线程安全）。</summary>
    public sealed class InMemorySettingsStore : ISettingsStore
    {
        private readonly object _lock = new object();
        private readonly Dictionary<string, object> _values = new Dictionary<string, object>();

        public string? GetString(string key)
        {
            lock (_lock) { return _values.TryGetValue(key, out object? v) ? v as string : null; }
        }

        public bool? GetBool(string key)
        {
            lock (_lock) { return _values.TryGetValue(key, out object? v) && v is bool b ? b : (bool?)null; }
        }

        public int? GetInt(string key)
        {
            lock (_lock) { return _values.TryGetValue(key, out object? v) && v is int i ? i : (int?)null; }
        }

        public void SetString(string key, string? value)
        {
            lock (_lock)
            {
                if (value == null) _values.Remove(key);
                else _values[key] = value;
            }
        }

        public void SetBool(string key, bool value) { lock (_lock) { _values[key] = value; } }
        public void SetInt(string key, int value) { lock (_lock) { _values[key] = value; } }
        public void Remove(string key) { lock (_lock) { _values.Remove(key); } }
        public bool Contains(string key) { lock (_lock) { return _values.ContainsKey(key); } }
    }

    /// <summary>内存密钥库双替（线程安全，永不失败）。</summary>
    public sealed class InMemorySecretStore : ISecretStore
    {
        private readonly object _lock = new object();
        private readonly Dictionary<string, string> _secrets = new Dictionary<string, string>();

        public bool Save(string account, string secret)
        {
            lock (_lock) { _secrets[account] = secret; return true; }
        }

        public string? Read(string account)
        {
            lock (_lock) { return _secrets.TryGetValue(account, out string? v) ? v : null; }
        }

        public bool Delete(string account)
        {
            lock (_lock) { _secrets.Remove(account); return true; }
        }
    }
}
