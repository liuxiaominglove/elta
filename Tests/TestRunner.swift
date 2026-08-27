import Foundation

// MARK: - 简易测试框架

var totalTests = 0
var passedTests = 0
var failedTests = 0

func test(_ name: String, _ block: () throws -> Void) {
    totalTests += 1
    do {
        try block()
        passedTests += 1
    } catch {
        failedTests += 1
        print("  FAIL: \(name)")
        print("    Reason: \(failureMessage(error))")
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
    init(_ msg: String) { self.message = msg }
}

/// 把任意 error 转成可展示的失败信息；非 TestFailure 也保留原始描述，而非笼统的 "unknown error"
func failureMessage(_ error: Error) -> String {
    return (error as? TestFailure)?.message ?? String(describing: error)
}

func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) throws {
    if lhs != rhs { throw TestFailure("Expected \(rhs), got \(lhs) (\(file):\(line))") }
}

func assertTrue(_ condition: Bool, _ msg: String = "Expected true", file: StaticString = #file, line: UInt = #line) throws {
    if !condition { throw TestFailure("\(msg) (\(file):\(line))") }
}

func assertFalse(_ condition: Bool, _ msg: String = "Expected false", file: StaticString = #file, line: UInt = #line) throws {
    if condition { throw TestFailure("\(msg) (\(file):\(line))") }
}

func assertNotNil<T>(_ value: T?, _ msg: String = "Expected non-nil", file: StaticString = #file, line: UInt = #line) throws -> T {
    guard let v = value else { throw TestFailure("\(msg) (\(file):\(line))") }
    return v
}

func assertNil<T>(_ value: T?, _ msg: String = "Expected nil", file: StaticString = #file, line: UInt = #line) throws {
    if value != nil { throw TestFailure("\(msg) (\(file):\(line))") }
}

func runAllTests() -> Int32 {
    print("========== ELTA Unit Tests ==========\n")

    // 隔离真实 Keychain：测试只读写测试专用 service，避免覆盖/删除用户真实 API Key，也避免跨身份钥匙串弹窗
    KeychainHelper.service = "com.elta.snaptranslate.test"

    runAIProviderTests()
    runHotkeyHelpersTests()
    runSettingsManagerTests()
    runSettingsWindowControllerTests()
    runTextPreprocessorTests()
    runTextNormalizerTests()
    runTableExtractorTests()
    runBuildScriptTests()
    runHTMLRendererTests()
    runSettingsManagerThreadSafetyTests()
    runTranslationEngineTests()
    runTranslationPipelineTests()
    runPasteboardSnapshotTests()
    runSentenceSplitterTests()
    runUpdateCheckerTests()
    runTestRunnerTests()

    print("\n========== Results ==========")
    print("Total: \(totalTests) | Passed: \(passedTests) | Failed: \(failedTests)")

    if failedTests == 0 {
        print("All tests passed! 🎉")
        return 0
    } else {
        print("\(failedTests) test(s) failed.")
        return 1
    }
}
