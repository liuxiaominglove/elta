# AGENTS.md

## Build & Test

```bash
./build.sh          # Compile Universal Binary, package .app, optionally install to /Applications
./run_tests.sh      # Compile + run unit tests (custom framework, not XCTest)
```

- **No Xcode project.** Everything uses `swiftc` directly. Never try `xcodebuild` or `swift test`.
- `build.sh` compiles `Sources/*.swift` (wildcard). Adding a new source file is automatic for the build.
- `run_tests.sh` explicitly lists each source and test file. Adding a source file that tests depend on requires updating the `SRC_FILES` array in this script.

## Architecture

Single-binary macOS menu bar app. Entrypoint: `Sources/main.swift` → `AppDelegate`.

| Directory | Purpose |
|-----------|---------|
| `Sources/` | macOS app (16 Swift files, flat structure) |
| `Tests/` | Custom mini test framework (`TestRunner.swift`) + test suites |
| `Resources/` | `Info.plist`, `AppIcon.icns` |
| `website/` | 官网（静态站，双部署：腾讯云主站 + Vercel 备用，见「部署」节） |
| `build/` | Build output (gitignored) |

Key modules: `AppDelegate` (lifecycle + hotkey registration), `StatusBarController` (menu bar UI), `TranslationPipeline` (screenshot/OCR/translate orchestration), `SettingsManager` (UserDefaults-based config), `OCREngine` (Apple Vision).

## Conventions

- **Logging**: use `logi("message")` helper, not `print()` or `os_log`.
- **Frontend**: vanilla HTML/CSS/JS. No frameworks or build steps.
- **Version**: read from `Resources/Info.plist` at build/bundle time. Single source of truth.
- **Icons**: `gen_icon.swift` generates `AppIcon.icns` from a source PNG, but contains a hardcoded absolute path — update it before running.

## CI

- GitHub Actions on `macos-14`, triggered by `v*` tags or manual dispatch.
- Builds Universal Binary → packages `.app` → creates DMG via `create-dmg` → uploads to release.

## Security

**API Key / Secret 调试纪律。** 以下命令**禁止**无过滤输出：

```bash
# ❌ 禁止 — 会打印完整 Key 值到对话日志
defaults read com.elta.app
security find-generic-password -s "com.elta.snaptranslate"
defaults read com.elta.app | grep apikey

# ✅ 正确 — 只确认存在与否，不泄露值
defaults read com.elta.app | grep -c apikey
security find-generic-password -s "com.elta.snaptranslate" -w >/dev/null 2>&1 && echo "exists" || echo "missing"
```

- 代码中使用 `logi("len=\(key.count)")` 输出长度，已正确处理。不新增输出 Key 明文的日志。
- 测试中存储测试 Key 后必须在 cleanup 中删除（`setApiKey(nil)`）。
- `.env`、`ghp_*` token、`sk-*` key 不得写入文件、commit、或在对话中完整打印。
- 如不慎暴露 Key，立即提醒用户去对应平台重置。

The app requires macOS **Screen Recording** and **Accessibility** permissions (TCC). These are requested at first use in `TranslationPipeline.primePermissionsIfNeeded()`. Both must be granted for all features to work.

## Swift & CF 安全规则

> **元规则（最高优先级，先于下面所有规则）**：规则必须基于实测/验证过的因果，而非"崩溃代码里刚好有它"的相关性。写任何技术规则前先自问三件事：① 这个因果验证过吗（跑过最小复现确认"因为 A 所以 B"，而不是只看到"A 和 B 同时出现"就归因）？② 能全局适用吗（是不是把本项目的特定场景坑拔高成了普适规律）？③ 会不会误导未来的开发者（禁止某 API 前，先查官方文档确认它是否本来就安全推荐）。——反例（已发生）：把剪贴板 `writeObjects` 崩溃误归因于 `CFGetTypeID`，进而写下"CFGetTypeID 一律禁止"，后经官方文档 + 实测证伪。

### 规则 1：AX API 的 CFTypeRef 类型转换（macOS 特定）

