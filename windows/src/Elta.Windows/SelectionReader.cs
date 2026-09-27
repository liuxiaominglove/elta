using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Automation;
using System.Windows.Automation.Text;
using Elta.Core;

namespace Elta.Windows
{
    /// <summary>
    /// 取词（B2）：优先 UIA TextPattern 读选中文本，失败回退 Ctrl+C + 剪贴板。
    /// P0.5 结论：Chrome / WPS 文字 / WPS PDF 读不到 UIA → **Ctrl+C 兜底为主路径**。
    /// </summary>
    internal static class SelectionReader
    {
        private const byte VK_CONTROL = 0x11;
        private const byte VK_C = 0x43;
        private const uint KEYEVENTF_KEYUP = 0x0002;
        private const int MaxRetries = 15;      // 最多约 1.5 秒
        private const int RetryDelayMs = 100;
        private const int MaxParentDepth = 10;

        [DllImport("user32.dll")]
        private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

        [DllImport("user32.dll")]
        private static extern uint GetClipboardSequenceNumber();

        /// <summary>读取当前选中文本；未取到返回 null。调用前应先等用户松开热键。</summary>
        public static string? ReadSelectedText()
        {
            string? viaUia = TryUia();
            if (SelectionText.IsUsable(viaUia)) return viaUia;
            return TryCopyFallback();
        }

        /// <summary>UIA 读焦点元素的选中文本（含父链上溯，应对浏览器选区在文档层）。失败返回 null。</summary>
        public static string? TryUia()
        {
            try
            {
                AutomationElement? element = AutomationElement.FocusedElement;
                for (int depth = 0; depth < MaxParentDepth && element != null; depth++)
                {
                    if (element.TryGetCurrentPattern(TextPattern.Pattern, out object patternObj)
                        && patternObj is TextPattern textPattern)
                    {
                        TextPatternRange[] ranges = textPattern.GetSelection();
                        foreach (TextPatternRange range in ranges)
                        {
                            string text = range.GetText(-1);
                            if (!string.IsNullOrEmpty(text)) return text;
                        }
                    }
                    element = TreeWalker.ControlViewWalker.GetParent(element);
                }
            }
            catch { }
            return null;
        }

        /// <summary>Ctrl+C + 剪贴板兜底（主路径）。取词后恢复原剪贴板。</summary>
        public static string? TryCopyFallback()
        {
            uint oldSequence = GetClipboardSequenceNumber();
            ClipboardState snapshot = ClipboardState.Capture();
            string? oldText = ClipboardService.GetText();
            var previousTexts = new List<string>();
            if (!string.IsNullOrEmpty(oldText)) previousTexts.Add(oldText!);

            SendCtrlC();

            string? selected = null;
            for (int i = 0; i < MaxRetries; i++)
            {
                Thread.Sleep(RetryDelayMs);
                string? newText = ClipboardService.GetText();
                if (ClipboardAcceptPolicy.AcceptByChangeCount(GetClipboardSequenceNumber() != oldSequence, newText))
                {
                    selected = newText;
                    break;
                }
            }
            if (selected == null)
            {
                string? newText = ClipboardService.GetText();
                if (ClipboardAcceptPolicy.AcceptByFallback(newText, previousTexts)) selected = newText;
            }

            snapshot.Restore();
            return selected;
        }

        private static void SendCtrlC()
        {
            keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
            keybd_event(VK_C, 0, 0, UIntPtr.Zero);
            keybd_event(VK_C, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
            keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        }
    }
}
