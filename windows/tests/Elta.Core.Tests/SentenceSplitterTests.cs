using System;
using System.Collections.Generic;
using System.Linq;
using Xunit;

namespace Elta.Core.Tests
{
    public class SentenceSplitterTests
    {
        // ---------- 英文分句 ----------

        [Fact]
        public void SplitEnglish_PlainSentences()
            => Assert.Equal(new[] { "Hello world.", "This is a test.", "Goodbye." },
                SentenceSplitter.SplitEnglish("Hello world. This is a test. Goodbye."));

        [Fact]
        public void SplitEnglish_QuestionAndExclamation()
            => Assert.Equal(new[] { "What is this?", "Really!", "Let's go." },
                SentenceSplitter.SplitEnglish("What is this? Really! Let's go."));

        [Fact]
        public void SplitEnglish_DoesNotSplitAfterDr()
            => Assert.Equal(new[] { "Dr. Smith went home.", "He was tired." },
                SentenceSplitter.SplitEnglish("Dr. Smith went home. He was tired."));

        [Fact]
        public void SplitEnglish_DoesNotSplitAfterEg()
            => Assert.Equal(new[] { "Some fruits, e.g. apples, are sweet.", "That's all." },
                SentenceSplitter.SplitEnglish("Some fruits, e.g. apples, are sweet. That's all."));

        [Fact]
        public void SplitEnglish_AcrossParagraphs()
            => Assert.Equal(new[] { "First line.", "Second paragraph here." },
                SentenceSplitter.SplitEnglish("First line.\n\nSecond paragraph here."));

        [Fact]
        public void SplitEnglish_Empty()
            => Assert.Empty(SentenceSplitter.SplitEnglish(""));

        [Fact]
        public void SplitEnglish_SingleNoTerminator()
            => Assert.Equal(new[] { "no punctuation at all" },
                SentenceSplitter.SplitEnglish("no punctuation at all"));

        // ---------- 中文分句 ----------

        [Fact]
        public void SplitChinese_Basic()
            => Assert.Equal(new[] { "这是第一句。", "这是第二句！", "这是第三句？", "这是第四句；" },
                SentenceSplitter.SplitChinese("这是第一句。这是第二句！这是第三句？这是第四句；"));

        [Fact]
        public void SplitChinese_QuoteSemicolon()
            => Assert.Equal(new[] { "他断言“食物中可找到良药；食物中也可找到劣药”，这一观点仍成立。" },
                SentenceSplitter.SplitChinese("他断言“食物中可找到良药；食物中也可找到劣药”，这一观点仍成立。"));

        [Fact]
        public void SplitChinese_ListSemicolon()
            => Assert.Equal(new[] { "甲；乙；丙。" },
                SentenceSplitter.SplitChinese("甲；乙；丙。"));

        [Fact]
        public void SplitChinese_TrailingPunctuation()
            => Assert.Equal(new[] { "你好。" }, SentenceSplitter.SplitChinese("你好。"));

        [Fact]
        public void SplitChinese_AcrossLines()
            => Assert.Equal(new[] { "第一行。", "第二行。" }, SentenceSplitter.SplitChinese("第一行。\n第二行。"));

        [Fact]
        public void SplitChinese_Empty()
            => Assert.Empty(SentenceSplitter.SplitChinese(""));

        [Fact]
        public void SplitChinese_NoPunctuation()
            => Assert.Equal(new[] { "没有标点" }, SentenceSplitter.SplitChinese("没有标点"));

        // ---------- 配对 ----------

        [Fact]
        public void Pair_EqualCounts()
        {
            var pairs = SentenceSplitter.Pair("Hello. World.", "你好。世界。");
            Assert.Equal(2, pairs.Count);
            Assert.Equal("Hello.", pairs[0].Original);
            Assert.Equal("你好。", pairs[0].Translation);
            Assert.Equal("World.", pairs[1].Original);
            Assert.Equal("世界。", pairs[1].Translation);
        }

        [Fact]
        public void Pair_MergeEnglishIntoFewerTranslations()
        {
            var pairs = SentenceSplitter.Pair("One. Two. Three.", "第一句。");
            Assert.Single(pairs);
            Assert.Equal("One. Two. Three.", pairs[0].Original);
            Assert.Equal("第一句。", pairs[0].Translation);
        }

        [Fact]
        public void Pair_MergeChineseIntoFewerOriginals()
        {
            var pairs = SentenceSplitter.Pair("One.", "第一句。第二句。");
            Assert.Single(pairs);
            Assert.Equal("One.", pairs[0].Original);
            Assert.Equal("第一句。\n第二句。", pairs[0].Translation);
        }

