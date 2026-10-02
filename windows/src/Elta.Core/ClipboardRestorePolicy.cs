using System;

namespace Elta.Core
{
    /// <summary>Ctrl+C 兜底取词后，对剪贴板的处置。</summary>
    public enum ClipboardRestoreAction
    {
        /// <summary>什么都不做（默认安全选择）。</summary>
        LeaveAsIs,

        /// <summary>写回快照（还原用户原有内容）。</summary>
        Restore,

        /// <summary>清空（仅在确认原本为空时，用于清除 Ctrl+C 残留）。</summary>
        Clear,
    }

    /// <summary>
    /// WI-1：兜底取词结束后如何处置剪贴板。核心安全原则——
    /// **无法确认原剪贴板内容时绝不清空**（宁可留下 Ctrl+C 的残留，也不丢用户数据）。
    ///
    /// 决策优先级：
    /// 1) 快照捕获失败 → 不动（无法还原，也不能清空）
    /// 2) 操作期间被第三方改写 → 不动（不覆盖别人的新内容）
    /// 3) 剪贴板序号未变（我们的 Ctrl+C 没生效）→ 不动
    /// 4) 原本为空 → 清空（去残留）；原本有内容 → 还原
    /// </summary>
    public static class ClipboardRestorePolicy
    {
        public static ClipboardRestoreAction Decide(
            bool captureSucceeded,
            int originalCount,
            bool clipboardChanged,
            bool changedByThirdParty)
        {
            if (originalCount < 0) throw new ArgumentOutOfRangeException(nameof(originalCount));

            if (!captureSucceeded) return ClipboardRestoreAction.LeaveAsIs;
            if (changedByThirdParty) return ClipboardRestoreAction.LeaveAsIs;
            if (!clipboardChanged) return ClipboardRestoreAction.LeaveAsIs;

            return originalCount == 0 ? ClipboardRestoreAction.Clear : ClipboardRestoreAction.Restore;
        }
    }
}
