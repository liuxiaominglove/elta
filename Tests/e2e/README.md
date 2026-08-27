# E2E tests — ELTA

Drive the real ELTA app and assert its window behavior. `lib/` is a symlink to
the shared harness in `~/project/it-guy-pro/tests/e2e/lib/` (do not copy).

## Prerequisites

- ELTA built and installed at `/Applications/ELTA.app` (`build.sh`).
- Accessibility permission for the host terminal (iTerm). Without it, opening
  the settings window via the menu bar fails with `不允许发送按键 (1002)`.
- No Screen Recording permission is needed: window z-order is read by
  `kCGWindowOwnerName` (owner name), not window titles.

## Run

```bash
./run.sh                 # run all cases
./run.sh --list          # list cases
./run.sh --case elta_settings_not_covering.js
```

Exit code 0 = pass. Screenshots land in `tests/e2e/shots/`.

## Side effects

The test quits and relaunches ELTA and Calculator to start from a known state.
If you are using ELTA, quit it before running, or expect it to restart.

## What it asserts

`elta_settings_not_covering.js` opens ELTA's settings window, activates
Calculator, then reads the on-screen window z-order via CGWindowList and asserts
the Calculator window is above the ELTA settings window (settings does not cover
other apps). It matches ELTA's settings by owner `ELTA` + layer 0, deliberately
excluding the floating translation panel (layer 3).

`elta_pasteboard_roundtrip.js` guards the pasteboard round-trip in the Cmd+C
fallback path (`getSelectedTextViaCopyPasteboard`): it seeds the pasteboard with
a unique marker, triggers 划词翻译 from the menu bar, then asserts the pasteboard
is still exactly the marker after the Cmd+C → restore cycle. It also asserts the
`剪贴板已恢复` log line appears in the log lines written during this run (not
historical ones), proving the Cmd+C fallback path was actually exercised rather
than skipped via the Accessibility path. To make that path deterministic, the
case activates Finder before triggering — Finder has no selected text, so the
Accessibility read fails and the fallback runs. It needs no API key and no
Screen Recording permission.

`elta_no_api_key_alert.js` guards the "no API key" degradation path: it switches
the provider to one without a key (dynamically picked, restored in `finally`),
selects text in TextEdit, triggers 划词翻译, then asserts the `未配置 API Key`
alert appears and that clicking `打开偏好设置` dismisses it. It needs no
real API key — it deliberately targets the empty-key state — but does need
TextEdit to stay frontmost when the translation is triggered (so the text
selection is set up after ELTA has launched and grabbed focus).

`elta_selection_golden_path.js` guards the 划词翻译 golden path: it picks a
provider that *has* a key (opposite of the no-key case), selects text in
TextEdit, triggers 划词翻译, then asserts the `翻译结果 — ELTA` panel appears
and that the `划词翻译流水线完成` log line appears in this run's new log lines
(proving the `.success` branch, not `.missingKey`). It needs a valid real API
key and makes one real translation call, so it is a slow, paid gate — run it
before release, not in the inner loop. It deliberately does not assert the
panel's inner text (that is WebView-rendered HTML and not reliably readable via
System Events).

## Case checklist（交卷六问）

写/改一个 case 收工前，逐条确认。这六条来自「测试绿了 ≠ 测到了」的假阳性/空过教训：

1. **绿是真测到了吗** — 跑完回日志确认「被测路径真的执行了」，不要只看 exit 0。
2. **断言锚定本次了吗** — 读有历史累积的状态（日志/剪贴板/文件）前记基线，只读增量。用 `fileLineCount` + `fileTailSince`（见 `lib/jxa/ui.js`），不要直接 `tail`/`grep` 全量。
3. **有路径证明吗** — 除结果断言外，必须有一条证明「中间环节真的发生」的断言，否则会静默空过。
4. **环境前置显式构造了吗** — 前置条件要主动造出来（如激活 Finder 让 AX 确定性读不到），不能靠环境碰巧。
5. **做过负向验证吗** — 临时改错一个断言（或注入一个 bug），确认测试会 fail，证明它非恒真。
6. **断言的是「状态转变」还是「状态存在」** — 若断言对象在动作发生前就存在（或本就不存在），说明没咬住因果，是恒真/假阴性风险。用 `assertAppears` / `assertDisappears`（见 `lib/jxa/ui.js`）断言「从无到有 / 从有到无」。

## Known limitation

The case cold-starts Calculator after ELTA's settings window is frontmost, and
asserts Calculator comes to the foreground. This currently **fails** by design:
ELTA's "hybrid" app configuration (LSUIElement + runtime `.regular` activation
policy + `NSStatusItem` + `activate(ignoringOtherApps: true)`) keeps ELTA
frontmost and blocks a cold-started app from taking focus. This is an accepted
edge case (see the related GitHub issue); the `.floating`-level bug that the test
was originally built to guard against is fixed in v5.5.3.

## Notes

- Window owner names are locale-dependent (`计算器` = Calculator on a zh-CN
  system). Adjust `calcOwner` in the case if your locale differs.
- The Swift z-order helper `lib/jxa/windowz` is compiled automatically from
  `windowz.swift` on first run.
