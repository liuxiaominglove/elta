using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using Elta.Core;
using Forms = System.Windows.Forms;

namespace Elta.Windows
{
    /// <summary>
    /// ELTA Windows 外壳入口：托盘常驻程序。
    /// 截图选区 = Ctrl+T；划词翻译 = Ctrl+Shift+T。
    /// C0 托盘骨架；B1 截图；B2 取词（UIA → Ctrl+C 兜底）。
    /// </summary>
    public static class Program
    {
        private const uint MOD_CONTROL = 0x0002;
        private const uint MOD_SHIFT = 0x0004;
        private const uint VK_T = 0x54;
        private const int ID_SCREENSHOT = 0x4A17;
        private const int ID_SELECTION = 0x4A18;

        [STAThread]
        public static void Main(string[] args)
        {
            // 无头诊断：--ocr <图片路径> 直接跑 OCR（不启动托盘），供自动化验证
            if (args.Length >= 2 && args[0] == "--ocr")
            {
                RunOcrCli(args[1]);
                return;
            }

            // 无头诊断：--selection-cli <输出文件> 直接跑 Ctrl+C 兜底取词（不启动托盘）
            if (args.Length >= 2 && args[0] == "--selection-cli")
            {
                RunSelectionCli(args[1]);
                return;
            }

            // 无头诊断：--selftest 跑剪贴板策略集成自检（不启动托盘、不依赖外部程序）
            if (args.Length >= 1 && args[0] == "--selftest")
            {
                RunSelfTest();
                return;
            }

            // 单实例守卫：第二个实例会静默抢不到全局热键（RegisterHotKey 失败），
            // 提示后退出，避免出现「进程在跑但热键失效」的僵尸实例。
            using var singleInstance = new Mutex(
                initiallyOwned: true, name: @"Local\Elta.Windows.SingleInstance", out bool isFirstInstance);
            if (!isFirstInstance)
            {
                Forms.MessageBox.Show(
                    "ELTA 已在运行（见系统托盘图标）。",
                    "ELTA",
                    Forms.MessageBoxButtons.OK, Forms.MessageBoxIcon.Information);
                return;
            }

            var app = new System.Windows.Application
            {
                ShutdownMode = ShutdownMode.OnExplicitShutdown,
            };

            // WI-2：全局异常兜底——记录日志并保住进程，避免「无痕崩溃」
            app.DispatcherUnhandledException += (_, e) =>
            {
                Log.Error("DispatcherUnhandledException", e.Exception);
                try
                {
                    Forms.MessageBox.Show(
                        $"发生未处理错误（已记入日志）：\n{e.Exception.Message}\n\n日志目录：{Log.DirectoryPath}",
                        "ELTA", Forms.MessageBoxButtons.OK, Forms.MessageBoxIcon.Error);
                }
                catch { }
                e.Handled = true;
            };
            AppDomain.CurrentDomain.UnhandledException += (_, e) =>
                Log.Error("AppDomain.UnhandledException", e.ExceptionObject as Exception);
            TaskScheduler.UnobservedTaskException += (_, e) =>
            {
                Log.Error("UnobservedTaskException", e.Exception);
                e.SetObserved();
            };

            var menu = new Forms.ContextMenuStrip();

            var shotItem = new Forms.ToolStripMenuItem("截图选区（Ctrl+T）");
            shotItem.Click += (_, _) => RunScreenshot();
            menu.Items.Add(shotItem);

            var selectItem = new Forms.ToolStripMenuItem("划词翻译（Ctrl+Shift+T）");
            selectItem.Click += (_, _) => RunSelection();
            menu.Items.Add(selectItem);

            menu.Items.Add(new Forms.ToolStripSeparator());
            var exitItem = new Forms.ToolStripMenuItem("退出 ELTA");
            exitItem.Click += (_, _) => app.Shutdown();
            menu.Items.Add(exitItem);

            var tray = new Forms.NotifyIcon
            {
                Icon = SystemIcons.Application,
                Text = "ELTA — 截图即译，精读利器",
                Visible = true,
                ContextMenuStrip = menu,
            };

            var hotkey = new HotkeyHost();
            bool shotKey = hotkey.Register(ID_SCREENSHOT, MOD_CONTROL, VK_T,
                () => app.Dispatcher.BeginInvoke((Action)RunScreenshot));
            bool selectKey = hotkey.Register(ID_SELECTION, MOD_CONTROL | MOD_SHIFT, VK_T,
                () => app.Dispatcher.BeginInvoke((Action)RunSelection));

            Log.Info($"start version={typeof(Program).Assembly.GetName().Version} " +
                     $"shotKey={shotKey} selectKey={selectKey} logDir={Log.DirectoryPath}");

            tray.ShowBalloonTip(3500, "ELTA",
                $"Ctrl+T 截图；Ctrl+Shift+T 划词{(shotKey && selectKey ? "" : "（部分热键被占用，可用托盘菜单）")}",
                Forms.ToolTipIcon.Info);

            app.Exit += (_, _) =>
            {
                Log.Info("exit");
                hotkey.Dispose();
                tray.Visible = false;
                tray.Dispose();
                menu.Dispose();
            };

            app.Run();
        }

