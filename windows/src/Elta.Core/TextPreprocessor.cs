using System;
using System.Text.RegularExpressions;

namespace Elta.Core
{
    /// <summary>
    /// 检测并压缩 Apple Books 的四行/三行中文引用块为单行。
    /// 移植自 macOS 版 Sources/TextPreprocessor.swift。
    /// </summary>
    public static class TextPreprocessor
    {
        private static readonly Regex FourLine = new Regex(
            "摘录来自\n([^\n]+)\n([^\n]+)\n此材料受版权保护。", RegexOptions.Compiled);

        private static readonly Regex ThreeLine = new Regex(
            "摘录来自\n([^\n]+)\n此材料受版权保护。", RegexOptions.Compiled);

        public static string CondenseCitation(string text)
        {
            ArgumentNullException.ThrowIfNull(text);

            string result = FourLine.Replace(text, "摘录来自《$1》$2");
            result = ThreeLine.Replace(result, "摘录来自《$1》");
            return result;
        }
    }
}