        [Fact]
        public void Pair_OneToTwoLong()
        {
            var pairs = SentenceSplitter.Pair(
                "Consider the case of poor Ignaz Semmelweis, a Viennese obstetrician who was troubled by the fact that so many new mothers were dying in the hospital where he worked. He concluded that their strange “childbed fever” might somehow be linked to the autopsies that he and his colleagues performed in the mornings, before delivering babies in the afternoons—without washing their hands in between. The existence of germs had not yet been discovered, but Semmelweis nonetheless believed that the doctors were transmitting something to these women that caused their illness. His observations were most unwelcome. His colleagues ostracized him, and Semmelweis died in an insane asylum in 1865.",
                "想想可怜的伊格纳兹·塞麦尔维斯吧。这位维也纳产科医生深感困扰，因为在他工作的医院里，有太多新妈妈相继离世。他得出结论，她们所患的诡异“产褥热”或许与他及同事们上午进行尸检、下午接生婴儿——期间从不洗手——之间存在某种关联。当时细菌尚未被发现，但塞麦尔维斯仍然坚信，是医生们将某种致病之物传给了这些女性。他的观察结果极不受欢迎。同事们将他排挤在外，而塞麦尔维斯最终于1865年死于精神病院。");
            Assert.Equal(5, pairs.Count);
            Assert.Equal("想想可怜的伊格纳兹·塞麦尔维斯吧。\n这位维也纳产科医生深感困扰，因为在他工作的医院里，有太多新妈妈相继离世。", pairs[0].Translation);
            Assert.Equal("他得出结论，她们所患的诡异“产褥热”或许与他及同事们上午进行尸检、下午接生婴儿——期间从不洗手——之间存在某种关联。", pairs[1].Translation);
            Assert.Equal("当时细菌尚未被发现，但塞麦尔维斯仍然坚信，是医生们将某种致病之物传给了这些女性。", pairs[2].Translation);
            Assert.Equal("他的观察结果极不受欢迎。", pairs[3].Translation);
            Assert.Equal("同事们将他排挤在外，而塞麦尔维斯最终于1865年死于精神病院。", pairs[4].Translation);
        }

        [Fact]
        public void Pair_TwoToOne()
        {
            var pairs = SentenceSplitter.Pair("One. Two.", "一和二。");
            Assert.Single(pairs);
            Assert.Equal("One. Two.", pairs[0].Original);
            Assert.Equal("一和二。", pairs[0].Translation);
        }

        [Fact]
        public void Pair_DoesNotDropTrailingChinese()
        {
            var pairs = SentenceSplitter.Pair("Hi. Bye.", "甲。你好你好你好。乙。");
            Assert.Equal(2, pairs.Count);
            Assert.Equal("甲。", pairs[0].Translation);
            Assert.Contains("乙。", pairs[1].Translation);
        }

        [Fact]
        public void Pair_DoesNotDropTrailingEnglish()
        {
            var pairs = SentenceSplitter.Pair("Hi. Bye bye bye. End.", "甲。乙。");
            Assert.Equal(2, pairs.Count);
            Assert.Contains("End.", pairs[1].Original);
        }

        [Fact]
        public void Pair_OriginalOnly()
        {
            var pairs = SentenceSplitter.Pair("One. Two.", "");
            Assert.Equal(2, pairs.Count);
            Assert.Equal("One.", pairs[0].Original);
            Assert.Equal("", pairs[0].Translation);
            Assert.Equal("Two.", pairs[1].Original);
        }

        [Fact]
        public void Pair_TranslationOnly()
        {
            var pairs = SentenceSplitter.Pair("", "第一句。第二句。");
            Assert.Equal(2, pairs.Count);
            Assert.Equal("", pairs[0].Original);
            Assert.Equal("第一句。", pairs[0].Translation);
            Assert.Equal("第二句。", pairs[1].Translation);
        }

        [Fact]
        public void Pair_BothEmpty()
            => Assert.Empty(SentenceSplitter.Pair("", ""));

        // ---------- 英文边界 ----------

        [Fact]
        public void SplitEnglish_EtAl_Paren()
            => Assert.Equal(new[] { "Smith et al. (2020) found it." },
                SentenceSplitter.SplitEnglish("Smith et al. (2020) found it."));

        [Fact]
        public void SplitEnglish_EtAl_Year()
            => Assert.Equal(new[] { "Smith et al. 2020 found it." },
                SentenceSplitter.SplitEnglish("Smith et al. 2020 found it."));

        [Fact]
        public void SplitEnglish_EtAl_Uppercase()
            => Assert.Equal(new[] { "Johnson et al. Nature published it." },
                SentenceSplitter.SplitEnglish("Johnson et al. Nature published it."));

        [Fact]
        public void SplitEnglish_Initials()
            => Assert.Equal(new[] { "J. K. Rowling wrote it." },
                SentenceSplitter.SplitEnglish("J. K. Rowling wrote it."));

        [Fact]
        public void SplitEnglish_AM()
            => Assert.Equal(new[] { "The train leaves at 8 a.m. Passengers should board early." },
                SentenceSplitter.SplitEnglish("The train leaves at 8 a.m. Passengers should board early."));

        [Fact]
        public void SplitEnglish_PM()
            => Assert.Equal(new[] { "Meeting ends at 6 p.m. Dinner follows." },
                SentenceSplitter.SplitEnglish("Meeting ends at 6 p.m. Dinner follows."));

        [Fact]
        public void SplitEnglish_QuotedStop()
            => Assert.Equal(new[] { "He said \"Stop.\" and left." },
                SentenceSplitter.SplitEnglish("He said \"Stop.\" and left."));

