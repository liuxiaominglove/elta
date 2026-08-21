import Foundation

func runTestRunnerTests() {
    print("\n--- TestRunner Tests ---")

    test("failureMessage preserves TestFailure message") {
        try assertEqual(failureMessage(TestFailure("boom")), "boom")
    }

    test("failureMessage preserves non-TestFailure error description") {
        struct DemoError: Error, CustomStringConvertible {
            var description: String { "demo-boom" }
        }
        try assertEqual(failureMessage(DemoError()), "demo-boom")
    }

    test("assertEqual failure message includes source location") {
        do {
            try assertEqual(1, 2)
            throw TestFailure("expected assertEqual to throw")
        } catch let e as TestFailure {
            try assertTrue(e.message.contains(":"), "failure message should include file:line, got: \(e.message)")
        }
    }
}
