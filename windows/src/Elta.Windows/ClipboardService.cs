using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;
using Elta.Core;

namespace Elta.Windows
{
    /// <summary>
    /// 剪贴板深拷贝快照与恢复（B2 / WI-1）。教训来自 mac PasteboardSnapshot：
    /// 不持有原剪贴板对象的懒引用——流须深拷贝到 MemoryStream，否则原剪贴板一变就失效/崩溃。
    ///
    /// WI-1 安全要点：
    /// - 捕获是否成功要**显式记录**（<see cref="CaptureSucceeded"/>），不能把「读取失败」与「原本为空」混为一谈；
    /// - 处置动作由 Core <see cref="ClipboardRestorePolicy"/> 决定，**捕获失败时绝不清空**；
    /// - 剪贴板是共享可锁资源，读写均带退避重试；
    /// - 单格式超过 50MB 跳过并标 <see cref="Partial"/>，防内存翻倍。
    /// </summary>
    internal sealed class ClipboardState
    {
        private const int MaxAttempts = 5;
        private const int RetryDelayMs = 30;
        private const long MaxFormatBytes = 50L * 1024 * 1024;

        private readonly List<(string Format, object? Data)> _items = new();

        /// <summary>是否成功读到剪贴板（null 的 DataObject = 空剪贴板，也算成功）。</summary>
        public bool CaptureSucceeded { get; private set; }

        /// <summary>是否有格式因超限/异常被跳过（快照不完整，但仍有还原价值）。</summary>
        public bool Partial { get; private set; }

        public int Count => _items.Count;

        /// <summary>诊断用：构造一个「捕获失败」状态（无项、CaptureSucceeded=false），供 --selftest 验证不清空行为。</summary>
        public static ClipboardState SimulateCaptureFailure() => new();

        public static ClipboardState Capture()
        {
            var state = new ClipboardState();
            for (int attempt = 0; attempt < MaxAttempts; attempt++)
            {
                try
                {
                    IDataObject? data = Clipboard.GetDataObject();
                    state.CaptureSucceeded = true;
                    if (data == null) return state;   // 空剪贴板
                    state.Collect(data);
                    return state;
                }
                catch (ExternalException)
                {
                    Thread.Sleep(RetryDelayMs * (attempt + 1));   // 被其他进程占用：退避重试
                }
                catch
                {
                    break;   // 其他异常：不重试，CaptureSucceeded 保持 false
                }
            }
            return state;
        }

        private void Collect(IDataObject data)
        {
            string[] formats;
            try { formats = data.GetFormats(); }
            catch { Partial = true; return; }

            foreach (string format in formats)
            {
                try
                {
                    object? value = data.GetData(format, autoConvert: true);
                    if (value is Stream stream)
                    {
                        if (!TryCopyStream(stream, out MemoryStream? copy))
                        {
                            Partial = true;
                            continue;
                        }
                        value = copy;
                    }
                    if (value == null)
                    {
                        Partial = true;
                        continue;
                    }
                    _items.Add((format, value));
                }
                catch
                {
                    Partial = true;   // 个别格式不可克隆，跳过
                }
            }
        }

        private static bool TryCopyStream(Stream stream, out MemoryStream? copy)
        {
            copy = null;
            try
            {
                if (stream.CanSeek)
                {
                    if (stream.Length > MaxFormatBytes) return false;
                    stream.Position = 0;
                }

                var ms = new MemoryStream();
                var buffer = new byte[81920];
                long total = 0;
                int read;
                while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
                {
                    total += read;
                    if (total > MaxFormatBytes)
                    {
                        ms.Dispose();
                        return false;
                    }
                    ms.Write(buffer, 0, read);
                }
                ms.Position = 0;
                copy = ms;
                return true;
            }
            catch
            {
                copy?.Dispose();
                copy = null;
                return false;
            }
        }

        /// <summary>按 Core 策略处置剪贴板。LeaveAsIs 不动；Restore 写回快照；Clear 仅清残留。返回是否成功。</summary>
        public bool Apply(ClipboardRestoreAction action)
        {
            switch (action)
            {
                case ClipboardRestoreAction.Restore: return WriteBack();
                case ClipboardRestoreAction.Clear: return TryClear();
                default: return true;
            }
        }

        private bool WriteBack()
        {
            for (int attempt = 0; attempt < MaxAttempts; attempt++)
            {
                try
                {
                    var data = new DataObject();
                    foreach ((string format, object? value) in _items)
                    {
                        if (value == null) continue;
                        try { data.SetData(format, value); } catch { }
                    }
                    Clipboard.SetDataObject(data, copy: true);
                    return true;
                }
                catch (ExternalException)
                {
                    Thread.Sleep(RetryDelayMs * (attempt + 1));
                }
                catch
                {
                    return false;
                }
            }
            return false;
        }

        private static bool TryClear()
        {
            for (int attempt = 0; attempt < MaxAttempts; attempt++)
            {
                try
                {
                    Clipboard.Clear();
                    return true;
                }
                catch (ExternalException)
                {
                    Thread.Sleep(RetryDelayMs * (attempt + 1));
                }
                catch
                {
                    return false;
                }
            }
            return false;
        }
    }

    internal static class ClipboardService
    {
        /// <summary>当前剪贴板文本；无文本或读取失败返回 null。带退避重试。</summary>
        public static string? GetText()
        {
            for (int attempt = 0; attempt < 5; attempt++)
            {
                try
                {
                    if (Clipboard.ContainsText()) return Clipboard.GetText();
                    return Clipboard.GetDataObject()?.GetData(DataFormats.UnicodeText) as string;
                }
                catch (ExternalException)
                {
                    Thread.Sleep(30 * (attempt + 1));
                }
                catch
                {
                    return null;
                }
            }
            return null;
        }
    }
}