范围限定：只针对 macOS **AX（Accessibility）API** 场景（`AXUIElementCopyAttributeValue` 返回 `CFTypeRef?` 时）。**不适用于**其他 CF 类型（CGImage、SecKey 等）或 NSObject 子类的向下转型。

实测事实：
1. `AXUIElementCopyAttributeValue` 返回 `CFTypeRef?`（桥接为 `AnyObject?`），需转成具体类型。
2. `as? AXUIElement` → 编译器报 **error** "conditional downcast will always succeed"。编译器 note 建议改用 CFTypeID 比较。
3. `CFGetTypeID(obj)` 对有效 CF 对象**完全安全**，返回正确 typeID（实测，无崩溃）。
4. `as! AXUIElement` 做无条件 cast，不做类型检查，不因"类型不匹配"崩溃（仅当对象为 nil 时才崩，需先 guard 非 nil）。

ELTA 的选择：当 AX API 契约明确承诺返回类型时，用 `as!` 最简洁。**但这不代表其他做法是错的**：`CFGetTypeID` 是官方推荐的类型判断方式，在"返回类型不确定"的场景它是正确选择。⚠️ 曾错误地写"CFGetTypeID 一律禁止"（基于误诊），已证伪——**SIGSEGV 真正来源是无效指针/悬垂引用，与 CFGetTypeID 无关**。

### 规则 2：同步/异步语义转换

改同步函数为异步前，**必须**：① `grep` 找到所有调用方（含 C 回调、事件处理器、通知观察者）② 逐一确认调用方不依赖同步返回（不依赖返回后状态已变更、不依赖返回值做后续判断）。以下场景**不可**改为异步：Carbon `EventHotKey` 回调、`CGEventTap` 回调、`NSEvent` 本地/全局 monitor 回调、`NSApplicationDelegate` 生命周期方法内直接调用的路径。如需让事件循环不冻住但保持同步语义，用 `RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: delay))` 替代 `usleep`。

### 规则 3：NSScrollView 视图层级

当使用 `NSScrollView` 的 `documentView` 时：`documentView.superview` 返回 **`NSClipView`**，不是 `NSScrollView`；`(documentView.superview as? NSScrollView)` **永远为 nil**。要获取 scrollView 用 `documentView.enclosingScrollView` 或 `documentView.superview?.superview as? NSScrollView`。

### 规则 4：swiftc 编译参数一致性

本项目用 `swiftc` 直接编译（非 Xcode project）：`run_tests.sh` 与 `build.sh` 必须用**相同的** `-target` 参数（当前 `macosx13.0`）；`run_tests.sh` 的 `SRC_FILES` 数组需包含被测模块的所有传递依赖源文件；`build.sh` 有 `-framework Xxx` 时测试脚本同样需要。

### 规则 5：修复前必须读懂调用链与数据流

以下回归都源于"没读懂上下文就动手"：改同步为 `asyncAfter` → 引入 race（没检查调用方是否依赖同步返回）；"恢复剪贴板"改用 `writeObjects(旧对象)` → 引入 NSException（`pasteboardItems` 是懒加载引用，`clearContents` 后失效）；移按钮改 TabView 高度 → 布局重叠；误诊崩溃根因（writeObjects 崩溃归因 CFGetTypeID）→ 写出错误规则。**动手改代码前，必须依次确认**：① 这个函数被谁调用（`grep` 所有调用点）② 读写哪些共享状态（剪贴板/Keychain/UserDefaults/全局单例/静态变量）③ 这些状态的生命周期（何时失效、是否懒加载、是否跨线程共享）④ 改动影响哪些"看起来无关"的东西。核心一句话：**修一个 bug 前，先证明自己理解了 bug 周边的完整上下文，再动手。**

## 部署（双部署：腾讯云主站 + Vercel 备用）

官网是**两套独立部署**，`git push` 只会更新 Vercel 备用站。腾讯云主站由**服务器 cron 每 5 分钟自动同步**（见下），**改完 `website/` 后 `git push` 即可，无需手动部署**。

