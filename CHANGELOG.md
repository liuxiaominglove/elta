# Changelog

All notable changes to ELTA will be documented in this file.

## [v5.2.2] — 2026-08-19

### Changed
- 应用改用 **Developer ID 签名 + 公证（notarization）**：从官网/GitHub 下载后双击打开**不再出现「无法验证」安全弹窗**
- 官网下载页支持**国内直链下载**（腾讯云服务器直出，国内用户无需 VPN 也能下载）

### Fixed
- 修复审计确认的安全与稳定性问题：192.168 端点校验（SSRF）、热键 keyCode 0 哨兵冲突、CapsLock 复制粘贴、Keychain 静默丢弃、重置模板残留、主线程卡顿、浮点 epsilon 等

## [v5.2.1] — 2026-08-16

### Fixed
- 修复 DeepSeek V4（`deepseek-v4-flash`/`deepseek-v4-pro`）默认开启思考模式导致翻译慢约 6.7 倍、多烧约 7 倍 token（请求显式传 `thinking: disabled` 关闭思考）
- DeepSeek 默认模型从已停用的 `deepseek-chat` 迁移至 `deepseek-v4-flash`（旧模型名已于 2026-07-24 停用，此前 DeepSeek 翻译会直接报错）
- Google Gemini 默认模型从已停用的 `gemini-2.0-flash` 迁移至 `gemini-2.5-flash`（旧模型已于 2026-06-01 停用）
- Anthropic 默认模型从 `claude-3-5-sonnet-20241022` 迁移至 `claude-sonnet-4-6`
- Google Gemini 的 API 地址改为随所选模型动态拼接，消除「测试连接」与「翻译」两处模型名不一致

### Added
- 所有 AI 提供商支持**模型选择**：官方模型（DeepSeek/OpenAI/Anthropic/Gemini/千问）在设置页显示下拉框预设，本地/第三方（Ollama/OpenAI-Compatible）保留自由输入
- 旧 `customModel` / `ollamaModel` 存储自动迁移至统一的每-provider 模型覆盖存储
- 修复「清空模型名保存后旧值残留」：清空模型输入框并保存会清除覆盖，回退到默认模型

## [v5.2.0] — 2026-08-16

### Added
- 新增「悬停翻译」（免截图/划词）：鼠标移到段落**右下角**，按快捷键 `⌥⌘T` 翻译鼠标上方**半屏**内容。设置页可选**内容范围**：`双栏`（取鼠标左侧半屏宽，适配左右分页）或 `整栏`（取整屏宽，适配全屏单栏）。窗口内按「**行距为主 + 首行缩进为辅**」自动分段，可能覆盖多段或半段。
- 悬停翻译自动识别窗口内**表格**，转为 **Markdown 表格**，便于 AI 逐格翻译、保持表格结构。

## [v5.1.33] — 2026-08-14

### Fixed（多模型审计后修复）
- 修复迁移 API Key 时忽略 Keychain 写入结果、无条件删除 UserDefaults 明文导致的**数据丢失**（写失败时旧 key 永久丢失）
- 修复 `setApiKey` 保存新 key 后未清除 UserDefaults 明文回退，明文 key 残留
- 修复 Keychain 存储「先删后加」：`SecItemAdd` 失败时旧 key 已被删除（改为 `SecItemUpdate` 优先，找不到才新增）
- 修复「测试连接」把 HTTP 401/403（认证失败）误报为「连接成功」，现在显示红色「API Key 无效」
- 修复快捷键录制用 keyCode `0` 作「未录制」哨兵值，导致 `Cmd+A`（A 键 keyCode=0）被静默丢弃（改为 `Optional<Int>`）
- 修复 Accessibility 划词截取用 `String.count`（grapheme）当 CFRange 偏移，含 emoji/生僻字时截错位置（改为 UTF-16 偏移）
- 修复划词选中文本被写入日志文件（隐私），改为只记录长度
- 修复剪贴板恢复「先 clearContents 再 writeObjects」，写失败会丢失原剪贴板内容（改为 writeObjects 原子替换）
- 修复 `NSRegularExpression` 每次调用重复编译（提取为静态缓存）
- 修复切换 provider 后明文/密文输入框可见性状态错乱（loadKey 未复位 isHidden）
- 修复 providerChanged 先切换 provider 再检查 UI 就绪，失败时半切换（调整顺序）
- 修复 HotkeyRecorder.reset() 未复位 isRecording、未移除键盘监听（恢复默认时状态残留）
- 恢复设置界面底部版本号标签（WIP 重构时误删）

## [v5.1.32] — 2026-08-12

### Security
- API Key 不再写入 UserDefaults 明文存储，仅保留 Keychain 加密（移除 `setApiKey` 的 UD 回写）
- 翻译结果面板 AI 响应做 HTML 转义 + WKWebView 禁用 JavaScript（防御 XSS）
- 自定义 Endpoint URL 校验：拦截 `file://`/`javascript:` 等危险 scheme，非本地 HTTP 必须 HTTPS
- 划词翻译剪贴板恢复失败时记录警告日志

### Fixed
- 修复快捷键重注册时 Carbon 事件处理器累积泄漏（多次切换快捷键后重复触发翻译）
- 修复 `activeApiKey` 保护性判空，防止未经配置首次启动偶发崩溃
- SettingsManager 关键属性（`apiProvider`/`activeApiKey`/热键）加 `NSLock` 线程安全保护

### Changed
- TranslationEngine 从阻塞式 Semaphore 重构为异步回调，避免占用 GCD 线程池
- 提取 `ResponseParser` 独立模块，统一多提供商 JSON 响应解析
- 翻译结果面板 JavaScript 禁用 API 改用 `allowsContentJavaScript`（替代已 deprecated 的 `javaScriptEnabled`）

