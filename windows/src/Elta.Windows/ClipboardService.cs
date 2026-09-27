using System;
using System.Collections.Generic;
using System.IO;
using System.Windows.Forms;

namespace Elta.Windows
{
    /// <summary>
    /// 剪贴板深拷贝快照与恢复（B2）。教训来自 mac PasteboardSnapshot：
    /// 不持有原剪贴板对象的懒引用——流须深拷贝到 MemoryStream，否则原剪贴板一变就失效/崩溃。
    /// </summary>
    internal sealed class ClipboardState
    {
        private readonly List<(string Format, object? Data)> _items = new();

        public int Count => _items.Count;

        public static ClipboardState Capture()
        {
            var state = new ClipboardState();
            try
            {
                IDataObject? data = Clipboard.GetDataObject();
                if (data == null) return state;
                foreach (string format in data.GetFormats())
                {
                    try
                    {
                        object? value = data.GetData(format, autoConvert: true);
                        if (value is Stream stream && stream.CanSeek)
                        {
                            stream.Position = 0;
                            var ms = new MemoryStream();
                            stream.CopyTo(ms);
                            ms.Position = 0;
                            value = ms;
                        }
                        state._items.Add((format, value));
                    }
                    catch { /* 个别格式不可克隆，跳过 */ }
                }
            }
            catch { }
            return state;
        }

        /// <summary>用全新的 DataObject 写回；空快照则清空（清除 Ctrl+C 残留）。返回是否成功。</summary>
        public bool Restore()
        {
            try
            {
                if (_items.Count == 0)
                {
                    Clipboard.Clear();
                    return true;
                }
                var data = new DataObject();
                foreach ((string format, object? value) in _items)
                {
                    if (value == null) continue;
                    try { data.SetData(format, value); } catch { }
                }
                Clipboard.SetDataObject(data, copy: true);
                return true;
            }
            catch
            {
                return false;
            }
        }
    }

    internal static class ClipboardService
    {
        /// <summary>当前剪贴板文本；无文本返回 null。</summary>
        public static string? GetText()
        {
            try
            {
                if (Clipboard.ContainsText()) return Clipboard.GetText();
                return Clipboard.GetDataObject()?.GetData(DataFormats.UnicodeText) as string;
            }
            catch
            {
                return null;
            }
        }
    }
}
