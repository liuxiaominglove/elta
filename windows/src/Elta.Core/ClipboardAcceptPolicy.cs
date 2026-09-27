using System;
using System.Collections.Generic;
using System.Linq;

namespace Elta.Core
{
    /// <summary>
    /// Ctrl+C 兜底取词时，「是否接受剪贴板新内容」的判定。移植自 macOS 版
    /// <c>getSelectedTextViaCopyPasteboard</c>：先看剪贴板序号是否变化，未变化再兜底比对旧文本。
    /// 实际的剪贴板抓取/写回由平台外壳（Windows 的 ClipboardService）完成，
    /// 快照须深拷贝，不持有原剪贴板对象引用。
    /// </summary>
    public static class ClipboardAcceptPolicy
    {
        /// <summary>剪贴板序号（changeCount）变化且新文本非空 → 接受。</summary>
        public static bool AcceptByChangeCount(bool changeCountChanged, string? newText)
            => changeCountChanged && !string.IsNullOrEmpty(newText);

        /// <summary>兜底：部分程序不更新剪贴板序号；新文本非空且不等于任一条旧文本 → 接受。</summary>
        public static bool AcceptByFallback(string? newText, IReadOnlyList<string> previousTexts)
        {
            ArgumentNullException.ThrowIfNull(previousTexts);
            return !string.IsNullOrEmpty(newText) && !previousTexts.Contains(newText);
        }
    }
}