        [DllImport("kernel32.dll")]
        private static extern bool AttachConsole(int dwProcessId);

        /// <summary>
        /// 无头诊断：`Elta.Windows.exe --ocr &lt;图片路径&gt;` 直接跑 <see cref="OcrService"/>（不启动托盘），
        /// 把状态/文本/块坐标写到 `&lt;图片&gt;.ocr.txt`（并尝试附加到父控制台），供自动化验证 B3 代码路径。
        /// </summary>
        private static void RunOcrCli(string imagePath)
        {
            string report;
            try
            {
                using var bitmap = new Bitmap(imagePath);
                OcrOutcome outcome = OcrService.RecognizeAsync(bitmap).GetAwaiter().GetResult();
                Log.Info($"ocr-cli status={outcome.Status} blocks={outcome.Blocks.Count} size={bitmap.Width}x{bitmap.Height}");

                var sb = new StringBuilder();
                sb.AppendLine($"image={imagePath}");
                sb.AppendLine($"size={bitmap.Width}x{bitmap.Height}");
                sb.AppendLine($"status={outcome.Status}");
                sb.AppendLine($"blocks={outcome.Blocks.Count}");
                if (outcome.Error is not null) sb.AppendLine($"error={outcome.Error}");
                if (outcome.Status == OcrStatus.Ok && outcome.Blocks.Count > 0)
                {
                    string text = TextPreprocessor.CondenseCitation(TableExtractor.Process(outcome.Blocks));
                    sb.AppendLine("---- text ----");
                    sb.AppendLine(text);
                    sb.AppendLine("---- blocks ----");
                    foreach (OcrBlock b in outcome.Blocks)
                        sb.AppendLine($"{b.Text} @({b.BoundingBox.X:0},{b.BoundingBox.Y:0},{b.BoundingBox.Width:0},{b.BoundingBox.Height:0})");
                }
                report = sb.ToString();
            }
            catch (Exception ex)
            {
                report = "EXCEPTION: " + ex;
            }

            try { File.WriteAllText(imagePath + ".ocr.txt", report, new UTF8Encoding(false)); } catch { }
            try
            {
                AttachConsole(-1);
                Console.WriteLine(report);
                Console.Out.Flush();
            }
            catch { }
        }

        /// <summary>
        /// 无头诊断：`--selection-cli &lt;输出文件&gt;` 直接调用 Ctrl+C 兜底取词（绕过 UIA），
        /// 把结果写文件并尝试附加父控制台。供脚本驱动（如记事本全选后运行）做端到端验证。
        /// </summary>
        private static void RunSelectionCli(string outPath)
        {
            string report;
            try
            {
                Thread.Sleep(500);   // 给前台/选区稳定时间
                string? text = SelectionReader.TryCopyFallback();
                report = text is null ? "selected=null" : $"selected=len={text.Length}{Environment.NewLine}{text}";
                Log.Info($"selection-cli len={text?.Length ?? 0}");
            }
            catch (Exception ex)
            {
                report = "EXCEPTION: " + ex;
                Log.Error("selection-cli failed", ex);
            }

            try { File.WriteAllText(outPath, report, new UTF8Encoding(false)); } catch { }
            try
            {
                AttachConsole(-1);
                Console.WriteLine(report);
                Console.Out.Flush();
            }
            catch { }
        }

