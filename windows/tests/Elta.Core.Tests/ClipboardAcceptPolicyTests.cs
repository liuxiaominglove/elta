using System.Collections.Generic;
using Elta.Core;
using Xunit;

namespace Elta.Core.Tests
{
    public class ClipboardAcceptPolicyTests
    {
        // MARK: - 接受剪贴板结果的判定（移植 mac getSelectedTextViaCopyPasteboard）

        [Fact]
        public void Accept_ByChangeCount_ChangedAndNonEmpty_IsTrue()
            => Assert.True(ClipboardAcceptPolicy.AcceptByChangeCount(changeCountChanged: true, newText: "copied"));

        [Fact]
        public void Accept_ByChangeCount_NotChanged_IsFalse()
            => Assert.False(ClipboardAcceptPolicy.AcceptByChangeCount(changeCountChanged: false, newText: "copied"));

        [Fact]
        public void Accept_ByChangeCount_EmptyText_IsFalse()
            => Assert.False(ClipboardAcceptPolicy.AcceptByChangeCount(changeCountChanged: true, newText: ""));

        [Fact]
        public void Accept_ByChangeCount_NullText_IsFalse()
            => Assert.False(ClipboardAcceptPolicy.AcceptByChangeCount(changeCountChanged: true, newText: null));

        [Fact]
        public void Accept_ByFallback_NewTextNotInOld_IsTrue()
            => Assert.True(ClipboardAcceptPolicy.AcceptByFallback("new", new[] { "old" }));

        [Fact]
        public void Accept_ByFallback_SameAsOld_IsFalse()
            => Assert.False(ClipboardAcceptPolicy.AcceptByFallback("old", new[] { "old" }));

        [Fact]
        public void Accept_ByFallback_EmptyText_IsFalse()
            => Assert.False(ClipboardAcceptPolicy.AcceptByFallback("", new[] { "old" }));

        [Fact]
        public void Accept_ByFallback_NullText_IsFalse()
            => Assert.False(ClipboardAcceptPolicy.AcceptByFallback(null, new[] { "old" }));

        [Fact]
        public void Accept_ByFallback_NoPreviousTexts_IsTrue()
            => Assert.True(ClipboardAcceptPolicy.AcceptByFallback("first", new string[0]));
    }
}
