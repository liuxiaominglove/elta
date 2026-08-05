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

## Permissions

The app requires macOS **Screen Recording** and **Accessibility** permissions (TCC). These are requested at first use in `TranslationPipeline.primePermissionsIfNeeded()`. Both must be granted for all features to work.
