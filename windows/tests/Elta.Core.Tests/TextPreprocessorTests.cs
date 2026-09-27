using System;
using Xunit;

namespace Elta.Core.Tests
{
    public class TextPreprocessorTests
    {
        [Fact]
        public void FourLineCitation_CondensedWithAuthor()
            => Assert.Equal("摘录来自《书名》作者",
                TextPreprocessor.CondenseCitation("摘录来自\n书名\n作者\n此材料受版权保护。"));

        [Fact]
        public void ThreeLineCitation_CondensedWithoutAuthor()
            => Assert.Equal("摘录来自《书名》",
                TextPreprocessor.CondenseCitation("摘录来自\n书名\n此材料受版权保护。"));

        [Fact]
        public void NoCitation_Unchanged()
            => Assert.Equal("hello world", TextPreprocessor.CondenseCitation("hello world"));

        [Fact]
        public void Empty_ReturnsEmpty()
            => Assert.Equal("", TextPreprocessor.CondenseCitation(""));

        [Fact]
        public void Null_Throws()
            => Assert.Throws<ArgumentNullException>(() => TextPreprocessor.CondenseCitation(null!));
    }
}
