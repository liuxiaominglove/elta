# Changelog

All notable changes to ELTA will be documented in this file.

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
