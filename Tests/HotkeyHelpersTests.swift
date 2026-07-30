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
}
