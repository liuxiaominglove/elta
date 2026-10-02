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
        private const int ID_SCREENSHOT = 0x4A17;
        private const int ID_SELECTION = 0x4A18;
        private const int HotkeyReleaseDelayMs = 300;   // 等用户松开热键（对应 mac RunLoop 0.3s）

        // WI-3：全局重入守卫——截图/取词/OCR 任一在跑时忽略新触发，避免嵌套与剪贴板竞争
        private static int _busy;
        private static bool TryEnterBusy() => Interlocked.CompareExchange(ref _busy, 1, 0) == 0;
        private static void ExitBusy() => Interlocked.Exchange(ref _busy, 0);

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

            // 无头诊断：--selection-selftest <输出文件> 走与 RunSelection 同路径（STA + UIA 看门狗 → 兜底）
            if (args.Length >= 2 && args[0] == "--selection-selftest")
            {
                RunSelectionSelfTestCli(args[1]);
                return;
            }

            // 无头诊断：--selftest 跑剪贴板策略集成自检（不启动托盘、不依赖外部程序）
            if (args.Length >= 1 && args[0] == "--selftest")
            {
                RunSelfTest();
                return;
            }

            // 无头诊断：--settings-selftest <输出文件> 配置存储/密钥库/默认值自检
            if (args.Length >= 2 && args[0] == "--settings-selftest")
            {
                RunSettingsSelfTest(args[1]);
                return;
            }

            // 无头诊断：--hook-selftest <输出文件> 低级键盘钩子安装 + 注入按键自检
            if (args.Length >= 2 && args[0] == "--hook-selftest")
            {
                RunHookSelfTest(args[1]);
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

            // B4：设置 = JSON 存储 + DPAPI 密钥库 + Windows 默认值（键位/显示）
            var settings = new SettingsManager(
                new JsonSettingsStore(), new DpapiSecretStore(), SettingsDefaults.Windows, msg => Log.Info(msg));

            var menu = new Forms.ContextMenuStrip();

            var shotItem = new Forms.ToolStripMenuItem($"截图选区（{settings.HotkeyDisplay}）");
            shotItem.Click += (_, _) => RunScreenshot();
            menu.Items.Add(shotItem);

            var selectItem = new Forms.ToolStripMenuItem($"划词翻译（{settings.SelectionHotkeyDisplay}）");
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

            // 热键由设置决定；清洗键码/掩码，防脏数据（含 mac Carbon 残留值）
            int shotVk = WindowsHotkeys.SanitizeKeyCode(settings.HotkeyKeyCode);
            int shotMods = settings.HotkeyModifiers & WindowsHotkeys.AllModifiers;
            int selectVk = WindowsHotkeys.SanitizeKeyCode(settings.SelectionHotkeyKeyCode);
            int selectMods = settings.SelectionHotkeyModifiers & WindowsHotkeys.AllModifiers;

            var hotkeys = new HotkeyManager();
            hotkeys.Add(ID_SCREENSHOT, (uint)shotMods, (uint)shotVk,
                () => app.Dispatcher.BeginInvoke((Action)RunScreenshot), "shot");
            hotkeys.Add(ID_SELECTION, (uint)selectMods, (uint)selectVk,
                () => app.Dispatcher.BeginInvoke((Action)RunSelection), "selection");
            hotkeys.StatusChanged += () =>
            {
                bool all = hotkeys.AllRegistered;
                tray.Text = all ? "ELTA — 截图即译，精读利器" : "ELTA（热键被占用，自动重试中）";
                if (all) Log.Info("hotkeys all registered");
            };
            hotkeys.RegisterAll();

            Log.Info($"start version={typeof(Program).Assembly.GetName().Version} " +
                     $"hotkeys={(hotkeys.AllRegistered ? "ok" : "pending:" + string.Join(",", hotkeys.PendingNames))} " +
                     $"logDir={Log.DirectoryPath}");
            Log.Info($"settings provider={AIProviders.RawValue(settings.ApiProvider)} " +
                     $"model={settings.EffectiveModel(settings.ApiProvider)} " +
                     $"keySet={settings.ActiveApiKey != null} " +
                     $"hotkey={settings.HotkeyDisplay} selHotkey={settings.SelectionHotkeyDisplay}");

            tray.ShowBalloonTip(3500, "ELTA",
                $"{settings.HotkeyDisplay} 截图；{settings.SelectionHotkeyDisplay} 划词" +
                $"{(hotkeys.AllRegistered ? "" : "（部分热键被占用，将自动重试）")}",
                Forms.ToolTipIcon.Info);

            app.Exit += (_, _) =>
            {
                Log.Info("exit");
                hotkeys.Dispose();
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

        [DllImport("user32.dll")]
        private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

        private static void WriteCliReport(string outPath, string header, string body)
        {
            string report = header + Environment.NewLine + body;
            Log.Info(header);
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
        /// 无头诊断：`--settings-selftest &lt;输出文件&gt;` B4 配置存储 / DPAPI 密钥库 / Windows 默认值自检。
        /// 使用临时目录，不触碰真实设置与密钥；测试密钥用后即删。
        /// </summary>
        private static void RunSettingsSelfTest(string outPath)
        {
            var sb = new StringBuilder();
            int pass = 0, fail = 0;
            void Check(string name, bool ok)
            {
                sb.AppendLine($"[{(ok ? "PASS" : "FAIL")}] {name}");
                if (ok) pass++; else fail++;
            }

            string tempDir = Path.Combine(Path.GetTempPath(), "elta-settings-selftest");
            try { if (Directory.Exists(tempDir)) Directory.Delete(tempDir, recursive: true); } catch { }
            Directory.CreateDirectory(tempDir);

            try
            {
                // 1) JSON 配置存储：读写 / 持久化 / 删除
                string settingsPath = Path.Combine(tempDir, "settings.json");
                var store = new JsonSettingsStore(settingsPath);
                store.SetString("k.s", "value");
                store.SetBool("k.b", true);
                store.SetInt("k.i", 42);
                Check("store string", store.GetString("k.s") == "value");
                Check("store bool", store.GetBool("k.b") == true);
                Check("store int", store.GetInt("k.i") == 42);
                Check("store contains", store.Contains("k.s"));
                var reloaded = new JsonSettingsStore(settingsPath);
                Check("store persisted", reloaded.GetString("k.s") == "value");
                store.Remove("k.s");
                Check("store remove", store.GetString("k.s") == null && !store.Contains("k.s"));

                // 回归：缺失键必须返回 null（不能是 0/false），否则默认值不生效
                Check("store missing string is null", store.GetString("missing.k") == null);
                Check("store missing bool is null", store.GetBool("missing.k") == null);
                Check("store missing int is null", store.GetInt("missing.k") == null);

                // 2) DPAPI 密钥库：写 / 读 / 删（幂等）；测试值用后即删
                var secrets = new DpapiSecretStore(Path.Combine(tempDir, "secrets"));
                const string account = "snaptranslate.selftest";
                const string dummy = "DUMMY-SECRET-FOR-SELFTEST";
                Check("secret save", secrets.Save(account, dummy));
                Check("secret read", secrets.Read(account) == dummy);
                Check("secret delete", secrets.Delete(account));
                Check("secret gone", secrets.Read(account) == null);
                Check("secret delete idempotent", secrets.Delete(account));

                // 3) Windows 默认值
                SettingsDefaults d = SettingsDefaults.Windows;
                Check("defaults hotkey", d.HotkeyKeyCode == 0x54 && d.HotkeyDisplay == "Ctrl+T");
                Check("defaults selection display",
                    WindowsHotkeys.Display(d.SelectionHotkeyKeyCode, d.SelectionHotkeyModifiers) == "Ctrl+Shift+T");

                // 4) 键码清洗 / 修饰键判定
                Check("sanitize clamp", WindowsHotkeys.SanitizeKeyCode(999) == 0xFF);
                Check("required modifiers",
                    WindowsHotkeys.HasRequiredModifiers(WindowsHotkeys.ModControl)
                    && !WindowsHotkeys.HasRequiredModifiers(0));

                // 5) SettingsManager 走 Windows 默认值
                var sm = new SettingsManager(
                    new JsonSettingsStore(Path.Combine(tempDir, "s2.json")),
                    new DpapiSecretStore(Path.Combine(tempDir, "secrets2")),
                    SettingsDefaults.Windows);
                Check("settings defaults", sm.HotkeyDisplay == "Ctrl+T" && sm.SelectionHotkeyDisplay == "Ctrl+Shift+T");
                Check("settings numeric defaults",
                    sm.HotkeyKeyCode == 0x54
                    && sm.HotkeyModifiers == WindowsHotkeys.ModControl
                    && sm.SelectionHotkeyModifiers == (WindowsHotkeys.ModControl | WindowsHotkeys.ModShift));
                Check("settings bool defaults", sm.DefaultSplitMode && sm.TelemetryEnabled);
                Check("settings provider", sm.ApiProvider == AIProvider.Deepseek && sm.ActiveApiKey == null);
            }
            catch (Exception ex)
            {
                Check("exception: " + ex.Message, false);
            }
            finally
            {
                try { Directory.Delete(tempDir, recursive: true); } catch { }
            }

            WriteCliReport(outPath, $"settings-selftest pass={pass} fail={fail}", sb.ToString());
        }

        /// <summary>
        /// 无头诊断：`--hook-selftest &lt;输出文件&gt;` 安装 WH_KEYBOARD_LL、注入一个按键并验证回调触发。
        /// </summary>
        private static void RunHookSelfTest(string outPath)
        {
            var sb = new StringBuilder();
            int pass = 0, fail = 0;
            void Check(string name, bool ok)
            {
                sb.AppendLine($"[{(ok ? "PASS" : "FAIL")}] {name}");
                if (ok) pass++; else fail++;
            }

            const int VK_F13 = 0x7C;
            const uint KEYEVENTF_KEYUP = 0x0002;
            int fired = 0;
            try
            {
                using var hook = new LowLevelKeyboardHook();
                hook.OnKeyDown = vk =>
                {
                    if (vk == VK_F13) fired++;
                    return false;
                };
                bool started = hook.Start();
                Check("hook install", started);
                if (started)
                {
                    keybd_event(VK_F13, 0, 0, UIntPtr.Zero);
                    keybd_event(VK_F13, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);

                    int deadline = Environment.TickCount + 1500;
                    while (fired == 0 && Environment.TickCount < deadline)
                    {
                        Forms.Application.DoEvents();   // LL 钩子回调需要消息泵
                        Thread.Sleep(10);
                    }
                    Check("hook fired on injected key", fired >= 1);
                }
            }
            catch (Exception ex)
            {
                Check("exception: " + ex.Message, false);
            }

            WriteCliReport(outPath, $"hook-selftest pass={pass} fail={fail}", sb.ToString());
        }

        private static async void RunScreenshot()
        {
            if (!TryEnterBusy())
            {
                Log.Info("screenshot ignored: busy");
                return;
            }

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
                ExitBusy();
            }
        }

        private static async void RunSelection()
        {
            if (!TryEnterBusy())
            {
                Log.Info("selection ignored: busy");
                return;
            }

            try
            {
                var sw = Stopwatch.StartNew();
                // WI-3：在 STA 工作线程上执行（WinForms 剪贴板要求 STA），不阻塞 UI
                string? text = await StaRunner.RunAsync(() =>
                {
                    Thread.Sleep(HotkeyReleaseDelayMs);
                    return SelectionReader.ReadSelectedText();
                });
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
            finally
            {
                ExitBusy();
            }
        }

        /// <summary>
        /// 无头诊断：`--selection-selftest &lt;输出文件&gt;` 走与 RunSelection 相同路径
        /// （STA 工作线程 + UIA 看门狗 → Ctrl+C 兜底），供脚本驱动做端到端验证。
        /// </summary>
        private static void RunSelectionSelfTestCli(string outPath)
        {
            string report;
            try
            {
                string? text = StaRunner.RunAsync(() =>
                {
                    Thread.Sleep(HotkeyReleaseDelayMs);
                    return SelectionReader.ReadSelectedText();
                }).GetAwaiter().GetResult();
                report = text is null ? "selected=null" : $"selected=len={text.Length}{Environment.NewLine}{text}";
                Log.Info($"selection-selftest len={text?.Length ?? 0}");
            }
            catch (Exception ex)
            {
                report = "EXCEPTION: " + ex;
                Log.Error("selection-selftest failed", ex);
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
    }
}
