using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using Elta.Core;

namespace Elta.Windows
{
    /// <summary>
    /// B4：DPAPI（CurrentUser）加密文件的 <see cref="ISecretStore"/> 实现（对应 mac Keychain）。
    /// 每账户一个文件，文件名 = SHA256(account) 十六进制（避免明文账户名落盘）；
    /// 内容为 DPAPI 保护后的字节。Save 为 update-or-add；Delete 幂等；失败只记录不抛。
    /// 日志只出现账户哈希前缀，**绝不出现密钥内容**。
    /// </summary>
    internal sealed class DpapiSecretStore : ISecretStore
    {
        private readonly string _dir;

        public DpapiSecretStore(string? directory = null)
        {
            _dir = directory ?? Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ELTA", "secrets");
        }

        public string DirectoryPath => _dir;

        private string FileFor(string account)
        {
            byte[] hash = SHA256.HashData(Encoding.UTF8.GetBytes(account));
            return Path.Combine(_dir, Convert.ToHexString(hash) + ".bin");
        }

        public bool Save(string account, string secret)
        {
            try
            {
                Directory.CreateDirectory(_dir);
                byte[] plain = Encoding.UTF8.GetBytes(secret);
                byte[] protectedBytes = ProtectedData.Protect(plain, optionalEntropy: null, DataProtectionScope.CurrentUser);
                string path = FileFor(account);
                string tmp = path + ".tmp";
                File.WriteAllBytes(tmp, protectedBytes);
                File.Move(tmp, path, overwrite: true);
                return true;
            }
            catch (Exception ex)
            {
                Log.Error($"secret save failed account-hash={ShortHash(account)}", ex);
                return false;
            }
        }

        public string? Read(string account)
        {
            try
            {
                string path = FileFor(account);
                if (!File.Exists(path)) return null;
                byte[] protectedBytes = File.ReadAllBytes(path);
                byte[] plain = ProtectedData.Unprotect(protectedBytes, optionalEntropy: null, DataProtectionScope.CurrentUser);
                return Encoding.UTF8.GetString(plain);
            }
            catch (Exception ex)
            {
                Log.Error($"secret read failed account-hash={ShortHash(account)}", ex);
                return null;
            }
        }

        public bool Delete(string account)
        {
            try
            {
                string path = FileFor(account);
                if (File.Exists(path)) File.Delete(path);
                return true;
            }
            catch (Exception ex)
            {
                Log.Error($"secret delete failed account-hash={ShortHash(account)}", ex);
                return false;
            }
        }

        private static string ShortHash(string account)
        {
            byte[] hash = SHA256.HashData(Encoding.UTF8.GetBytes(account));
            return Convert.ToHexString(hash)[..8];
        }
    }
}
