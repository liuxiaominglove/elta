import Cocoa
import Carbon
import Foundation

func runSettingsManagerThreadSafetyTests() {
    print("\n--- SettingsManager Thread Safety Tests ---")

    test("concurrent reads do not crash") {
        let sm = SettingsManager.shared
        let group = DispatchGroup()
        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                _ = sm.apiProvider
                _ = sm.activeApiKey
                _ = sm.hotkeyKeyCode
                _ = sm.hotkeyModifiers
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 5)
    }

    test("concurrent apiProvider get/set is consistent") {
        let sm = SettingsManager.shared
        let orig = sm.apiProvider
        sm.apiProvider = .deepseek

        let group = DispatchGroup()
        var readValues: [AIProvider] = []
        let lock = NSLock()

        for _ in 0..<50 {
            group.enter()
            DispatchQueue.global().async {
                let val = sm.apiProvider
                lock.lock()
                readValues.append(val)
                lock.unlock()
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 5)

        let allValid = readValues.allSatisfy { $0 == .deepseek }
        try assertTrue(allValid, "All reads should see consistent value")

        sm.apiProvider = orig
    }

    test("concurrent hotkey reads are consistent") {
        let sm = SettingsManager.shared
        let orig = sm.hotkeyKeyCode

        let group = DispatchGroup()
        var readValues: [Int] = []
        let lock = NSLock()

        for _ in 0..<20 {
            group.enter()
            DispatchQueue.global().async {
                let val = sm.hotkeyKeyCode
                lock.lock()
                readValues.append(val)
                lock.unlock()
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 5)

        let allSame = readValues.allSatisfy { $0 == readValues.first }
        try assertTrue(allSame, "All concurrent reads should return same value")

        sm.hotkeyKeyCode = orig
    }

    test("activeApiKey is consistent during concurrent access") {
        let sm = SettingsManager.shared
        sm.apiProvider = .deepseek
        sm.setApiKey("concurrency-test-key", for: .deepseek)

        let group = DispatchGroup()
        for _ in 0..<20 {
            group.enter()
            DispatchQueue.global().async {
                _ = sm.activeApiKey
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 5)

        let finalKey = sm.activeApiKey
        try assertEqual(finalKey, "concurrency-test-key")

        sm.setApiKey(nil, for: .deepseek)
    }
}
