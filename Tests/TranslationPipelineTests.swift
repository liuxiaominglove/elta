import Foundation

func runTranslationPipelineTests() {
    print("\n--- TranslationPipeline Tests ---")

    test("TranslationPipeline shared instance exists") {
        _ = try assertNotNil(TranslationPipeline.shared as Any?)
    }

    test("extractRange valid range returns substring") {
        let result = TranslationPipeline.substringInRange("hello world", cfLocation: 0, cfLength: 5)
        try assertEqual(result, "hello")
    }

    test("extractRange mid-string range") {
        let result = TranslationPipeline.substringInRange("hello world", cfLocation: 6, cfLength: 5)
        try assertEqual(result, "world")
    }

    test("extractRange full string range") {
        let result = TranslationPipeline.substringInRange("abc", cfLocation: 0, cfLength: 3)
        try assertEqual(result, "abc")
    }

    test("extractRange zero-length returns nil") {
        let result = TranslationPipeline.substringInRange("hello", cfLocation: 2, cfLength: 0)
        try assertNil(result)
    }

    test("extractRange length=0 at start returns nil") {
        let result = TranslationPipeline.substringInRange("hello", cfLocation: 0, cfLength: 0)
        try assertNil(result)
    }

    test("extractRange out-of-bounds length returns nil") {
        let result = TranslationPipeline.substringInRange("abc", cfLocation: 1, cfLength: 10)
        try assertNil(result)
    }

    test("extractRange out-of-bounds location returns nil") {
        let result = TranslationPipeline.substringInRange("abc", cfLocation: 5, cfLength: 1)
        try assertNil(result)
    }

    test("extractRange negative location returns nil") {
        let result = TranslationPipeline.substringInRange("abc", cfLocation: -1, cfLength: 1)
        try assertNil(result)
    }

    test("extractRange empty string returns nil") {
        let result = TranslationPipeline.substringInRange("", cfLocation: 0, cfLength: 0)
        try assertNil(result)
    }

    // ━━━ WI-R1/R2 回归测试 ━━━

    test("getSelectedTextViaAccessibility without permissions returns nil, no crash") {
        // 无 Accessibility 权限时，函数应安全返回 nil，不 SIGSEGV
        let result = TranslationPipeline.shared.getSelectedTextViaAccessibility(pid: nil)
        // 由于测试环境没有 AX 权限，应返回 nil（而不是崩溃）
        try assertNil(result, "未授权时预期返回 nil，不崩溃")
    }

    test("getSelectedTextViaAccessibility with invalid pid does not crash") {
        // 传入无效 PID（如极大值）时，实现会回退系统全局聚焦元素；AX 已授权时可能返回非 nil 文本。
        // 此处只验证「不崩溃」（SIGSEGV 会直接杀死测试进程），不断言返回值。
        _ = TranslationPipeline.shared.getSelectedTextViaAccessibility(pid: 99999999)
    }

    // ━━━ WI-D3 回归测试 ━━━

    test("substringInRange boundary: zero length returns nil") {
        let result = TranslationPipeline.substringInRange("hello", cfLocation: 0, cfLength: 0)
        try assertNil(result)
    }

    test("substringInRange boundary: length overflow returns nil") {
        let result = TranslationPipeline.substringInRange("abc", cfLocation: 0, cfLength: 100)
        try assertNil(result)
    }

    test("substringInRange boundary: negative location returns nil") {
        let result = TranslationPipeline.substringInRange("abc", cfLocation: -1, cfLength: 2)
        try assertNil(result)
    }

    // ━━━ 审计修复：CFRange 用 UTF-16 偏移（emoji/生僻字不偏移错）━━━━

    test("substringInRange uses UTF-16 offsets (emoji surrogate pair)") {
        // "a😀b": UTF-16 单元 [a][😀高][😀低][b] = 4 单元；CFRange(1,2) 应返回 "😀"
        let s = TranslationPipeline.substringInRange("a😀b", cfLocation: 1, cfLength: 2)
        try assertEqual(s, "😀")
    }

    test("substringInRange bounds use UTF-16 length (not grapheme count)") {
        // "😀a": UTF-16 单元 3（😀=2 + a=1），grapheme 2；CFRange(2,1) 应返回 "a"
        let s = TranslationPipeline.substringInRange("😀a", cfLocation: 2, cfLength: 1)
        try assertEqual(s, "a")
    }

    // ━━━ 权限决策：拆分截图/划词各自的 TCC 弹窗 ━━━

    test("permission decision: granted always proceeds (regardless of primed)") {
        try assertEqual(TranslationPipeline.resolvePermissionAction(isGranted: true, wasPrimed: false), .proceed)
        try assertEqual(TranslationPipeline.resolvePermissionAction(isGranted: true, wasPrimed: true), .proceed)
    }

    test("permission decision: not granted, first trigger → primeAndAbort") {
        try assertEqual(TranslationPipeline.resolvePermissionAction(isGranted: false, wasPrimed: false), .primeAndAbort)
    }

    test("permission decision: not granted, already primed → guideAndAbort") {
        try assertEqual(TranslationPipeline.resolvePermissionAction(isGranted: false, wasPrimed: true), .guideAndAbort)
    }
}
