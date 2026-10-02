using System;
using System.Globalization;
using System.IO;
using System.Text;

namespace Elta.Windows
{
    /// <summary>
    /// WI-2 极简文件日志。原则：
    /// - **绝不记录敏感内容**（只记状态/长度/耗时）；消息内换行会被清洗、超长会截断；
    /// - 任何写盘失败都静默降级，绝不因日志导致崩溃；
    /// - 按天分文件，保留最近 7 天；单文件超 2MB 滚动为 `.1`（尽力而为）。
    /// </summary>
    internal static class Log
    {
        private const int MaxMessageLength = 500;
        private const long MaxFileBytes = 2 * 1024 * 1024;
        private const int KeepDays = 7;

        private static readonly object Gate = new();
        private static readonly string LogDir = ResolveLogDir();
        private static string? _currentDate;
        private static string? _currentPath;

        /// <summary>日志目录（诊断用；可能为空字符串表示不可写且降级失败）。</summary>
        public static string DirectoryPath => LogDir;

        public static void Info(string message) => Write("INFO", message);
        public static void Warn(string message) => Write("WARN", message);
        public static void Error(string message) => Write("ERROR", message);

        public static void Error(string message, Exception? ex)
            => Write("ERROR", ex is null ? message : $"{message} | {ex.GetType().Name}: {ex.Message}");

        private static string ResolveLogDir()
        {
            try
            {
                string baseDir = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                if (!string.IsNullOrEmpty(baseDir))
                {
                    string dir = Path.Combine(baseDir, "ELTA", "logs");
                    Directory.CreateDirectory(dir);
                    return dir;
                }
            }
            catch { }

            try
            {
                string dir = Path.Combine(Path.GetTempPath(), "ELTA-logs");
                Directory.CreateDirectory(dir);
                return dir;
            }
            catch { }

            return string.Empty;
        }

        private static void Write(string level, string message)
        {
            if (string.IsNullOrEmpty(LogDir)) return;

            lock (Gate)
            {
                try
                {
                    string date = DateTime.Now.ToString("yyyyMMdd", CultureInfo.InvariantCulture);
                    if (_currentDate != date)
                    {
                        _currentDate = date;
                        _currentPath = Path.Combine(LogDir, $"elta-{date}.log");
                        CleanupOldFiles();
                    }

                    string line = $"[{DateTime.Now:HH:mm:ss.fff}] [{level}] {Sanitize(message)}{Environment.NewLine}";
                    byte[] bytes = Encoding.UTF8.GetBytes(line);

                    using var fs = new FileStream(_currentPath!, FileMode.Append, FileAccess.Write, FileShare.ReadWrite);
                    if (fs.Length > MaxFileBytes)
                    {
                        RollCurrentFile();
                    }
                    fs.Write(bytes, 0, bytes.Length);
                }
                catch
                {
                    // 日志失败绝不影响主流程
                }
            }
        }

        private static void RollCurrentFile()
        {
            try
            {
                string rolled = _currentPath + ".1";
                if (File.Exists(rolled))
                {
                    try { File.Delete(rolled); } catch { }
                }
                File.Move(_currentPath!, rolled);
            }
            catch
            {
                // 移动失败（被占用等）则继续追加，超限仅尽力而为
            }
        }

        private static void CleanupOldFiles()
        {
            try
            {
                DateTime cutoff = DateTime.Now.AddDays(-KeepDays);
                foreach (string file in Directory.GetFiles(LogDir, "elta-*.log*"))
                {
                    try
                    {
                        if (File.GetLastWriteTime(file) < cutoff) File.Delete(file);
                    }
                    catch { }
                }
            }
            catch { }
        }

        private static string Sanitize(string message)
        {
            if (string.IsNullOrEmpty(message)) return string.Empty;
            var sb = new StringBuilder(message.Length);
            foreach (char c in message)
            {
                sb.Append(c is '\r' or '\n' or '\t' ? ' ' : c);
                if (sb.Length >= MaxMessageLength) break;
            }
            return sb.ToString();
        }
    }
}
