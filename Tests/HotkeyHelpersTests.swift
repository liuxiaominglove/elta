import Cocoa
import Carbon
import Foundation

func runHotkeyHelpersTests() {
    print("\n--- HotkeyHelpers Tests ---")

    test("cocoaToCarbonModifiers: command only") {
        let carbon = cocoaToCarbonModifiers(.command)
        try assertEqual(carbon, Int(cmdKey))
    }

    test("cocoaToCarbonModifiers: command+option") {
        let carbon = cocoaToCarbonModifiers([.command, .option])
        try assertEqual(carbon, Int(cmdKey | optionKey))
    }

    test("cocoaToCarbonModifiers: command+shift") {
        let carbon = cocoaToCarbonModifiers([.command, .shift])
        try assertEqual(carbon, Int(cmdKey | shiftKey))
    }

    test("cocoaToCarbonModifiers: control only") {
        let carbon = cocoaToCarbonModifiers(.control)
        try assertEqual(carbon, Int(controlKey))
    }

    test("cocoaToCarbonModifiers: no modifiers") {
        let carbon = cocoaToCarbonModifiers([])
        try assertEqual(carbon, 0)
    }

    test("cocoaToCarbonModifiers: all four modifiers") {
        let carbon = cocoaToCarbonModifiers([.command, .option, .control, .shift])
        try assertEqual(carbon, Int(cmdKey | optionKey | controlKey | shiftKey))
    }

    test("hotkeyHasRequiredModifiers: cmd only returns true") {
        try assertTrue(hotkeyHasRequiredModifiers(Int(cmdKey)))
    }

    test("hotkeyHasRequiredModifiers: option only returns true") {
        try assertTrue(hotkeyHasRequiredModifiers(Int(optionKey)))
    }

    test("hotkeyHasRequiredModifiers: no modifiers returns false") {
        try assertFalse(hotkeyHasRequiredModifiers(0))
    }

    test("checkSystemHotkeyConflict: ⌘Q detected") {
        _ = try assertNotNil(checkSystemHotkeyConflict(modifiers: Int(cmdKey), keyCode: 0x0C))
    }

    test("checkSystemHotkeyConflict: ⌘W detected") {
        _ = try assertNotNil(checkSystemHotkeyConflict(modifiers: Int(cmdKey), keyCode: 0x0D))
    }

    test("checkSystemHotkeyConflict: ⌘C detected") {
        _ = try assertNotNil(checkSystemHotkeyConflict(modifiers: Int(cmdKey), keyCode: 0x08))
    }

    test("checkSystemHotkeyConflict: ⌘V detected") {
        _ = try assertNotNil(checkSystemHotkeyConflict(modifiers: Int(cmdKey), keyCode: 0x09))
    }

    test("checkSystemHotkeyConflict: ⌘Tab detected") {
        _ = try assertNotNil(checkSystemHotkeyConflict(modifiers: Int(cmdKey), keyCode: 0x30))
    }

    test("checkSystemHotkeyConflict: ⌘Space detected") {
        _ = try assertNotNil(checkSystemHotkeyConflict(modifiers: Int(cmdKey), keyCode: 0x31))
    }

    test("checkSystemHotkeyConflict: ⇧⌘3 detected") {
        _ = try assertNotNil(checkSystemHotkeyConflict(modifiers: Int(cmdKey | shiftKey), keyCode: 0x14))
    }

    test("checkSystemHotkeyConflict: ⇧⌘4 detected") {
        _ = try assertNotNil(checkSystemHotkeyConflict(modifiers: Int(cmdKey | shiftKey), keyCode: 0x15))
    }

    test("checkSystemHotkeyConflict: no conflict for uncommon combo") {
        let conflict = checkSystemHotkeyConflict(modifiers: Int(cmdKey | optionKey), keyCode: 0x11) // ⌥⌘T
        try assertNil(conflict)
    }

    test("hotkeyDisplayString: ⌘T") {
        let display = hotkeyDisplayString(keyCode: 0x11, modifiers: Int(cmdKey))
        try assertEqual(display, "⌘T")
    }

    test("hotkeyDisplayString: ⌘⇧T") {
        let display = hotkeyDisplayString(keyCode: 0x11, modifiers: Int(cmdKey | shiftKey))
        try assertEqual(display, "⌘⇧T")
    }

    test("hotkeyDisplayString: ⌘A") {
        let display = hotkeyDisplayString(keyCode: 0x00, modifiers: Int(cmdKey))
        try assertEqual(display, "⌘A")
    }

    test("hotkeyDisplayString: ⌘⌥F") {
        let display = hotkeyDisplayString(keyCode: 0x03, modifiers: Int(cmdKey | optionKey))
        try assertEqual(display, "⌘⌥F")
    }

    test("hotkeyDisplayString: F1 with no modifiers") {
        let display = hotkeyDisplayString(keyCode: 0x7A, modifiers: 0)
        try assertEqual(display, "F1")
    }

    test("hotkeyDisplayString: ⌘F12") {
        let display = hotkeyDisplayString(keyCode: 0x6F, modifiers: Int(cmdKey))
        try assertEqual(display, "⌘F12")
    }

    // ━━━ 审计修复：负数/超大热键值不得让 UInt32 转换崩溃 ━━━

    test("sanitizeHotkeyCode: negative clamps to 0") {
        try assertEqual(sanitizeHotkeyCode(-1), 0)
        try assertEqual(sanitizeHotkeyCode(-100), 0)
    }

    test("sanitizeHotkeyCode: normal value passes through") {
        try assertEqual(sanitizeHotkeyCode(0x11), 0x11)
        try assertEqual(sanitizeHotkeyCode(0), 0)
    }

    test("sanitizeHotkeyCode: out-of-range clamps to UInt32.max") {
        try assertEqual(sanitizeHotkeyCode(Int.max), UInt32.max)
    }

    // ━━━ 审计修复：保存前收集「本次新录制热键」中命中已知系统快捷键冲突的项 ━━━

    test("collectHotkeyConflicts: detects Cmd+T conflict") {
        let conflicts = collectHotkeyConflicts([(keyCode: 0x11, modifiers: Int(cmdKey))])
        try assertEqual(conflicts.count, 1)
        try assertEqual(conflicts[0].display, "⌘T")
        try assertEqual(conflicts[0].reason, "⌘T 新建标签页")
    }

    test("collectHotkeyConflicts: empty array returns empty") {
        try assertEqual(collectHotkeyConflicts([]).count, 0)
    }

    test("collectHotkeyConflicts: nil keyCode (not recorded) is skipped") {
        let conflicts = collectHotkeyConflicts([(keyCode: nil, modifiers: Int(cmdKey))])
        try assertEqual(conflicts.count, 0)
    }

    test("collectHotkeyConflicts: no-conflict combo returns empty") {
        let conflicts = collectHotkeyConflicts([(keyCode: 0x11, modifiers: Int(cmdKey | optionKey))])
        try assertEqual(conflicts.count, 0)
    }

    test("collectHotkeyConflicts: mixed entries return only conflicts") {
        let conflicts = collectHotkeyConflicts([
            (keyCode: 0x11, modifiers: Int(cmdKey)),
            (keyCode: 0x11, modifiers: Int(cmdKey | optionKey)),
            (keyCode: nil, modifiers: 0),
        ])
        try assertEqual(conflicts.count, 1)
        try assertEqual(conflicts[0].display, "⌘T")
    }

    test("collectHotkeyConflicts: negative keyCode does not crash") {
        let conflicts = collectHotkeyConflicts([(keyCode: -1, modifiers: Int(cmdKey))])
        try assertEqual(conflicts.count, 0)
    }
}
