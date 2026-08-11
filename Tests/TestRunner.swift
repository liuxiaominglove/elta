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
        let err = error as? TestFailure ?? TestFailure("unknown error")
        print("  FAIL: \(name)")
        print("    Reason: \(err.message)")
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
    init(_ msg: String) { self.message = msg }
}

func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) throws {
    if lhs != rhs { throw TestFailure("Expected \(rhs), got \(lhs)") }
}

func assertTrue(_ condition: Bool, _ msg: String = "Expected true") throws {
    if !condition { throw TestFailure(msg) }
}

func assertFalse(_ condition: Bool, _ msg: String = "Expected false") throws {
    if condition { throw TestFailure(msg) }
}

func assertNotNil<T>(_ value: T?, _ msg: String = "Expected non-nil") throws -> T {
    guard let v = value else { throw TestFailure(msg) }
    return v
}

func assertNil(_ value: Any?, _ msg: String = "Expected nil") throws {
    if value != nil { throw TestFailure(msg) }
}

func runAllTests() -> Int32 {
    print("========== ELTA Unit Tests ==========\n")

    runAIProviderTests()
    runHotkeyHelpersTests()
    runSettingsManagerTests()
    runTextPreprocessorTests()

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
