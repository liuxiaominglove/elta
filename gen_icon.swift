import AppKit
import Foundation

// MARK: - ELTA 图标生成器
// 从源 PNG 生成 macOS AppIcon.icns

let projectDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourcePNG = projectDir.appendingPathComponent("generated-images/ELTA_icon_rounded_v3.png")
let outputDir = projectDir.appendingPathComponent("Resources")
let iconsetDir = outputDir.appendingPathComponent("AppIcon.iconset")

// 验证源文件存在
guard FileManager.default.fileExists(atPath: sourcePNG.path) else {
    print("❌ 错误：找不到源图标文件 \(sourcePNG.path)")
    print("   请确保 generated-images/ELTA_icon_rounded_v3.png 存在")
    exit(1)
}

// 清理并创建 iconset 目录
try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (size, name) in sizes {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    task.arguments = [
        "-z", String(size), String(size),
        sourcePNG.path,
        "--out", iconsetDir.appendingPathComponent(name).path
    ]
    try task.run()
    task.waitUntilExit()
    print("  \(name) (\(size)x\(size)) ✓")
}

// 用 iconutil 打包成 .icns
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", "-o", outputDir.appendingPathComponent("AppIcon.icns").path, iconsetDir.path]
try task.run()
task.waitUntilExit()

// 清理临时 iconset
try? FileManager.default.removeItem(at: iconsetDir)

print("✅ AppIcon.icns 已生成: \(outputDir.appendingPathComponent("AppIcon.icns").path)")
