using System;
using System.IO;
using System.Text;
using Elta.Windows;
using Xunit;

namespace Elta.Windows.Tests
{
    /// <summary>JsonSettingsStore（B4）审计修复的单测：纯文件 IO，可自动验证。</summary>
    public class JsonSettingsStoreTests
    {
        private static string TempPath()
            => Path.Combine(Path.GetTempPath(), "elta-settings-" + Guid.NewGuid().ToString("N") + ".json");

        [Fact]
        public void SetString_Persists_And_Reloads()
        {
            string path = TempPath();
            try
            {
                new JsonSettingsStore(path).SetString("k", "v");
                Assert.True(File.Exists(path));
                Assert.Equal("v", new JsonSettingsStore(path).GetString("k"));
            }
            finally { if (File.Exists(path)) File.Delete(path); }
        }

        // 审计修复 #12：裸文件名（无目录分量）时 CreateDirectory("") 抛异常 → 静默不落盘
        [Fact]
        public void SetString_WithBareFilename_StillPersists()
        {
            string name = "elta-bare-" + Guid.NewGuid().ToString("N") + ".json";
            string full = Path.Combine(Directory.GetCurrentDirectory(), name);
            try
            {
                new JsonSettingsStore(name).SetString("k", "v");
                Assert.True(File.Exists(full), "裸文件名也应落盘（#12）");
            }
            finally { if (File.Exists(full)) File.Delete(full); }
        }

        // 审计修复 #11：瞬时读取失败（文件被独占锁）不得被当作「损坏」而覆盖完好文件
        [Fact]
        public void Load_TransientIoError_DoesNotOverwriteIntactFile()
        {
            string path = TempPath();
            try
            {
                File.WriteAllText(path, "{\"keep\":\"me\"}", new UTF8Encoding(false));

                JsonSettingsStore store;
                using (new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.None))
                {
                    store = new JsonSettingsStore(path);   // 读取被锁 → IOException
                }

                // 锁已释放：修复前 Save 会用空数据覆盖 → "keep" 丢失；修复后应跳过 Save
                store.SetString("new", "value");
                Assert.Contains("keep", File.ReadAllText(path));
            }
            finally { if (File.Exists(path)) File.Delete(path); }
        }
    }
}