        /// <summary>
        /// 无头诊断：`--selftest` 剪贴板策略集成自检。覆盖 WI-1 的关键回归：
        /// 文本还原 / 图片还原 / 捕获失败不清空 / 原本为空去残留 / 第三方改写不动。
        /// 会短暂借用剪贴板，结束后尽力还原原内容。结果写 `%TEMP%\elta-selftest.txt`。
        /// </summary>
        private static void RunSelfTest()
        {
            var sb = new StringBuilder();
            int pass = 0, fail = 0;
            void Check(string name, bool ok)
            {
                sb.AppendLine($"[{(ok ? "PASS" : "FAIL")}] {name}");
                if (ok) pass++; else fail++;
            }

            ClipboardState backup = ClipboardState.Capture();
            try
            {
                // 1) 文本还原
                Forms.Clipboard.SetDataObject("ORIGINAL-TEXT", copy: true);
                ClipboardState s1 = ClipboardState.Capture();
                Forms.Clipboard.SetDataObject("CTRL-C-RESULT", copy: true);
                ClipboardRestoreAction a1 = ClipboardRestorePolicy.Decide(s1.CaptureSucceeded, s1.Count, true, false);
                s1.Apply(a1);
                Check("text restore", a1 == ClipboardRestoreAction.Restore && ClipboardService.GetText() == "ORIGINAL-TEXT");

                // 2) 图片还原
                using (var bmp = new Bitmap(20, 10))
                {
                    using (Graphics g = Graphics.FromImage(bmp)) g.Clear(Color.Red);
                    Forms.Clipboard.SetImage(bmp);
                }
                ClipboardState s2 = ClipboardState.Capture();
                Forms.Clipboard.SetDataObject("TEXT-AFTER-IMAGE", copy: true);
                ClipboardRestoreAction a2 = ClipboardRestorePolicy.Decide(s2.CaptureSucceeded, s2.Count, true, false);
                s2.Apply(a2);
                Check("image restore", a2 == ClipboardRestoreAction.Restore && Clipboard.ContainsImage());

                // 3) 捕获失败 → 不动（绝不清空）
                Forms.Clipboard.SetDataObject("USER-DATA", copy: true);
                ClipboardState failed = ClipboardState.SimulateCaptureFailure();
                ClipboardRestoreAction a3 = ClipboardRestorePolicy.Decide(failed.CaptureSucceeded, failed.Count, true, false);
                failed.Apply(a3);
                Check("capture-failure leaves clipboard", a3 == ClipboardRestoreAction.LeaveAsIs && ClipboardService.GetText() == "USER-DATA");

                // 4) 原本为空 + 我们改过 → 清空残留
                Forms.Clipboard.Clear();
                ClipboardState s4 = ClipboardState.Capture();
                Forms.Clipboard.SetDataObject("RESIDUE", copy: true);
                ClipboardRestoreAction a4 = ClipboardRestorePolicy.Decide(s4.CaptureSucceeded, s4.Count, true, false);
                s4.Apply(a4);
                Check("empty -> clear residue", a4 == ClipboardRestoreAction.Clear && string.IsNullOrEmpty(ClipboardService.GetText()));

                // 5) 第三方改写 → 不动
                Forms.Clipboard.SetDataObject("USER-DATA-2", copy: true);
                ClipboardState s5 = ClipboardState.Capture();
                Forms.Clipboard.SetDataObject("THIRD-PARTY", copy: true);
                ClipboardRestoreAction a5 = ClipboardRestorePolicy.Decide(s5.CaptureSucceeded, s5.Count, true, changedByThirdParty: true);
                s5.Apply(a5);
                Check("third-party untouched", a5 == ClipboardRestoreAction.LeaveAsIs && ClipboardService.GetText() == "THIRD-PARTY");
            }
            catch (Exception ex)
            {
                Check("exception: " + ex.Message, false);
            }
            finally
            {
                // 尽力还原用户剪贴板
                ClipboardRestoreAction restore = ClipboardRestorePolicy.Decide(
                    backup.CaptureSucceeded, backup.Count, true, false);
                backup.Apply(restore);
            }

            string report = $"selftest pass={pass} fail={fail}{Environment.NewLine}{sb}";
            Log.Info($"selftest pass={pass} fail={fail}");
            string outPath = Path.Combine(Path.GetTempPath(), "elta-selftest.txt");
            try { File.WriteAllText(outPath, report, new UTF8Encoding(false)); } catch { }
            try
            {
                AttachConsole(-1);
                Console.WriteLine(report);
                Console.Out.Flush();
            }
            catch { }
        }

