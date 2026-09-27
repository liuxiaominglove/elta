using System;

namespace Elta.Core
{
    /// <summary>
    /// 取词文本的纯逻辑。移植自 macOS 版 TranslationPipeline 的
    /// <c>substringInRange</c> 与选中文本可用性判定。
    /// </summary>
    public static class SelectionText
    {
        /// <summary>
        /// 从 <paramref name="fullText"/> 按 UTF-16 代码单元区间截取子串。
        /// 注意：Accessibility / UIA 的选区偏移是 UTF-16 单元（NSString/CFRange 语义），
        /// 不能用字素计数，否则含 emoji/生僻字时偏移错。区间无效或结果为空返回 null。
        /// </summary>
        public static string? SubstringInRange(string fullText, int utf16Location, int utf16Length)
        {
            ArgumentNullException.ThrowIfNull(fullText);
            if (utf16Location < 0 || utf16Length <= 0) return null;
            if ((long)utf16Location + utf16Length > fullText.Length) return null;

            string sub = fullText.Substring(utf16Location, utf16Length);
            return sub.Length == 0 ? null : sub;
        }

        /// <summary>选中文本是否可用（非 null 且非空；空白串按 mac 语义视为可用）。</summary>
        public static bool IsUsable(string? text) => !string.IsNullOrEmpty(text);
    }
}
