using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using Elta.Core;

namespace Elta.Windows
{
    /// <summary>
    /// 全屏选区覆盖层（B1）。冻结整个虚拟桌面截图作背景，拖拽框选，返回物理像素选区。
    /// 覆盖层横跨所有显示器（Bounds = 虚拟桌面），因此在主屏触发后仍可把鼠标移到副屏框选。
    /// 用 WinForms <see cref="Form"/> 而非 WPF Window：Form 的 Bounds 直接是物理像素，
    /// 与 GDI 截图/选区坐标同一坐标系，规避多屏 DIP 换算错位（P0.5 已暴露该坑）。
    /// 取消方式：ESC 或右键。
    /// </summary>
    internal sealed class ScreenshotSelector : Form
    {
        private readonly Bitmap _background;
        private Point _start;
        private RectF _current;
        private bool _dragging;
        private bool _hasSelection;

        /// <summary>选区（客户端坐标 = 物理像素）；取消时为 null。</summary>
        public RectF? Selection { get; private set; }

        public ScreenshotSelector(Bitmap background, Rectangle virtualBounds)
        {
            _background = background;

            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.Manual;
            Bounds = virtualBounds;         // 整个虚拟桌面（物理像素，可为负原点）
            TopMost = true;
            ShowInTaskbar = false;
            KeyPreview = true;
            DoubleBuffered = true;
            AutoScaleMode = AutoScaleMode.None;   // 固定像素坐标，禁止 WinForms 按 DPI 缩放
            Cursor = Cursors.Cross;
            BackColor = Color.Black;
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            Activate();
            Focus();
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Right)
            {
                Cancel();
                return;
            }
            if (e.Button != MouseButtons.Left) return;

            _dragging = true;
            _hasSelection = false;
            _start = e.Location;
            _current = new RectF(e.X, e.Y, 0, 0);
            Invalidate();
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            if (!_dragging) return;
            _current = ScreenshotGeometry.NormalizeSelection(_start.X, _start.Y, e.X, e.Y);
            Invalidate();
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) return;   // 只吃「发起拖拽的左键」抬起
            if (!_dragging) return;
            _dragging = false;
            _current = ScreenshotGeometry.NormalizeSelection(_start.X, _start.Y, e.X, e.Y);

            if (!ScreenshotGeometry.IsSelectionUsable(_current))
            {
                // 单击/微拖：不判为取消（取消=ESC/右键），重置拖拽态，保持覆盖层可重画
                _dragging = false;
                _current = new RectF(0, 0, 0, 0);
                Invalidate();
                return;
            }

            _hasSelection = true;
            Selection = _current;
            Close();
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Escape)
            {
                Cancel();
                return;
            }
            base.OnKeyDown(e);
        }

        private void Cancel()
        {
            Selection = null;
            Close();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.DrawImageUnscaled(_background, 0, 0);

            // 15% 变暗提示截图模式
            using (var dim = new SolidBrush(Color.FromArgb(38, 0, 0, 0)))
            {
                g.FillRectangle(dim, ClientRectangle);
            }

            if (_dragging || _hasSelection)
            {
                Rectangle r = ToRectangle(_current);

                // 挖空选区：重画背景
                GraphicsState state = g.Save();
                g.SetClip(r);
                g.DrawImageUnscaled(_background, 0, 0);
                g.Restore(state);

                using var pen = new Pen(Color.FromArgb(0, 120, 215), 2f);
                g.DrawRectangle(pen, r);

                string text = $"{r.Width} × {r.Height}";
                using var font = new Font("Consolas", 11f, FontStyle.Bold);
                SizeF sz = g.MeasureString(text, font);
                float labelX = Math.Max(r.Right - sz.Width - 8, 4);
                float labelY = Math.Max(r.Top - sz.Height - 6, 4);
                using var labelBg = new SolidBrush(Color.FromArgb(217, 0, 120, 215));
                g.FillRectangle(labelBg, labelX - 6, labelY - 3, sz.Width + 12, sz.Height + 6);
                g.DrawString(text, font, Brushes.White, labelX, labelY);
            }
        }

        private static Rectangle ToRectangle(RectF r)
            => new Rectangle(
                (int)Math.Round(r.X, MidpointRounding.AwayFromZero),
                (int)Math.Round(r.Y, MidpointRounding.AwayFromZero),
                (int)Math.Round(r.Width, MidpointRounding.AwayFromZero),
                (int)Math.Round(r.Height, MidpointRounding.AwayFromZero));
    }
}
