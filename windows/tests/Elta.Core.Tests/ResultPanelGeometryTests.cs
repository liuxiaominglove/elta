using Elta.Core;
using Xunit;

namespace Elta.Core.Tests
{
    public class ResultPanelGeometryTests
    {
        private static readonly RectF Screen = new(0, 0, 1366, 768);

        // MARK: - 对侧半屏选择（对齐 mac computeFrame：avoidRect 在中线左侧 → 面板右半屏）

        [Fact]
        public void Compute_AvoidOnLeft_PutsPanelOnRightHalf()
        {
            RectF avoid = new(100, 100, 200, 100);
            RectF panel = ResultPanelGeometry.Compute(Screen, avoid, savedHeight: null, savedY: null);

            Assert.Equal(683, panel.X);
            Assert.Equal(683, panel.Width);
            Assert.Equal(768, panel.Height);
            Assert.Equal(0, panel.Y);
        }

        [Fact]
        public void Compute_AvoidOnRight_PutsPanelOnLeftHalf()
        {
            RectF avoid = new(900, 100, 200, 100);
            RectF panel = ResultPanelGeometry.Compute(Screen, avoid, savedHeight: null, savedY: null);

            Assert.Equal(0, panel.X);
            Assert.Equal(683, panel.Width);
        }

        // MARK: - 已保存高度 / 位置的回用与夹紧

        [Fact]
        public void Compute_ReusesSavedHeightAndY()
        {
            RectF avoid = new(900, 100, 200, 100);
            RectF panel = ResultPanelGeometry.Compute(Screen, avoid, savedHeight: 500, savedY: 120);

            Assert.Equal(500, panel.Height);
            Assert.Equal(120, panel.Y);
        }

        [Fact]
        public void Compute_ClampsSavedHeightToMinimum()
        {
            RectF avoid = new(900, 100, 200, 100);
            RectF panel = ResultPanelGeometry.Compute(Screen, avoid, savedHeight: 200, savedY: 0);

            Assert.Equal(ResultPanelGeometry.MinPanelHeight, panel.Height);
        }

        [Fact]
        public void Compute_ClampsSavedHeightToScreen()
        {
            RectF avoid = new(900, 100, 200, 100);
            RectF panel = ResultPanelGeometry.Compute(Screen, avoid, savedHeight: 900, savedY: 0);

            Assert.Equal(768, panel.Height);
        }

        [Fact]
        public void Compute_ClampsSavedYToBottomEdge()
        {
            RectF avoid = new(900, 100, 200, 100);
            RectF panel = ResultPanelGeometry.Compute(Screen, avoid, savedHeight: 500, savedY: 700);

            Assert.Equal(268, panel.Y);   // 768 - 500
        }

        // MARK: - 翻面（` 键）

        [Fact]
        public void ComputeForSide_Left_ReturnsLeftHalf()
        {
            RectF panel = ResultPanelGeometry.ComputeForSide(Screen, panelOnRight: false, savedHeight: null, savedY: null);

            Assert.Equal(0, panel.X);
            Assert.Equal(683, panel.Width);
        }

        [Fact]
        public void ComputeForSide_Right_ReturnsRightHalf()
        {
            RectF panel = ResultPanelGeometry.ComputeForSide(Screen, panelOnRight: true, savedHeight: null, savedY: null);

            Assert.Equal(683, panel.X);
        }

        [Fact]
        public void PanelOnRight_MidlineBoundary_IsRight()
        {
            // avoidRect.midX == midline → 不满足 <，落左半屏（与 mac avoidRect.midX < midline 语义一致）
            RectF avoid = new(583, 0, 200, 10);   // midX = 683
            Assert.False(ResultPanelGeometry.PanelOnRight(Screen, avoid));
        }
    }
}
