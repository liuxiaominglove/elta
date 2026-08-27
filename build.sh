#!/bin/bash
set -e

# ============================================
# ELTA — Intel + Apple Silicon 通用编译 + 打包脚本
# ============================================

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ELTA"
BINARY_NAME="ELTA"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"
APP_TARGET="/Applications/${APP_NAME}.app"
SRC_FILES=("$PROJECT_DIR"/Sources/*.swift)
PLIST="$PROJECT_DIR/Resources/Info.plist"
ICONS_DIR="$PROJECT_DIR/Resources"
MIN_TARGET="13.0"   # 与 Info.plist LSMinimumSystemVersion 保持一致

# 本地稳定签名身份：让 TCC（屏幕录制/辅助功能）与 Keychain「始终允许」授权跨重建持久化。
# ad-hoc（--sign -）每次重建都会生成新的代码身份，macOS 视为新 App，重新弹授权。
# 优先用 "Apple Development" 证书；找不到则回退 ad-hoc。
SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -oE '"Apple Development[^"]*"' | head -1 | tr -d '"')
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="-"
fi

# 通用编译参数
HOST_ARCH=$(uname -m)
SWIFT_FLAGS="-framework Cocoa -framework Carbon -framework WebKit -framework Vision -framework UserNotifications -O -whole-module-optimization"

echo "=========================================="
echo " ELTA v$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST") ($(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")) — Universal Build & Package"
echo "=========================================="
echo ""

# 1. 清理
echo "[1/6] 清理..."
rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 2. 编译
echo "[2/6] 编译 Swift 源码..."

# 2a. x86_64（当前机器架构）
echo "   [x86_64] 编译中..."
swiftc -target x86_64-apple-macosx$MIN_TARGET \
    -o "$BUILD_DIR/$BINARY_NAME.x86_64" \
    "${SRC_FILES[@]}" \
    $SWIFT_FLAGS
echo "   [x86_64] 编译完成"

# 2b. arm64（Apple Silicon）
echo "   [arm64] 交叉编译中..."
swiftc -target arm64-apple-macosx$MIN_TARGET \
    -o "$BUILD_DIR/$BINARY_NAME.arm64" \
    "${SRC_FILES[@]}" \
    $SWIFT_FLAGS
echo "   [arm64] 编译完成"

# 2c. 用 lipo 合并为 Universal Binary
echo "   [合并] 生成 Universal Binary..."
lipo -create \
    "$BUILD_DIR/$BINARY_NAME.x86_64" \
    "$BUILD_DIR/$BINARY_NAME.arm64" \
    -output "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME"

# 验证架构
echo "   架构信息: $(lipo -archs "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME")"
echo "   二进制大小: $(du -h "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME" | cut -f1)"

# 清理中间产物
rm -f "$BUILD_DIR/$BINARY_NAME.x86_64" "$BUILD_DIR/$BINARY_NAME.arm64"

# 3. 图标（如存在）
echo "[3/6] 处理图标..."
if [ -f "$ICONS_DIR/AppIcon.icns" ]; then
    cp "$ICONS_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
    echo "   图标已安装"
else
    echo "   跳过（无图标文件）"
fi

# 4. Info.plist + PkgInfo
echo "[4/6] 安装 Info.plist..."
cp "$PLIST" "$APP_BUNDLE/Contents/"
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# 5. 代码签名（本地开发用稳定签名身份，避免重建后 TCC/Keychain 重复弹授权）
echo "[5/6] 签名（身份: ${SIGN_IDENTITY}）..."
codesign --force --sign "$SIGN_IDENTITY" "$APP_BUNDLE" 2>/dev/null && echo "   签名成功" || echo "   签名跳过"

echo ""
echo "=========================================="
echo " 打包完成: $APP_BUNDLE"
echo ""

# 6. 自动安装到 /Applications
echo "[6/6] 安装到 /Applications..."

# 终止旧版本
killall "$BINARY_NAME" 2>/dev/null || true
sleep 0.5

# 删除旧版本
rm -rf "$APP_TARGET" 2>/dev/null || true
# 校验删除成功：BSD cp 在目标已存在时会拷进目标内形成嵌套 bundle，必须确认旧版已移除（含悬空符号链接）
if [ -e "$APP_TARGET" ] || [ -L "$APP_TARGET" ]; then
    echo "错误：无法删除 $APP_TARGET（可能由 sudo/pkg 安装、属 root 所有；请 sudo rm -rf 后重试）" >&2
    exit 1
fi

# 复制新版本
cp -R "$APP_BUNDLE" "$APP_TARGET"

# 签名
codesign --force --sign "$SIGN_IDENTITY" "$APP_TARGET" 2>/dev/null

echo "安装完成: $APP_TARGET"
echo ""

# 询问是否启动（仅在交互终端；CI/非交互环境 read 会因 EOF 返回非零，set -e 下导致构建误判失败）
if [ -t 0 ]; then
    read -p "是否立即启动？[Y/n] " -n 1 -r
    echo ""
else
    REPLY=n
fi
if [[ $REPLY =~ ^[Yy] ]] || [[ -z $REPLY ]]; then
    open "$APP_TARGET"
    echo "已启动 $APP_NAME"
    sleep 1
    echo ""
    echo "📖 查看菜单栏右上角的 ELTA 图标"
    echo "⌨️  快捷键: Cmd+T 截图翻译"
fi

echo ""
echo "=========================================="
echo " 完成"
echo "=========================================="
