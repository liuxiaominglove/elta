using System;
using Xunit;

namespace Elta.Core.Tests
{
    public class TextNormalizerTests
    {
        [Fact]
        public void SingleLineBreak_BecomesSpace()
            => Assert.Equal("a b", TextNormalizer.NormalizeLineBreaks("a\nb"));

        [Fact]
        public void ParagraphBreak_Preserved()
            => Assert.Equal("a\n\nb", TextNormalizer.NormalizeLineBreaks("a\n\nb"));

        [Fact]
        public void Empty_ReturnsEmpty()
            => Assert.Equal("", TextNormalizer.NormalizeLineBreaks(""));

        [Fact]
        public void Null_Throws()
            => Assert.Throws<ArgumentNullException>(() => TextNormalizer.NormalizeLineBreaks(null!));

        [Fact]
        public void AllWhitespace_ReturnsEmpty()
            => Assert.Equal("", TextNormalizer.NormalizeLineBreaks("   \n\t"));

        [Fact]
        public void NewlineIndent_BecomesParagraphBreak()
            => Assert.Equal("a\n\nb", TextNormalizer.NormalizeLineBreaks("a\n    b"));

        [Fact]
        public void TrimsAndDropsEmptyParagraphs()
            => Assert.Equal("a\n\nb", TextNormalizer.NormalizeLineBreaks("\n\na\n\n\n\nb\n\n"));
    }
}
