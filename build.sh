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
SRC="$PROJECT_DIR/Sources/main.swift"
PLIST="$PROJECT_DIR/Resources/Info.plist"
ICONS_DIR="$PROJECT_DIR/Resources"
MIN_TARGET="13.0"   # 与 Info.plist LSMinimumSystemVersion 保持一致

# 通用编译参数
HOST_ARCH=$(uname -m)
SWIFT_FLAGS="-framework Cocoa -framework Carbon -framework WebKit -framework Vision -framework UserNotifications -O -whole-module-optimization"

echo "=========================================="
echo " ELTA v5.0 — Universal Build & Package"
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
    "$SRC" \
    $SWIFT_FLAGS
echo "   [x86_64] 编译完成"

# 2b. arm64（Apple Silicon）
echo "   [arm64] 交叉编译中..."
swiftc -target arm64-apple-macosx$MIN_TARGET \
    -o "$BUILD_DIR/$BINARY_NAME.arm64" \
    "$SRC" \
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

# 5. 代码签名（本地开发用 ad-hoc 签名）
echo "[5/6] 签名..."
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null && echo "   签名成功" || echo "   签名跳过"

echo ""
echo "=========================================="
echo " 打包完成: $APP_BUNDLE"
echo ""

# 询问是否安装
read -p "是否安装到 /Applications？[Y/n] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy] ]] || [[ -z $REPLY ]]; then
    echo "正在安装..."
    
    # 终止旧版本
    killall "$BINARY_NAME" 2>/dev/null || true
    sleep 0.5

    # 删除旧版本
    rm -rf "$APP_TARGET" 2>/dev/null || true

    # 复制新版本
    cp -R "$APP_BUNDLE" "$APP_TARGET"

    # 签名
    codesign --force --sign - "$APP_TARGET" 2>/dev/null

    echo "安装完成: $APP_TARGET"
    echo ""
    
    # 启动
    read -p "是否立即启动？[Y/n] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy] ]] || [[ -z $REPLY ]]; then
        open "$APP_TARGET"
        echo "已启动 $APP_NAME"
        sleep 1
        echo ""
        echo "📖 查看菜单栏右上角的 ELTA 图标"
        echo "⌨️  快捷键: Cmd+T 截图翻译"
    fi
else
    echo ""
    echo "手动安装: cp -R \"$APP_BUNDLE\" /Applications/"
fi

echo ""
echo "=========================================="
echo " 完成"
echo "=========================================="
