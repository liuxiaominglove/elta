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
| `website/` | Vercel static site + serverless functions (`api/`) |
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
