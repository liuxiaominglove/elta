import Foundation

func runUpdateCheckerTests() {
    print("\n--- UpdateChecker Tests ---")

    // MARK: - 响应解析（新 JSON 格式 {version, url}）

    test("parseUpdateResponse extracts version and url") {
        let json = #"{"version":"5.6.0","url":"https://autoelta.com/download/ELTA.v5.6.0.dmg"}"#
        let result = UpdateChecker.parseUpdateResponse(json.data(using: .utf8)!)
        try assertEqual(result?.version, "5.6.0")
        try assertEqual(result?.url, "https://autoelta.com/download/ELTA.v5.6.0.dmg")
    }

    test("parseUpdateResponse strips leading v from version") {
        let json = #"{"version":"v5.6.0","url":"https://autoelta.com/download/ELTA.v5.6.0.dmg"}"#
        let result = UpdateChecker.parseUpdateResponse(json.data(using: .utf8)!)
        try assertEqual(result?.version, "5.6.0")
    }

    test("parseUpdateResponse returns nil on empty object") {
        let result = UpdateChecker.parseUpdateResponse("{}".data(using: .utf8)!)
        try assertNil(result as Any?)
    }

    test("parseUpdateResponse returns nil when url missing") {
        let json = #"{"version":"5.6.0"}"#
        try assertNil(UpdateChecker.parseUpdateResponse(json.data(using: .utf8)!) as Any?)
    }

    test("parseUpdateResponse returns nil when version empty") {
        let json = #"{"version":"","url":"x"}"#
        try assertNil(UpdateChecker.parseUpdateResponse(json.data(using: .utf8)!) as Any?)
    }

    test("parseUpdateResponse returns nil on invalid JSON") {
        try assertNil(UpdateChecker.parseUpdateResponse("not json".data(using: .utf8)!) as Any?)
    }

    // MARK: - 版本比较

    test("isNewer returns true when remote is newer") {
        try assertTrue(UpdateChecker.isNewer(remote: "5.2.0", local: "5.1.31"))
    }

    test("isNewer returns false on equal version") {
        try assertFalse(UpdateChecker.isNewer(remote: "5.1.31", local: "5.1.31"))
    }

    test("isNewer returns false when remote is older") {
        try assertFalse(UpdateChecker.isNewer(remote: "5.0.0", local: "5.1.31"))
    }

    // MARK: - 是否弹更新（含跳过版本）

    test("shouldShowUpdate true for newer without skip") {
        try assertTrue(UpdateChecker.shouldShowUpdate(remoteVersion: "5.2.0", localVersion: "5.1.31", skipVersion: nil))
    }

    test("shouldShowUpdate false for same version") {
        try assertFalse(UpdateChecker.shouldShowUpdate(remoteVersion: "5.1.31", localVersion: "5.1.31", skipVersion: nil))
    }

    test("shouldShowUpdate false when version skipped") {
        try assertFalse(UpdateChecker.shouldShowUpdate(remoteVersion: "5.2.0", localVersion: "5.1.31", skipVersion: "5.2.0"))
    }

    // MARK: - 更新检查 URL

    test("updateURL points to our self-hosted endpoint") {
        try assertEqual(UpdateChecker.updateURL, "https://autoelta.com/api/update")
    }

    // MARK: - 匿名统计开关决定是否附带 id

    test("buildUpdateURL appends id when telemetry on") {
        let url = UpdateChecker.buildUpdateURL(telemetryEnabled: true, installID: "abc-123")
        try assertEqual(url, "https://autoelta.com/api/update?id=abc-123")
    }

    test("buildUpdateURL omits id when telemetry off") {
        let url = UpdateChecker.buildUpdateURL(telemetryEnabled: false, installID: "abc-123")
        try assertEqual(url, "https://autoelta.com/api/update")
    }
}