| 项目 | 平台 | 地址 | 更新方式 |
|------|------|------|---------|
| **主站** | 腾讯云服务器（nginx） | `autoelta.com`（IP `106.53.167.38`，SSH 用户 `root`，密钥已配置 `~/.ssh/id_ed25519`） | 服务器 cron 自动同步（≤5 分钟延迟） |
| 备用 | Vercel | `elta-seven.vercel.app` | 从 GitHub `main` 自动部署 |

- **DNS**：DNSPod，当前域名指向腾讯云（未切 Vercel）。
- **策略**：腾讯云为主站，Vercel 备用。备案风险：Vercel 是海外服务商，切过去可能被抽查注销备案，故**保持腾讯云为主站**。

### 主站自动同步（服务器 cron）

服务器上 `crontab` 每 5 分钟跑 `/root/auto-sync.sh`，做两件事：

1. `/root/sync-elta-release.sh` — 拉取 GitHub 最新 release 的 `.dmg` 到 `/var/www/elta-downloads/`，更新 `latest.dmg` 软链（国内直链）
2. 检查 `/opt/elta-repo` 的 `origin/main` 是否有新 commit，有则跑 `/root/update-elta-website.sh` 部署网站

所以 `git push` 后 ≤5 分钟，主站与国内直链自动更新。日志：`/var/log/elta-release-sync.log`、`/var/log/elta-auto-sync.log`。

### 手动更新主站（兜底，一般用不到）

```bash
ssh root@106.53.167.38 '/root/update-elta-website.sh'
```

回滚：`ssh root@106.53.167.38 '/root/rollback-elta-website.sh'`（交互式选备份）

### 服务器关键路径

| 用途 | 路径 |
|------|------|
| 网站文件 | `/var/www/elta-website/` |
| DMG 下载目录 | `/var/www/elta-downloads/`（独立于网站目录，`rsync --delete` 不碰；nginx `location /download/` alias 到此） |
| 自动同步脚本 | `/root/auto-sync.sh`（cron 入口）、`/root/sync-elta-release.sh`（拉取 DMG） |
| 备份 | `/var/backups/` |
| 代码仓库 | `/opt/elta-repo/`（sparse checkout） |
| 部署日志 | `/var/log/elta-deploy.log` |

### 部署脚本内部步骤（`/root/update-elta-website.sh`）

1. 预发布备份 → `/var/backups/elta-website-时间戳.tar.gz`
2. `git pull origin main`（在 `/opt/elta-repo/`，60s 超时，`http.lowSpeedLimit=1000`）
3. `rsync -av --delete` 同步到 `/var/www/elta-website/`
4. 域名本地化：`sed 's|elta-seven\.vercel\.app|autoelta.com|g'`
5. 恢复百度验证文件 `baidu_verify_codeva-5FripuB9n4.html`
6. 删除敏感/无用文件：`vercel.json`、`admin.html`、`api/admin.js`
7. 隐藏反馈区：`feedback.html` 的 `featured-feedback` 注入 `display:none`
8. `nginx -t` 校验 + `systemctl reload nginx`（失败熔断）
9. 清理备份：只保留最近 5 个
10. commit hash 写入 `/var/log/elta-deploy.log`

### 其他备注

- `website/api/admin.js` 的 `ALLOWED_ORIGIN_HOSTS` 同时认 `autoelta.com` 与 `elta-seven.vercel.app`。
- **DMG 国内直链**：`https://autoelta.com/download/latest.dmg` 指向 `/var/www/elta-downloads/latest.dmg` 软链，由服务器 cron 自动从 GitHub release 拉取，无需手动上传、无需改官网版本号。
- 版本发布是完整流程：改 `Resources/Info.plist` 版本 + `CHANGELOG.md` + 官网文案/版本号 + `git tag vX.Y.Z` 并推送（触发 GitHub Actions 构建 DMG 发 release）。推送后主站与国内直链由服务器 cron 自动更新（≤5 分钟），**只需 `git push --tags`，其余全自动**。
