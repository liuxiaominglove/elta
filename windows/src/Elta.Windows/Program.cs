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

        // C1：翻译服务 + 结果窗口（设置实例在 Main 装配后赋给静态字段）
        private static SettingsManager? _settings;
        private static readonly TranslationService Translation = new();
        private static readonly UpdateService Update = new();
        private static ResultWindow? _resultWindow;

        // C3：设置窗口 + 托盘/热键引用（供设置保存后重注册与文案刷新）
        private static SettingsWindow? _settingsWindow;
        private static HotkeyManager? _hotkeys;
        private static Forms.NotifyIcon? _tray;
        private static Forms.ToolStripMenuItem? _shotItem;
        private static Forms.ToolStripMenuItem? _selectItem;

        // C2：加载窗 + 面板期间键盘路由（Esc / ` / Ctrl+D）
        private static LoadingWindow? _loadingWindow;
        private static readonly PanelKeyRouter PanelKeys = new();

        // W1：流水线代数守卫（对齐 mac currentTaskGeneration）——新任务/取消都会递增，
        // 陈旧任务的异步回调静默丢弃，避免误清新任务的加载窗或弹出陈旧结果。
        private static int _pipelineGeneration;

        private static int BeginPipeline() => ++_pipelineGeneration;

        private static bool IsStale(int gen, string site)
        {
            if (gen == _pipelineGeneration) return false;
            Log.Info($"pipeline stale at {site} gen={gen} current={_pipelineGeneration}");
            return true;
        }

        /// <summary>用户按 ESC 取消整个流水线（含 OCR 阶段）：代数失效 + 取消网络 + 关闭加载窗。</summary>
        private static void CancelPipeline()
        {
            _pipelineGeneration++;
            Translation.CancelCurrent();
            HideLoading();
        }

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

            // 调试入口：--settings-ui 直接打开设置窗口（不启动托盘），供自动化冒烟
            if (args.Length >= 1 && args[0] == "--settings-ui")
            {
                RunSettingsUiCli();
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
            _settings = settings;
            PanelKeys.Match = HandlePanelKey;

            var menu = new Forms.ContextMenuStrip();

            var shotItem = new Forms.ToolStripMenuItem($"截图选区（{settings.HotkeyDisplay}）");
            shotItem.Click += (_, _) => RunScreenshot();
            menu.Items.Add(shotItem);
            _shotItem = shotItem;

            var selectItem = new Forms.ToolStripMenuItem($"划词翻译（{settings.SelectionHotkeyDisplay}）");
            selectItem.Click += (_, _) => RunSelection();
            menu.Items.Add(selectItem);
            _selectItem = selectItem;

            var settingsItem = new Forms.ToolStripMenuItem("设置…");
            settingsItem.Click += (_, _) => OpenSettings();
            menu.Items.Add(settingsItem);

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
            _tray = tray;
            tray.BalloonTipClicked += (_, _) =>
            {
                // C4a：点击「翻译完成」气泡 → 把结果窗拉到前台
                if (_resultWindow is not null) _resultWindow.Activate();
                Log.Info("notification clicked");
            };

            // 热键由设置决定（清洗键码/掩码，防脏数据）；设置窗口保存后可重注册
            _hotkeys = new HotkeyManager();
            _hotkeys.StatusChanged += UpdateTrayStatus;
            RegisterHotkeysFromSettings(settings);

            Log.Info($"start version={typeof(Program).Assembly.GetName().Version} " +
                     $"hotkeys={(_hotkeys.AllRegistered ? "ok" : "pending:" + string.Join(",", _hotkeys.PendingNames))} " +
                     $"logDir={Log.DirectoryPath}");
            Log.Info($"settings provider={AIProviders.RawValue(settings.ApiProvider)} " +
                     $"model={settings.EffectiveModel(settings.ApiProvider)} " +
                     $"keySet={settings.ActiveApiKey != null} " +
                     $"hotkey={settings.HotkeyDisplay} selHotkey={settings.SelectionHotkeyDisplay} " +
                     $"telemetry={(settings.TelemetryEnabled ? "on" : "off")}");

            tray.ShowBalloonTip(3500, "ELTA",
                $"{settings.HotkeyDisplay} 截图；{settings.SelectionHotkeyDisplay} 划词" +
                $"{(_hotkeys.AllRegistered ? "" : "（部分热键被占用，将自动重试）")}",
                Forms.ToolTipIcon.Info);

            // C4b/C4c：启动 3 秒后查一次更新（遥测 = 同一请求带 id，对齐 mac 时机）
            ScheduleUpdateCheck(settings, CurrentVersion());

            app.Exit += (_, _) =>
            {
                Log.Info("exit");
                PanelKeys.Stop();
                _hotkeys.Dispose();
                tray.Visible = false;
                tray.Dispose();
                menu.Dispose();
            };

            app.Run();
        }

        // MARK: - C3：设置窗口 / 热键重注册

        private static void OpenSettings()
        {
            if (_settings is null) return;
            if (_settingsWindow is not null)
            {
                _settingsWindow.Activate();
                return;
            }
            _settingsWindow = new SettingsWindow(_settings, ReregisterHotkeys);
            _settingsWindow.Closed += (_, _) => _settingsWindow = null;
            _settingsWindow.Show();
        }

        private static void ReregisterHotkeys()
        {
            if (_settings is null || _hotkeys is null) return;
            RegisterHotkeysFromSettings(_settings);
            Log.Info("hotkeys reregistered after settings change");
        }

        private static void RegisterHotkeysFromSettings(SettingsManager settings)
        {
            HotkeyManager hotkeys = _hotkeys!;
            hotkeys.Reset();

            int shotVk = WindowsHotkeys.SanitizeKeyCode(settings.HotkeyKeyCode);
            int shotMods = settings.HotkeyModifiers & WindowsHotkeys.AllModifiers;
            int selectVk = WindowsHotkeys.SanitizeKeyCode(settings.SelectionHotkeyKeyCode);
            int selectMods = settings.SelectionHotkeyModifiers & WindowsHotkeys.AllModifiers;

            hotkeys.Add(ID_SCREENSHOT, (uint)shotMods, (uint)shotVk,
                () => System.Windows.Application.Current.Dispatcher.BeginInvoke((Action)RunScreenshot), "shot");
            hotkeys.Add(ID_SELECTION, (uint)selectMods, (uint)selectVk,
                () => System.Windows.Application.Current.Dispatcher.BeginInvoke((Action)RunSelection), "selection");
            hotkeys.RegisterAll();

            if (_shotItem is not null) _shotItem.Text = $"截图选区（{settings.HotkeyDisplay}）";
            if (_selectItem is not null) _selectItem.Text = $"划词翻译（{settings.SelectionHotkeyDisplay}）";
        }

        private static void UpdateTrayStatus()
        {
            if (_tray is null || _hotkeys is null) return;
            bool all = _hotkeys.AllRegistered;
            _tray.Text = all ? "ELTA — 截图即译，精读利器" : "ELTA（热键被占用，自动重试中）";
            if (all) Log.Info("hotkeys all registered");
        }

        /// <summary>调试入口：`--settings-ui` 只打开设置窗口（无托盘），供自动化冒烟。</summary>
        private static void RunSettingsUiCli()
        {
            // W3：调试实例与托盘实例共用同一份配置；并发保存有互相覆盖风险，仅提示不拦截
            bool trayRunning = false;
            try
            {
                using Mutex probe = Mutex.OpenExisting(@"Local\Elta.Windows.SingleInstance");
                trayRunning = true;
            }
            catch (WaitHandleCannotBeOpenedException) { }
            if (trayRunning)
                Log.Warn("settings-ui: tray instance is running; shared config, avoid concurrent saves");

            var app = new System.Windows.Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
            var settings = new SettingsManager(
                new JsonSettingsStore(), new DpapiSecretStore(), SettingsDefaults.Windows, msg => Log.Info(msg));
            var win = new SettingsWindow(settings, () => { });
            app.Run(win);
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

            int gen = BeginPipeline();
            Bitmap? captured = null;
            string? text = null;
            Rectangle selectionRect = Rectangle.Empty;
            try
            {
                (captured, selectionRect) = ScreenshotService.CaptureSelection();
                if (captured == null) return;   // 取消或选区无效
                Log.Info($"screenshot captured {captured.Width}x{captured.Height}");

                // C2：与 mac 一致，OCR 阶段即显示加载窗（ESC 可取消）
                ShowLoading("正在识别与翻译...", "OCR 识别 → AI 翻译分析");

                // OCR 放后台线程，避免位图编码/识别阻塞 UI
                Bitmap shot = captured;
                var sw = Stopwatch.StartNew();
                OcrOutcome outcome = await Task.Run(() => OcrService.RecognizeAsync(shot));
                sw.Stop();
                Log.Info($"ocr status={outcome.Status} blocks={outcome.Blocks.Count} elapsed={sw.ElapsedMilliseconds}ms");

                // W1：OCR 期间被 ESC 取消 → 静默中止（不弹框、不发起翻译）
                if (IsStale(gen, "post-ocr")) return;

                switch (outcome.Status)
                {
                    case OcrStatus.NoLanguagePack:
                        HideLoading();
                        Forms.DialogResult ask = Forms.MessageBox.Show(
                            "缺少英文 OCR 语言包，无法识别文字。\n是否打开系统语言设置进行安装？",
                            "ELTA",
                            Forms.MessageBoxButtons.YesNo, Forms.MessageBoxIcon.Warning);
                        if (ask == Forms.DialogResult.Yes) OcrService.OpenLanguageSettings();
                        return;
                    case OcrStatus.Failed:
                        HideLoading();
                        Forms.MessageBox.Show(
                            $"OCR 失败：\n{outcome.Error}",
                            "ELTA",
                            Forms.MessageBoxButtons.OK, Forms.MessageBoxIcon.Error);
                        return;
                }

                if (outcome.Blocks.Count == 0)
                {
                    HideLoading();
                    Forms.MessageBox.Show(
                        "OCR 未识别到文字。\n请确认框选区域包含清晰文字，且文字不过小/模糊。",
                        "ELTA",
                        Forms.MessageBoxButtons.OK, Forms.MessageBoxIcon.Warning);
                    return;
                }

                // 与 mac 一致：OCR 坐标 → 表格/纯文本 → 引用压缩
                text = TextPreprocessor.CondenseCitation(TableExtractor.Process(outcome.Blocks));
            }
            catch (Exception ex)
            {
                // async void 内异常若逃逸会导致进程崩溃，这里兜底
                Log.Error("RunScreenshot failed", ex);
                if (IsStale(gen, "catch")) return;
                HideLoading();
                Forms.MessageBox.Show(
                    $"截图翻译失败：\n{ex.Message}",
                    "ELTA",
                    Forms.MessageBoxButtons.OK, Forms.MessageBoxIcon.Error);
                return;
            }
            finally
            {
                captured?.Dispose();
                ExitBusy();
            }

            // C1/C2：识别成功 → 翻译 → 结果窗口（翻译自带「取消旧请求」，不进 busy 守卫）
            if (text != null && !IsStale(gen, "pre-translate"))
                await TranslateAndShowAsync(text, selectionRect, gen);
        }

        private static async void RunSelection()
        {
            if (!TryEnterBusy())
            {
                Log.Info("selection ignored: busy");
                return;
            }

            int gen = BeginPipeline();
            string? text = null;
            try
            {
                var sw = Stopwatch.StartNew();
                // WI-3：在 STA 工作线程上执行（WinForms 剪贴板要求 STA），不阻塞 UI
                text = await StaRunner.RunAsync(() =>
                {
                    Thread.Sleep(HotkeyReleaseDelayMs);
                    return SelectionReader.ReadSelectedText();
                });
                sw.Stop();
                Log.Info($"selection len={text?.Length ?? 0} elapsed={sw.ElapsedMilliseconds}ms");

                if (IsStale(gen, "selection")) return;
                if (string.IsNullOrEmpty(text))
                {
                    Forms.MessageBox.Show(
                        "未取到选中文本。\n请先选中一段文字，再按 Ctrl+Shift+T。",
                        "ELTA",
                        Forms.MessageBoxButtons.OK, Forms.MessageBoxIcon.Warning);
                    return;
                }
            }
            catch (Exception ex)
            {
                Log.Error("RunSelection failed", ex);
                if (IsStale(gen, "catch")) return;
                Forms.MessageBox.Show(
                    $"取词失败：\n{ex.Message}",
                    "ELTA",
                    Forms.MessageBoxButtons.OK, Forms.MessageBoxIcon.Error);
                return;
            }
            finally
            {
                ExitBusy();
            }

            // C1/C2：取词成功 → 翻译 → 结果窗口
            if (!string.IsNullOrEmpty(text) && !IsStale(gen, "pre-translate"))
            {
                ShowLoading("正在翻译...", "划词翻译 → AI 翻译分析");
                await TranslateAndShowAsync(text!, MouseAnchor(), gen);
            }
        }

        /// <summary>C1/C2：翻译并展示结果窗口；调用方已显示加载窗，本方法负责在所有终止路径隐藏它。</summary>
        private static async Task TranslateAndShowAsync(string originalText, Rectangle avoidRect, int gen)
        {
            SettingsManager settings = _settings!;
            AIProvider provider = settings.ApiProvider;

            if (IsStale(gen, "missing-key")) return;
            if (string.IsNullOrEmpty(settings.ActiveApiKey))
            {
                HideLoading();
                Log.Info("translate missing key");
                Forms.DialogResult open = Forms.MessageBox.Show(
                    $"未配置 {AIProviders.DisplayName(provider)} API Key。\n" +
                    $"注册地址：{AIProviders.RegisterUrl(provider)}\n\n" +
                    "是否打开设置进行配置？（按“是”打开设置）",
                    "ELTA",
                    Forms.MessageBoxButtons.YesNo, Forms.MessageBoxIcon.Warning);
                if (open == Forms.DialogResult.Yes) OpenSettings();
                return;
            }

            var sw = Stopwatch.StartNew();
            TranslationOutcome outcome = await Translation.TranslateAsync(originalText, settings);
            sw.Stop();

            // W1：陈旧任务（被取消或被新任务顶掉）静默丢弃：不碰加载窗、不弹结果/错误
            if (IsStale(gen, "translate-done")) return;

            HideLoading();
            Log.Info($"translate kind={outcome.Kind} elapsed={sw.ElapsedMilliseconds}ms");

            switch (outcome.Kind)
            {
                case TranslationOutcomeKind.Success:
                    // C4 加固：结果窗单实例复用——避免每次翻译都重建 WebView2（反复初始化会闪烁/挂起）
                    if (_resultWindow is null)
                    {
                        var window = new ResultWindow(settings);
                        window.Closed += (_, _) =>
                        {
                            _resultWindow = null;
                            UpdatePanelHook();
                        };
                        _resultWindow = window;
                        window.Show();
                        UpdatePanelHook();
                    }
                    _resultWindow.ShowResult(outcome.Text!, originalText, avoidRect);
                    // C4a：完成通知（点击气泡 → 聚焦结果窗）
                    _tray?.ShowBalloonTip(3000, "ELTA", "翻译完成，点击查看结果", Forms.ToolTipIcon.Info);
                    Log.Info("notification shown");
                    break;
                case TranslationOutcomeKind.Cancelled:
                    // 用户 ESC 的路径已被代数守卫拦在前面；此处仅剩防御性场景
                    Log.Info("translate outcome=Cancelled (current task)");
                    break;
                case TranslationOutcomeKind.MissingKey:
                    break;
                default:
                    Forms.MessageBox.Show(
                        "翻译失败，请检查网络与 API Key 后重试。",
                        "ELTA",
                        Forms.MessageBoxButtons.OK, Forms.MessageBoxIcon.Error);
                    break;
            }
        }

        // MARK: - C2：加载窗 / 面板键盘路由

        private static void ShowLoading(string title, string subtitle)
        {
            HideLoading();
            var window = new LoadingWindow(title, subtitle);
            _loadingWindow = window;
            window.Closed += (_, _) =>
            {
                if (ReferenceEquals(_loadingWindow, window)) _loadingWindow = null;
                UpdatePanelHook();
            };
            window.Show();
            UpdatePanelHook();
        }

        private static void HideLoading()
        {
            LoadingWindow? window = _loadingWindow;
            if (window is null) return;
            _loadingWindow = null;
            window.Close();
            UpdatePanelHook();
        }

        private static void UpdatePanelHook()
        {
            bool need = _loadingWindow is not null || _resultWindow is not null;
            if (need) PanelKeys.Start();
            else PanelKeys.Stop();
        }

        /// <summary>
        /// 面板键路由：结果窗期间 Esc=关闭、`=翻面、Ctrl+D=拆分；加载期间 Esc=取消。
        /// 两者可能短暂并存（旧结果 + 新任务加载）——对齐 mac 的独立 tap：两类动作都处理，不互斥。
        /// </summary>
        private static bool HandlePanelKey(int vk, int modifiers)
        {
            SettingsManager s = _settings!;
            bool handled = false;

            if (_resultWindow is not null)
            {
                if (vk == s.ClosePanelHotkeyKeyCode && modifiers == s.ClosePanelHotkeyModifiers)
                {
                    _resultWindow.ClosePanel();
                    handled = true;
                }
                else if (vk == s.TogglePanelHotkeyKeyCode && modifiers == s.TogglePanelHotkeyModifiers)
                {
                    _resultWindow.TogglePosition();
                    handled = true;
                }
                else if (vk == s.SplitHotkeyKeyCode && modifiers == s.SplitHotkeyModifiers)
                {
                    _resultWindow.ToggleSplit();
                    handled = true;
                }
            }

            if (_loadingWindow is not null &&
                vk == s.ClosePanelHotkeyKeyCode && modifiers == s.ClosePanelHotkeyModifiers)
            {
                Log.Info("panel key: cancel pipeline (ESC)");
                CancelPipeline();
                handled = true;
            }

            return handled;
        }

        /// <summary>划词路径的定位锚点：触发时的鼠标位置（10×10，物理像素）。</summary>
        private static Rectangle MouseAnchor()
        {
            System.Drawing.Point p = Forms.Cursor.Position;
            return new Rectangle(p.X - 5, p.Y - 5, 10, 10);
        }

        // MARK: - C4：更新检查

        private static string CurrentVersion()
            => typeof(Program).Assembly.GetName().Version?.ToString(3) ?? "0.0.0";

        /// <summary>启动 3 秒后查一次（对齐 mac：不阻塞主流程，只查一次）。</summary>
        private static void ScheduleUpdateCheck(SettingsManager settings, string currentVersion)
        {
            var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
            timer.Tick += async (_, _) =>
            {
                timer.Stop();
                UpdateInfo? info = await Update.CheckAsync(settings, currentVersion);
                if (info is null) return;
                if (!UpdateLogic.ShouldShowUpdate(info.Version, currentVersion, settings.SkipUpdateVersion))
                {
                    Log.Info($"update ignored remote={info.Version} (same or skipped)");
                    return;
                }
                ShowUpdateDialog(settings, currentVersion, info);
            };
            timer.Start();
        }

        private static void ShowUpdateDialog(SettingsManager settings, string currentVersion, UpdateInfo info)
        {
            Log.Info($"update found remote={info.Version}");
            var dialog = new UpdateDialog(currentVersion, info.Version);
            dialog.ShowDialog();
            switch (dialog.Result)
            {
                case UpdateDialog.Choice.Download:
                    // 打开前二次校验协议（Core IsHttpUrl），不合法回退官网
                    string target = UpdateLogic.IsHttpUrl(info.Url) ? info.Url : UpdateLogic.DownloadPageUrl;
                    try
                    {
                        Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
                    }
                    catch (Exception ex)
                    {
                        Log.Error("open download url failed", ex);
                    }
                    break;
                case UpdateDialog.Choice.Skip:
                    settings.SkipUpdateVersion = info.Version;
                    Log.Info($"update skipped v{info.Version}");
                    break;
                default:
                    Log.Info("update deferred (later)");
                    break;
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
