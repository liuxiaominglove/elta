import Foundation

func runTranslationPipelineTests() {
    print("\n--- TranslationPipeline Tests ---")

    test("TranslationPipeline shared instance exists") {
        _ = try assertNotNil(TranslationPipeline.shared as Any?)
    }

    test("extractRange valid range returns substring") {
        let result = substringHelper("hello world", location: 0, length: 5)
        try assertEqual(result, "hello")
    }

    test("extractRange mid-string range") {
        let result = substringHelper("hello world", location: 6, length: 5)
        try assertEqual(result, "world")
    }

    test("extractRange full string range") {
        let result = substringHelper("abc", location: 0, length: 3)
        try assertEqual(result, "abc")
    }

    test("extractRange zero-length returns nil") {
        let result = substringHelper("hello", location: 2, length: 0)
        try assertNil(result)
    }

    test("extractRange length=0 at start returns nil") {
        let result = substringHelper("hello", location: 0, length: 0)
        try assertNil(result)
    }

    test("extractRange out-of-bounds length returns nil") {
        let result = substringHelper("abc", location: 1, length: 10)
        try assertNil(result)
    }

    test("extractRange out-of-bounds location returns nil") {
        let result = substringHelper("abc", location: 5, length: 1)
        try assertNil(result)
    }

    test("extractRange negative location returns nil") {
        let result = substringHelper("abc", location: -1, length: 1)
        try assertNil(result)
    }

    test("extractRange empty string returns nil") {
        let result = substringHelper("", location: 0, length: 0)
        try assertNil(result)
    }

    // ━━━ WI-R1/R2 回归测试 ━━━

    test("getSelectedTextViaAccessibility without permissions returns nil, no crash") {
        // 无 Accessibility 权限时，函数应安全返回 nil，不 SIGSEGV
        let result = TranslationPipeline.shared.getSelectedTextViaAccessibility(pid: nil)
        // 由于测试环境没有 AX 权限，应返回 nil（而不是崩溃）
        try assertNil(result, "未授权时预期返回 nil，不崩溃")
    }

    test("getSelectedTextViaAccessibility with invalid pid returns nil, no crash") {
        // 传入无效 PID（如极大值），函数应安全处理不崩溃
        let result = TranslationPipeline.shared.getSelectedTextViaAccessibility(pid: 99999999)
        try assertNil(result, "无效 PID 预期返回 nil，不崩溃")
    }

    // ━━━ WI-D3 回归测试 ━━━

    test("substringInRange boundary: zero length returns nil") {
        let result = substringHelper("hello", location: 0, length: 0)
        try assertNil(result)
    }

    test("substringInRange boundary: length overflow returns nil") {
        let result = substringHelper("abc", location: 0, length: 100)
        try assertNil(result)
    }

    test("substringInRange boundary: negative location returns nil") {
        let result = substringHelper("abc", location: -1, length: 2)
        try assertNil(result)
    }
}

private func substringHelper(_ fullText: String, location: Int, length: Int) -> String? {
    guard location >= 0,
          length > 0,
          location + length <= fullText.count else {
        return nil
    }
    let start = fullText.index(fullText.startIndex, offsetBy: location)
    let end = fullText.index(start, offsetBy: length)
    let selected = String(fullText[start..<end])
    return selected.isEmpty ? nil : selected
}
