using System;

namespace Elta.Core
{
    /// <summary>
    /// 设置持久化抽象。平台无关：Windows 外壳注入注册表或 %APPDATA% JSON 实现，
    /// 单元测试注入内存双替。<see cref="GetBool"/> / <see cref="GetInt"/> 返回 null 表示「未设置」，
    /// 用于区分「未设置」与「值为 false/0」（例如 keyCode=0 是合法值，不能被默认值覆盖）。
    /// </summary>
    public interface ISettingsStore
    {
        string? GetString(string key);
        bool? GetBool(string key);
        int? GetInt(string key);

        void SetString(string key, string? value);
        void SetBool(string key, bool value);
        void SetInt(string key, int value);

        void Remove(string key);
        bool Contains(string key);
    }
}
