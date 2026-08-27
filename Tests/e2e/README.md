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
