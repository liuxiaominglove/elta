import Foundation

// MARK: - Build Script & Info.plist Unit Tests

func runBuildScriptTests() {
    let projectDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .path
    let plistPath = projectDir + "/Resources/Info.plist"

    // === A1: Info.plist bundle ID consistency ===
    test("Info.plist has correct CFBundleIdentifier") {
        let plist = try assertNotNil(NSDictionary(contentsOfFile: plistPath), "Info.plist not found")
        let bundleId = try assertNotNil(plist["CFBundleIdentifier"] as? String, "Missing CFBundleIdentifier")
        try assertEqual(bundleId, "com.elta.app")
    }

    test("Info.plist has CFBundleExecutable") {
        let plist = try assertNotNil(NSDictionary(contentsOfFile: plistPath), "Info.plist not found")
        let executable = try assertNotNil(plist["CFBundleExecutable"] as? String, "Missing CFBundleExecutable")
        try assertEqual(executable, "ELTA")
    }

    test("Info.plist has LSUIElement set to true (menu bar app)") {
        let plist = try assertNotNil(NSDictionary(contentsOfFile: plistPath), "Info.plist not found")
        let isAgent = try assertNotNil(plist["LSUIElement"] as? Bool, "Missing LSUIElement")
        try assertTrue(isAgent, "LSUIElement should be true")
    }
}
