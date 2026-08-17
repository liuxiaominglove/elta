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

## TDD 与安全修复纪律

以下规则来自真实踩坑经验，适用于本项目和全局：

### ⚠️ CFTypeRef 强制转换规则

- ❌ **禁止** `CFGetTypeID(xxx) == AXUIElementGetTypeID()` 作类型判断——会 SIGSEGV
- ❌ **禁止** `as? AXUIElement`——编译器 warning "will always succeed" 是误报，实际走的是 CF 桥接，不检查 typeID
- ✅ **正确**：信任 AX API 契约，`as! AXUIElement` 直接强制转换。AX API 返回的对象契约上是 AXUIElement 类型。**编译通过即可，不要为消除 warning 引入更危险的代码。**

### ⚠️ 同步/异步转换规则

- **改同步函数为异步前，必须先 grep 所有调用方**，确认调用方不依赖同步返回语义
- 热键处理器、C 回调函数中的同步函数**不可**改成异步
- 如需减少主线程阻塞，用 `RunLoop.current.run(mode: .default, before: Date(...))` 代替 `usleep`

### ⚠️ NSScrollView documentView 遍历规则

- `documentView.superview` 返回 `NSClipView`，**不是** `NSScrollView`
- 要获取 scrollView 必须用 `enclosingScrollView` 或 `superview?.superview`

### ⚠️ Swift 编译配置

- `run_tests.sh` 需要和 `build.sh` **同样的** `-target` 参数（当前：`macosx13.0`）
- 新增源文件依赖时，`run_tests.sh` 的 `SRC_FILES` 数组需要同步更新

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