        [Fact]
        public void SplitEnglish_Decimal()
            => Assert.Equal(new[] { "Version 1.2 is released." },
                SentenceSplitter.SplitEnglish("Version 1.2 is released."));

        [Fact]
        public void SplitEnglish_URL()
            => Assert.Equal(new[] { "Visit example.com and read more." },
                SentenceSplitter.SplitEnglish("Visit example.com and read more."));

        [Fact]
        public void SplitEnglish_LongNoPunctuation()
            => Assert.Single(SentenceSplitter.SplitEnglish(new string('x', 5000)));

        // ---------- 中文边界 ----------

        [Fact]
        public void SplitChinese_Ellipsis()
            => Assert.Equal(new[] { "他走了……", "真的走了。" },
                SentenceSplitter.SplitChinese("他走了……真的走了。"));

        [Fact]
        public void SplitChinese_EllipsisClosingBracket()
            => Assert.Equal(new[] { "（内容省略……）", "然后继续。" },
                SentenceSplitter.SplitChinese("（内容省略……）然后继续。"));

        [Fact]
        public void SplitChinese_LoneEllipsis()
            => Assert.Equal(new[] { "……" }, SentenceSplitter.SplitChinese("……"));

        [Fact]
        public void SplitChinese_ClosingQuote()
            => Assert.Equal(new[] { "他说“你好。”", "然后走了。" },
                SentenceSplitter.SplitChinese("他说“你好。”然后走了。"));

        // ---------- 句数一致性 ----------

        [Fact]
        public void SentenceCountsMatch_True()
            => Assert.True(SentenceSplitter.SentenceCountsMatch("One. Two.", "第一句。第二句。"));

        [Fact]
        public void SentenceCountsMatch_False()
            => Assert.False(SentenceSplitter.SentenceCountsMatch("One. Two.", "第一句。第二句。第三句。"));

        [Fact]
        public void SentenceCountsMatch_Empty()
            => Assert.True(SentenceSplitter.SentenceCountsMatch("", ""));

        // ---------- 摘录来自 引用块 ----------

        [Fact]
        public void SplitEnglish_CitationDoubleNewline()
            => Assert.Equal(new[] { "Hello world." },
                SentenceSplitter.SplitEnglish("Hello world.\n\n摘录来自《Outlive》Peter Attia, MD"));

        [Fact]
        public void SplitEnglish_CitationSingleNewline()
            => Assert.Equal(new[] { "Hello world." },
                SentenceSplitter.SplitEnglish("Hello world.\n摘录来自《Outlive》Peter Attia, MD"));

        [Fact]
        public void SplitEnglish_CitationOnly()
            => Assert.Empty(SentenceSplitter.SplitEnglish("摘录来自《Outlive》Peter Attia, MD"));

        [Fact]
        public void SplitEnglish_BareCitationKept()
            => Assert.Equal(new[] { "This mentions 摘录来自 word." },
                SentenceSplitter.SplitEnglish("This mentions 摘录来自 word."));

        [Fact]
        public void Pair_AfterCitationRemoval()
        {
            var pairs = SentenceSplitter.Pair("One. Two.\n\n摘录来自《X》Y", "第一。第二。");
            Assert.Equal(2, pairs.Count);
            Assert.Equal("One.", pairs[0].Original);
            Assert.Equal("第一。", pairs[0].Translation);
            Assert.Equal("Two.", pairs[1].Original);
            Assert.Equal("第二。", pairs[1].Translation);
        }

        // ---------- 左引号起始 ----------

        [Fact]
        public void SplitEnglish_SplitsQuotedCurly()
            => Assert.Equal(new[]
            {
                "But instead he picked me.",
                "“Based on your previous career choice,” he said, “I suspect you are better prepared to deliver truly horrible news to people.”"
            },
                SentenceSplitter.SplitEnglish("But instead he picked me. “Based on your previous career choice,” he said, “I suspect you are better prepared to deliver truly horrible news to people.”"));

        [Fact]
        public void SplitEnglish_SplitsBetweenQuotedStraight()
            => Assert.Equal(new[] { "He said \"Stop.\"", "\"Go now.\"" },
                SentenceSplitter.SplitEnglish("He said \"Stop.\" \"Go now.\""));

        [Fact]
        public void SplitEnglish_NoSplitOpeningQuoteLowercase()
            => Assert.Equal(new[] { "He said \"hello.\" \"world.\"" },
                SentenceSplitter.SplitEnglish("He said \"hello.\" \"world.\""));

        // ---------- 空值边界 ----------

        [Fact]
        public void SplitEnglish_Null_Throws()
            => Assert.Throws<ArgumentNullException>(() => SentenceSplitter.SplitEnglish(null!));

        [Fact]
        public void SplitChinese_Null_Throws()
            => Assert.Throws<ArgumentNullException>(() => SentenceSplitter.SplitChinese(null!));

        [Fact]
        public void Pair_Null_Throws()
            => Assert.Throws<ArgumentNullException>(() => SentenceSplitter.Pair(null!, "x"));
    }
}