        private static async void RunScreenshot()
        {
            Bitmap? captured = null;
            try
            {
                captured = ScreenshotService.CaptureSelection();
                if (captured == null) return;   // 取消或选区无效
                Log.Info($"screenshot captured {captured.Width}x{captured.Height}");

                // OCR 放后台线程，避免位图编码/识别阻塞 UI
                Bitmap shot = captured;
                var sw = Stopwatch.StartNew();
                OcrOutcome outcome = await Task.Run(() => OcrService.RecognizeAsync(shot));
                sw.Stop();
                Log.Info($"ocr status={outcome.Status} blocks={outcome.Blocks.Count} elapsed={sw.ElapsedMilliseconds}ms");
                switch (outcome.Status)
                {
                    case OcrStatus.NoLanguagePack:
                        Forms.DialogResult ask = Forms.MessageBox.Show(
                            "缺少英文 OCR 语言包，无法识别文字。\n是否打开系统语言设置进行安装？",
                            "ELTA — OCR（B3）",
                            Forms.MessageBoxButtons.YesNo, Forms.MessageBoxIcon.Warning);
                        if (ask == Forms.DialogResult.Yes) OcrService.OpenLanguageSettings();
                        return;
                    case OcrStatus.Failed:
                        Forms.MessageBox.Show(
                            $"OCR 失败：\n{outcome.Error}",
                            "ELTA — OCR（B3）",
                            Forms.MessageBoxButtons.OK, Forms.MessageBoxIcon.Error);
                        return;
                }

                if (outcome.Blocks.Count == 0)
                {
                    Forms.MessageBox.Show(
                        "OCR 未识别到文字。\n请确认框选区域包含清晰文字，且文字不过小/模糊。",
                        "ELTA — OCR（B3）",
                        Forms.MessageBoxButtons.OK, Forms.MessageBoxIcon.Warning);
                    return;
                }

                // 与 mac 一致：OCR 坐标 → 表格/纯文本 → 引用压缩
                string text = TextPreprocessor.CondenseCitation(TableExtractor.Process(outcome.Blocks));
                string preview = text.Length > 500 ? text.Substring(0, 500) + "…" : text;
                Forms.MessageBox.Show(
                    $"识别到 {outcome.Blocks.Count} 行，{text.Length} 字符：\n\n{preview}",
                    "ELTA — OCR（B3）",
                    Forms.MessageBoxButtons.OK, Forms.MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                // async void 内异常若逃逸会导致进程崩溃，这里兜底
                Log.Error("RunScreenshot failed", ex);
                Forms.MessageBox.Show(
                    $"截图翻译失败：\n{ex.Message}",
                    "ELTA — OCR（B3）",
                    Forms.MessageBoxButtons.OK, Forms.MessageBoxIcon.Error);
            }
            finally
            {
                captured?.Dispose();
            }
        }

        private static void RunSelection()
        {
            try
            {
                var sw = Stopwatch.StartNew();
                // 等用户松开热键（对应 mac 的 RunLoop 0.3s），否则合成的 Ctrl+C 会带上 Shift
                Thread.Sleep(300);

                string? text = SelectionReader.ReadSelectedText();
                sw.Stop();
                Log.Info($"selection len={text?.Length ?? 0} elapsed={sw.ElapsedMilliseconds}ms");

                if (string.IsNullOrEmpty(text))
                {
                    Forms.MessageBox.Show(
                        "未取到选中文本。\n请先选中一段文字，再按 Ctrl+Shift+T。",
                        "ELTA — 划词取词（B2）",
                        Forms.MessageBoxButtons.OK, Forms.MessageBoxIcon.Warning);
                    return;
                }

                string preview = text!.Length > 300 ? text.Substring(0, 300) + "…" : text;
                Forms.MessageBox.Show(
                    $"取到 {text.Length} 字符：\n\n{preview}",
                    "ELTA — 划词取词（B2）",
                    Forms.MessageBoxButtons.OK, Forms.MessageBoxIcon.Information);
            }
            catch (Exception ex)
            {
                Log.Error("RunSelection failed", ex);
                Forms.MessageBox.Show(
                    $"取词失败：\n{ex.Message}",
                    "ELTA — 划词取词（B2）",
                    Forms.MessageBoxButtons.OK, Forms.MessageBoxIcon.Error);
            }
        }
    }
}