## [v5.1.30] — 2026-08-10

### Added
- 新增切换弹窗位置快捷键，默认 `` ` `` 键一键切换翻译面板左右位置
- 快捷键可在设置 → 快捷键中自定义

## [v5.1.29] — 2026-08-05

### Security
- API Key 从 UserDefaults 明文存储迁移至 macOS Keychain 安全存储
- KeychainHelper 增加 force-unwrap 兜底保护

### Fixed
- Anthropic（Claude）测试连接按钮永远失败的问题
- 翻译弹窗关闭后 CFRunLoopSource 内存泄漏
- Gemini 测试连接与翻译使用一致的 `x-goog-api-key` Header 鉴权
- 偏好设置窗口关闭后重新打开不刷新 Key 字段
- 加载提示框始终定位在主屏幕而非当前活动屏幕
- AppDelegate 悬垂指针导致 SIGSEGV 崩溃

### Changed
- 三个快捷键录制器拆分为独立的事件监听器
- 删除 4 个文件中的重复 `import` 语句
- `gen_icon.swift` 硬编码路径改为当前工作目录
- 修正 `SettingsManagerTests` 中快捷键默认值的错误断言

### Added
- `AGENTS.md` 开发者指引文档

## [v5.1.18] — 2026-07-31

### Added
- 代码模块化拆分：2807 行 `main.swift` 拆分为 15 个模块文件
- GitHub Actions 自动构建：推送 `v*` 标签时自动编译 Universal Binary、打包 DMG、上传到 Release
- Sitemap：添加 `sitemap.xml` 支持搜索引擎收录

### Changed
- DMG 二进制文件迁移至 GitHub Releases，不再纳入 Git 仓库
- 下载按钮指向 GitHub Releases 最新版本

## [v5.1.17] — 2026-07-29

### Fixed
- 四项基础改进：防崩溃保护、日志路径修正、动态 AI 页脚、网站版本同步

## [v5.1.16] — 2026-07-27

### Fixed
- 修复翻译弹窗任意按键都能关闭的 Bug

## [v5.1.15] — 2026-07-27

### Fixed
- 修复 Cmd+C 复制无效 + 全局 ESC 关闭翻译面板

## [v5.1.14] — 2026-07-26

### Changed
- 同步两个授权弹窗，无论先按哪个快捷键都同时触发

## [v5.1.13] — 2026-07-26

### Changed
- 设置窗口置顶
- 取消 API Key 默认选中

## [v5.1.12] — 2026-07-24

### Fixed
- 通用设置页卡片默认显示顶部
- 通用设置页常驻滚动条

## [v5.1.11] — 2026-07-23

### Fixed
- 修复通用设置页 AI 提供商卡片文字重叠

## [v5.1.10] — 2026-07-23

### Fixed
- 彻底解决快捷键设置页提示重叠问题

## [v5.1.9] — 2026-07-22

### Changed
- 进一步调整快捷键设置页布局

## [v5.1.8] — 2026-07-22

### Changed
- 优化快捷键设置页布局

## [v5.1.7] — 2026-07-21

### Added
- 设置界面新增 ESC 关闭面板说明（不可修改）

## [v5.1.6] — 2026-07-20

### Changed
- 更新默认提示词模板

## [v5.1.5] — 2026-07-19

### Added
- 权限弹窗合并

### Changed
- 文档新增权限说明章节

## [v5.1.4] — 2026-07-18

### Added
- 小眼睛显隐功能：设置界面 API Key 输入框支持明文/密文切换
- 彻底移除 Keychain 弹窗

## [v5.1.3] — 2026-07-17

### Fixed
- 改用 Accessibility API 获取选中文本，彻底解决划词翻译失败问题
- 修复划词翻译 Cmd+C 模拟失败
- 修复 Keychain 授权弹窗：添加 `kSecAttrAccessibleAfterFirstUnlock`
- 修复划词翻译两个 bug
- 修复划词翻译弹窗定位：右侧阅读时弹窗自动移到左侧

## [v5.1.2] — 2026-07-16

### Added
- 添加贡献指南（CONTRIBUTING.md）
- 添加反馈入口
- 添加演示动图到 README

### Security
- 完成剩余全部安全加固
- 安全性加固与稳定性修复

### Changed
- 使用文档描述改为"划词/截图翻译工具"
- 精选反馈列表对用户邮箱脱敏显示，保护隐私

### Fixed
- 清理 API 调试堆栈输出
- API 500 错误返回堆栈方便定位
- API 手动解析 JSON body + 环境变量校验
- 修复 Vercel 构建路径问题

## [v5.1.1] — 2026-07-15

### Added
- 用户反馈系统上线

### Fixed
- 反馈页提交按钮修复 + 新增删除截图功能

### Changed
- 首页副标题改为「英语精读翻译助手（划词/截图）」
- 使用文档 4 项优化
- 安装说明新增第 5 条指引
- DMG 文件名加入版本号
- 版本号更新至 v5.1

## [v5.1.0] — 2026-07-14

### Added
- 新增划词翻译功能：选中文本 + `⇧⌘T` 直接翻译

### Changed
- 文档新增 macOS 15 (Sequoia) 安全提示的终端解决方案

## [v5.0.0] — 2026-07-13

### Added
- ELTA 首个正式版本发布
- 截图翻译：`Cmd+T` 框选 → OCR → AI 翻译
- 支持 OpenAI、Google Gemini、DeepSeek、Anthropic 多个 AI 后端
- 自定义翻译模板
- 本地 OCR（Apple Vision）
- macOS Keychain API Key 安全存储
- 菜单栏常驻
- 全局快捷键
- 支持 Intel + Apple Silicon
