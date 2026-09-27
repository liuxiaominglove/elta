using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace Elta.Core
{
    /// <summary>
    /// 文本归一化：段内单 \n 合并为空格，\n\n 保留为段落间隔，去掉首尾多余空行。
    /// 移植自 macOS 版 Sources/Helpers.swift 的 TextNormalizer。
    /// </summary>
    public static class TextNormalizer
    {
        private static readonly Regex NewlineIndent =
            new Regex("\\n[\\t ]+", RegexOptions.Compiled);

        private static readonly string[] ParagraphSeparator = { "\n\n" };

        public static string NormalizeLineBreaks(string text)
        {
            ArgumentNullException.ThrowIfNull(text);

            string result = NewlineIndent.Replace(text, "\n\n");

            var processed = new List<string>();
            foreach (string paragraph in result.Split(ParagraphSeparator, StringSplitOptions.None))
            {
                string line = string.Join(" ", paragraph
                    .Split('\n')
                    .Select(l => l.Trim())
                    .Where(l => l.Length > 0));
                if (line.Length > 0)
                {
                    processed.Add(line);
                }
            }

            return string.Join("\n\n", processed);
        }
    }
}
