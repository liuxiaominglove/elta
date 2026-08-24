import Foundation

func runSettingsWindowControllerTests() {
    print("\n--- SettingsWindowController Tests ---")

    test("computeProviderCardLayout uses given model and key positions") {
        let model: CGFloat = 549
        let key: CGFloat = 415
        let layout = SettingsWindowController.computeProviderCardLayout(
            modelPopupY: model, keyFieldY: key, cardHeight: 666)
        try assertEqual(layout.modelPopupY, model)
        try assertEqual(layout.keyFieldY, key)
    }

    test("computeProviderCardLayout derives model title above model popup") {
        let layout = SettingsWindowController.computeProviderCardLayout(
            modelPopupY: 549, keyFieldY: 415, cardHeight: 666)
        try assertEqual(layout.modelTitleY, CGFloat(549 + 26 + 4))
    }

    test("computeProviderCardLayout derives key title above key field") {
        let layout = SettingsWindowController.computeProviderCardLayout(
            modelPopupY: 549, keyFieldY: 415, cardHeight: 666)
        try assertEqual(layout.keyTitleY, CGFloat(415 + 26 + 4))
    }

    test("computeProviderCardLayout places register label at card top") {
        let layout = SettingsWindowController.computeProviderCardLayout(
            modelPopupY: 549, keyFieldY: 415, cardHeight: 666)
        try assertEqual(layout.registerLabelY, CGFloat(666 - 8 - 18))
    }

    test("computeProviderCardLayout keeps test button below key field") {
        let layout = SettingsWindowController.computeProviderCardLayout(
            modelPopupY: 549, keyFieldY: 415, cardHeight: 666)
        try assertEqual(layout.testButtonY, CGFloat(415 - 38))
    }

    test("computeProviderCardLayout preserves vertical order") {
        let layout = SettingsWindowController.computeProviderCardLayout(
            modelPopupY: 549, keyFieldY: 415, cardHeight: 666)
        try assertTrue(layout.registerLabelY > layout.modelTitleY, "注册地址应在模型上方")
        try assertTrue(layout.modelTitleY > layout.modelPopupY, "模型标题应在下拉框上方")
        try assertTrue(layout.modelPopupY > layout.keyTitleY, "模型应在 API Key 标题上方")
        try assertTrue(layout.keyTitleY > layout.keyFieldY, "API Key 标题应在输入框上方")
        try assertTrue(layout.keyFieldY > layout.testButtonY, "API Key 输入框应在测试按钮上方")
    }
}
