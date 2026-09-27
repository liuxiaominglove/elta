namespace Elta.Core
{
    /// <summary>
    /// 密钥（API Key）安全存储抽象。对应 macOS 版的 KeychainHelper：
    /// Windows 外壳注入 DPAPI 加密文件或凭据管理器实现，单元测试注入内存双替。
    /// 实现须保证 <see cref="Save"/> 为 update-or-add（保留旧值，避免「先删后加」失败丢 key）。
    /// </summary>
    public interface ISecretStore
    {
        /// <summary>保存（已存在则更新）。返回是否成功；失败时调用方须保留旧值。</summary>
        bool Save(string account, string secret);

        /// <summary>读取；不存在返回 null。</summary>
        string? Read(string account);

        /// <summary>删除；不存在视为成功（幂等）。</summary>
        bool Delete(string account);
    }
}
