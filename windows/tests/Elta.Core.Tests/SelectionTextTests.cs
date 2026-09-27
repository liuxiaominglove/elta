using Elta.Core;
using Xunit;

namespace Elta.Core.Tests
{
    public class SelectionTextTests
    {
        // MARK: - SubstringInRange（移植 mac TranslationPipeline.substringInRange）

        [Fact]
        public void Substring_ValidRange_ReturnsSubstring()
            => Assert.Equal("hello", SelectionText.SubstringInRange("hello world", 0, 5));

        [Fact]
        public void Substring_MidStringRange()
            => Assert.Equal("world", SelectionText.SubstringInRange("hello world", 6, 5));

        [Fact]
        public void Substring_FullStringRange()
            => Assert.Equal("abc", SelectionText.SubstringInRange("abc", 0, 3));

        [Fact]
        public void Substring_ZeroLength_ReturnsNull()
            => Assert.Null(SelectionText.SubstringInRange("hello", 2, 0));

        [Fact]
        public void Substring_LengthOverflow_ReturnsNull()
            => Assert.Null(SelectionText.SubstringInRange("abc", 1, 10));

        [Fact]
        public void Substring_LocationOverflow_ReturnsNull()
            => Assert.Null(SelectionText.SubstringInRange("abc", 5, 1));

        [Fact]
        public void Substring_NegativeLocation_ReturnsNull()
            => Assert.Null(SelectionText.SubstringInRange("abc", -1, 1));

        [Fact]
        public void Substring_EmptyString_ReturnsNull()
            => Assert.Null(SelectionText.SubstringInRange("", 0, 0));

        [Fact]
        public void Substring_UsesUtf16Offsets_EmojiSurrogatePair()
        {
            // "a😀b": UTF-16 单元 [a][😀高][😀低][b] = 4；range(1,2) → "😀"
            Assert.Equal("😀", SelectionText.SubstringInRange("a😀b", 1, 2));
        }

        [Fact]
        public void Substring_BoundsUseUtf16Length_NotGraphemeCount()
        {
            // "😀a": UTF-16 长度 3（😀=2 + a=1），字素 2；range(2,1) → "a"
            Assert.Equal("a", SelectionText.SubstringInRange("😀a", 2, 1));
        }

        // MARK: - IsUsable（mac：非 nil 且非空即视为可用；空白串也算可用）

        [Fact]
        public void IsUsable_Null_IsFalse()
            => Assert.False(SelectionText.IsUsable(null));

        [Fact]
        public void IsUsable_Empty_IsFalse()
            => Assert.False(SelectionText.IsUsable(""));

        [Fact]
        public void IsUsable_Text_IsTrue()
            => Assert.True(SelectionText.IsUsable("hello"));

        [Fact]
        public void IsUsable_WhitespaceOnly_IsTrue_ParityWithMac()
            => Assert.True(SelectionText.IsUsable(" "));
    }
}
