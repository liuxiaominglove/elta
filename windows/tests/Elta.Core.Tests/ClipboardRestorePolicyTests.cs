using System;
using Elta.Core;
using Xunit;

namespace Elta.Core.Tests
{
    /// <summary>
    /// WI-1：Ctrl+C 兜底取词结束后「恢复 / 清空 / 不动」的决策。
    /// 核心回归点：捕获失败时**绝不能清空**用户剪贴板。
    /// </summary>
    public class ClipboardRestorePolicyTests
    {
        private static ClipboardRestoreAction Decide(
            bool captureSucceeded, int originalCount, bool clipboardChanged, bool changedByThirdParty)
            => ClipboardRestorePolicy.Decide(captureSucceeded, originalCount, clipboardChanged, changedByThirdParty);

        // MARK: - 捕获失败：一律不动（数据安全优先）

        [Fact]
        public void CaptureFailed_Empty_NotChanged_LeavesAsIs()
            => Assert.Equal(ClipboardRestoreAction.LeaveAsIs, Decide(false, 0, false, false));

        [Fact]
        public void CaptureFailed_Empty_Changed_LeavesAsIs()
            => Assert.Equal(ClipboardRestoreAction.LeaveAsIs, Decide(false, 0, true, false));

        [Fact]
        public void CaptureFailed_NonEmpty_Changed_LeavesAsIs()
            => Assert.Equal(ClipboardRestoreAction.LeaveAsIs, Decide(false, 3, true, false));

        // MARK: - 第三方改写：一律不动（不覆盖别人的新内容）

        [Fact]
        public void ThirdPartyChanged_NonEmpty_LeavesAsIs()
            => Assert.Equal(ClipboardRestoreAction.LeaveAsIs, Decide(true, 3, true, true));

        [Fact]
        public void ThirdPartyChanged_Empty_LeavesAsIs()
            => Assert.Equal(ClipboardRestoreAction.LeaveAsIs, Decide(true, 0, true, true));

        [Fact]
        public void ThirdPartyChanged_NotChanged_LeavesAsIs()
            => Assert.Equal(ClipboardRestoreAction.LeaveAsIs, Decide(true, 3, false, true));

        // MARK: - 我们没改过剪贴板：不动

        [Fact]
        public void CaptureOk_NonEmpty_NotChanged_LeavesAsIs()
            => Assert.Equal(ClipboardRestoreAction.LeaveAsIs, Decide(true, 2, false, false));

        [Fact]
        public void CaptureOk_Empty_NotChanged_LeavesAsIs()
            => Assert.Equal(ClipboardRestoreAction.LeaveAsIs, Decide(true, 0, false, false));

        // MARK: - 正常路径

        [Fact]
        public void CaptureOk_Empty_Changed_ClearsResidue()
            => Assert.Equal(ClipboardRestoreAction.Clear, Decide(true, 0, true, false));

        [Fact]
        public void CaptureOk_NonEmpty_Changed_RestoresOriginal()
            => Assert.Equal(ClipboardRestoreAction.Restore, Decide(true, 1, true, false));

        [Fact]
        public void CaptureOk_ManyFormats_Changed_RestoresOriginal()
            => Assert.Equal(ClipboardRestoreAction.Restore, Decide(true, 12, true, false));

        // MARK: - 非法输入

        [Fact]
        public void NegativeOriginalCount_Throws()
            => Assert.Throws<ArgumentOutOfRangeException>(() => Decide(true, -1, true, false));
    }
}
