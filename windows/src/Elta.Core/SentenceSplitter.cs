using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace Elta.Core
{
    /// <summary>原文句与译文句的一对。</summary>
    public sealed record SplitPair(string Original, string Translation);

    /// <summary>
    /// 把原文（英文）与译文（中文）拆句并配对，用于「拆分翻译」逐句对照。
    /// 移植自 macOS 版 Sources/SentenceSplitter.swift。
    /// </summary>
    public static class SentenceSplitter
    {
        // 常见英文缩写（避免在缩写后的句号处误拆）
        private static readonly HashSet<string> Abbreviations = new HashSet<string>(StringComparer.Ordinal)
        {
            "Mr", "Mrs", "Ms", "Dr", "Prof", "St", "Mt", "vs", "etc", "No",
            "Inc", "Ltd", "Jr", "Sr", "Co", "Gen", "Rep", "Sen", "Jan", "Feb",
            "Mar", "Apr", "Jun", "Jul", "Aug", "Sep", "Sept", "Oct", "Nov", "Dec",
        };

        // 含中间句点的多段缩写
        private static readonly HashSet<string> MultiDotAbbreviations = new HashSet<string>(StringComparer.Ordinal)
        {
            "e.g", "i.e", "U.S", "U.K", "Ph.D", "M.D", "B.C", "A.D", "vs", "a.m", "p.m",
        };

        // 含空格的多词缩写
        private static readonly HashSet<string> MultiWordAbbreviations = new HashSet<string>(StringComparer.Ordinal)
        {
            "et al",
        };

        // 匹配 Apple Books 引用元信息「摘录来自《书名》…」，拆分前整段剔除
        private static readonly Regex CitationRegex =
            new Regex("摘录来自《[^》]+》[^\\n]*", RegexOptions.Compiled);

        private static readonly char[] ParagraphSeparators = { '\n' };
        private static readonly char[] LineSeparators = { '\n', '\r' };

        // MARK: - 英文分句

        public static List<string> SplitEnglish(string text)
        {
            ArgumentNullException.ThrowIfNull(text);

            string cleaned = CitationRegex.Replace(text, "");

            var result = new List<string>();
            foreach (string paragraph in cleaned.Split(new[] { "\n\n" }, StringSplitOptions.None))
            {
                string singleLine = string.Join(" ", paragraph
                    .Split(LineSeparators)
                    .Select(l => l.Trim())
                    .Where(l => l.Length > 0));
                if (singleLine.Length == 0) continue;
                result.AddRange(SplitEnglishSentences(singleLine));
            }
            return result;
        }

        private static List<string> SplitEnglishSentences(string text)
        {
            char[] chars = text.ToCharArray();
            var sentences = new List<string>();
            int start = 0;
            int i = 0;

            while (i < chars.Length)
            {
                char c = chars[i];
                bool isTerminator = c == '.' || c == '!' || c == '?';
                if (isTerminator && !IsAbbreviationDot(chars, i))
                {
                    int j = i + 1;
                    while (j < chars.Length && IsClosingPunctuation(chars[j])) j++;
                    if (j >= chars.Length)
                    {
                        AppendTrimmed(sentences, chars, start, j);
                        start = j; i = j; continue;
                    }
                    if (chars[j] == ' ' || chars[j] == '\t' || chars[j] == '\n')
                    {
                        int k = j;
                        while (k < chars.Length && (chars[k] == ' ' || chars[k] == '\t' || chars[k] == '\n')) k++;
                        if (k >= chars.Length)
                        {
                            AppendTrimmed(sentences, chars, start, j);
                            start = j; i = j; continue;
                        }
                        char next = chars[k];
                        int m = k;
                        while (m < chars.Length && IsOpeningPunctuation(chars[m])) m++;
                        char effectiveNext = m < chars.Length ? chars[m] : next;
                        if (char.IsUpper(effectiveNext) || char.IsDigit(effectiveNext))
                        {
                            AppendTrimmed(sentences, chars, start, j);
                            start = j; i = j; continue;
                        }
                    }
                }
                i++;
            }

            AppendTrimmed(sentences, chars, start, chars.Length);
            return sentences;
        }

        private static bool IsAbbreviationDot(char[] chars, int index)
        {
            if (index < 0 || index >= chars.Length || chars[index] != '.') return false;

            if (index >= 3)
            {
                string seg = new string(chars, index - 3, 3);
                if (MultiDotAbbreviations.Contains(seg)) return true;
            }

            int k = index - 1;
            string word = "";
            while (k >= 0 && char.IsLetter(chars[k]))
            {
                word = chars[k] + word;
                k--;
            }
            if (Abbreviations.Contains(word)) return true;

            if (word.Length > 0)
            {
                int m = k;
                while (m >= 0 && chars[m] == ' ') m--;
                string prev = "";
                while (m >= 0 && char.IsLetter(chars[m]))
                {
                    prev = chars[m] + prev;
                    m--;
                }
                if (MultiWordAbbreviations.Contains(prev + " " + word)) return true;
            }

            if (word.Length == 1 && char.IsUpper(word[0])) return true;

            return false;
        }

        private static bool IsClosingPunctuation(char c)
            => c == '"' || c == '”' || c == '’' || c == ')' || c == ']' || c == '\''
               || c == '）' || c == '】' || c == '』' || c == '」' || c == '｣';

        private static bool IsOpeningPunctuation(char c)
            => c == '"' || c == '“' || c == '‘' || c == '\'' || c == '(' || c == '[' || c == '{'
               || c == '（' || c == '【' || c == '『' || c == '「' || c == '｢';

        // MARK: - 中文分句

        public static List<string> SplitChinese(string text)
        {
            ArgumentNullException.ThrowIfNull(text);

            var result = new List<string>();
            foreach (string rawLine in text.Split(LineSeparators))
            {
                string trimmed = rawLine.Trim(' ', '\t');
                if (trimmed.Length == 0) continue;
                result.AddRange(SplitChineseSentences(trimmed));
            }
            return result;
        }

        private static List<string> SplitChineseSentences(string text)
        {
            char[] chars = text.ToCharArray();
            var sentences = new List<string>();
            int start = 0;
            int i = 0;

            while (i < chars.Length)
            {
                char c = chars[i];
                if (c == '。' || c == '！' || c == '？' || c == '…')
                {
                    int j = i + 1;
                    while (j < chars.Length && chars[j] == '…') j++;
                    while (j < chars.Length && IsClosingPunctuation(chars[j])) j++;
                    AppendTrimmed(sentences, chars, start, j);
                    start = j; i = j; continue;
                }
                i++;
            }

            AppendTrimmed(sentences, chars, start, chars.Length);
            return sentences;
        }

        // MARK: - 配对

        public static List<SplitPair> Pair(string original, string translation)
        {
            ArgumentNullException.ThrowIfNull(original);
            ArgumentNullException.ThrowIfNull(translation);

            List<string> originals = SplitEnglish(original);
            List<string> translations = SplitChinese(translation);

            if (originals.Count == 0)
                return translations.Select(t => new SplitPair("", t)).ToList();
            if (translations.Count == 0)
                return originals.Select(o => new SplitPair(o, "")).ToList();

            if (originals.Count == translations.Count)
            {
                var pairs = new List<SplitPair>(originals.Count);
                for (int i = 0; i < originals.Count; i++)
                    pairs.Add(new SplitPair(originals[i], translations[i]));
                return pairs;
            }

            return originals.Count < translations.Count
                ? AlignConsumingTranslations(originals, translations)
                : AlignConsumingOriginals(originals, translations);
        }

        private static List<SplitPair> AlignConsumingTranslations(List<string> originals, List<string> translations)
        {
            double[] eLens = originals.Select(s => (double)s.Length).ToArray();
            double[] cLens = translations.Select(s => (double)s.Length).ToArray();
            double totalE = eLens.Sum();
            double totalC = cLens.Sum();
            double ratio = totalE > 0 ? totalC / totalE : 1.0;

            var pairs = new List<SplitPair>(originals.Count);
            int j = 0;
            for (int i = 0; i < originals.Count; i++)
            {
                int remainingEnglish = originals.Count - i - 1;
                int maxTake = translations.Count - j - remainingEnglish;
                double expected = eLens[i] * ratio;
                int take = 1;
                double acc = cLens[j];
                while (take < maxTake)
                {
                    double next = cLens[j + take];
                    if (Math.Abs(acc + next - expected) < Math.Abs(acc - expected))
                    {
                        acc += next;
                        take++;
                    }
                    else break;
                }
                if (remainingEnglish == 0) take = maxTake;
                string merged = string.Join("\n", translations.GetRange(j, take));
                pairs.Add(new SplitPair(originals[i], merged));
                j += take;
            }
            return pairs;
        }

        private static List<SplitPair> AlignConsumingOriginals(List<string> originals, List<string> translations)
        {
            double[] eLens = originals.Select(s => (double)s.Length).ToArray();
            double[] cLens = translations.Select(s => (double)s.Length).ToArray();
            double totalE = eLens.Sum();
            double totalC = cLens.Sum();
            double ratio = totalC > 0 ? totalC / totalE : 1.0;

            var pairs = new List<SplitPair>(translations.Count);
            int i = 0;
            for (int j = 0; j < translations.Count; j++)
            {
                int remainingChinese = translations.Count - j - 1;
                int maxTake = originals.Count - i - remainingChinese;
                double expected = cLens[j] / ratio;
                int take = 1;
                double acc = eLens[i];
                while (take < maxTake)
                {
                    double next = eLens[i + take];
                    if (Math.Abs(acc + next - expected) < Math.Abs(acc - expected))
                    {
                        acc += next;
                        take++;
                    }
                    else break;
                }
                if (remainingChinese == 0) take = maxTake;
                string merged = string.Join(" ", originals.GetRange(i, take));
                pairs.Add(new SplitPair(merged, translations[j]));
                i += take;
            }
            return pairs;
        }

        /// <summary>原文句数与译文句数是否一致。</summary>
        public static bool SentenceCountsMatch(string original, string translation)
        {
            ArgumentNullException.ThrowIfNull(original);
            ArgumentNullException.ThrowIfNull(translation);
            return SplitEnglish(original).Count == SplitChinese(translation).Count;
        }

        // MARK: - 内部工具

        private static void AppendTrimmed(List<string> sentences, char[] chars, int start, int end)
        {
            if (start < 0) start = 0;
            if (end > chars.Length) end = chars.Length;
            if (start >= end) return;
            string s = new string(chars, start, end - start).Trim(' ', '\t');
            if (s.Length > 0) sentences.Add(s);
        }
    }
}
