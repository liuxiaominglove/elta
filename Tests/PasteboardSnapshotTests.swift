import Cocoa

func runPasteboardSnapshotTests() {
    print("\n--- PasteboardSnapshot Tests ---")

    func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("test.snapshot.\(UUID().uuidString)"))
    }

    test("capture empty pasteboard returns empty snapshot") {
        let pb = makePasteboard()
        pb.clearContents()
        let snapshot = PasteboardSnapshot.capture(from: pb)
        try assertEqual(snapshot.items.count, 0)
    }

    test("capture plain text stores string data") {
        let pb = makePasteboard()
        pb.clearContents()
        pb.setString("hello", forType: .string)
        let snapshot = PasteboardSnapshot.capture(from: pb)
        try assertEqual(snapshot.items.count, 1)
        let types = snapshot.items[0].types
        try assertEqual(types.count, 1)
        try assertEqual(types[0].type, .string)
        try assertEqual(types[0].data, Data("hello".utf8))
    }

    test("restore plain text round-trips") {
        let src = makePasteboard()
        src.clearContents()
        src.setString("hello", forType: .string)
        let snapshot = PasteboardSnapshot.capture(from: src)

        let dst = makePasteboard()
        dst.clearContents()
        let ok = snapshot.restore(to: dst)
        try assertTrue(ok)
        try assertEqual(dst.string(forType: .string), "hello")
    }

    test("restore preserves multiple types") {
        let src = makePasteboard()
        src.clearContents()
        let item = NSPasteboardItem()
        item.setString("text content", forType: .string)
        item.setData(Data([0x89, 0x50, 0x4E, 0x47]), forType: .png)
        item.setString("file:///tmp/test.txt", forType: .fileURL)
        src.writeObjects([item])

        let snapshot = PasteboardSnapshot.capture(from: src)
        let dst = makePasteboard()
        dst.clearContents()
        let ok = snapshot.restore(to: dst)
        try assertTrue(ok)

        try assertEqual(dst.string(forType: .string), "text content")
        try assertEqual(dst.data(forType: .png), Data([0x89, 0x50, 0x4E, 0x47]))
        try assertEqual(dst.string(forType: .fileURL), "file:///tmp/test.txt")
    }

    test("restore after source cleared (deep copy independence)") {
        let src = makePasteboard()
        src.clearContents()
        src.setString("preserve me", forType: .string)
        let snapshot = PasteboardSnapshot.capture(from: src)

        // 清空源剪贴板，模拟 Cmd+C 后的场景
        src.clearContents()

        let dst = makePasteboard()
        dst.clearContents()
        let ok = snapshot.restore(to: dst)
        try assertTrue(ok)
        try assertEqual(dst.string(forType: .string), "preserve me")
    }

    test("empty snapshot restore clears pasteboard to empty state") {
        let pb = makePasteboard()
        pb.clearContents()
        let snapshot = PasteboardSnapshot.capture(from: pb)  // 空快照

        let dst = makePasteboard()
        dst.clearContents()
        dst.setString("existing", forType: .string)
        let ok = snapshot.restore(to: dst)
        try assertTrue(ok)
        // 空快照恢复成空状态：目标剪贴板被清空（清除 Cmd+C 残留的选中文本）
        try assertNil(dst.string(forType: .string) as Any?)
    }
}
