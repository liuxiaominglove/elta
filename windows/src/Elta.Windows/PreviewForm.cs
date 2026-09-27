using System;
using System.Drawing;
using System.Windows.Forms;

namespace Elta.Windows
{
    /// <summary>B1 结果预览：显示裁剪出的截图，并可复制到剪贴板。关闭时释放图像。</summary>
    internal sealed class PreviewForm : Form
    {
        private readonly Bitmap _image;

        public PreviewForm(Bitmap image)
        {
            _image = image;

            Text = $"截图结果 {image.Width}×{image.Height}";
            StartPosition = FormStartPosition.CenterScreen;
            AutoScaleMode = AutoScaleMode.None;
            AutoSize = true;
            AutoSizeMode = AutoSizeMode.GrowAndShrink;
            MaximizeBox = false;
            MinimizeBox = false;

            var picture = new PictureBox
            {
                Image = image,
                SizeMode = PictureBoxSizeMode.AutoSize,
                Dock = DockStyle.Top,
            };

            var copyButton = new Button
            {
                Text = "复制到剪贴板",
                Dock = DockStyle.Bottom,
                Height = 34,
            };
            copyButton.Click += (_, _) =>
            {
                Clipboard.SetImage(image);
                MessageBox.Show(this, "已复制到剪贴板", "ELTA", MessageBoxButtons.OK, MessageBoxIcon.Information);
            };

            Controls.Add(picture);
            Controls.Add(copyButton);
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            base.OnFormClosed(e);
            _image.Dispose();
        }
    }
}
