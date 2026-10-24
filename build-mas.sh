#!/bin/bash
set -euo pipefail

# ============================================
# ELTA — Mac App Store (sandbox) 构建脚本
# 仅用于本地 spike / TestFlight 预验证，不安装到 /Applications
# ============================================

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ELTA"
BINARY_NAME="ELTA"
BUILD_DIR="$PROJECT_DIR/build/mas"
APP_BUNDLE="$BUILD_DIR/${APP_NAME}.app"
SRC_FILES=("$PROJECT_DIR"/Sources/*.swift)
PLIST="$PROJECT_DIR/Resources/Info-MAS.plist"
ENTITLEMENTS="$PROJECT_DIR/Resources/ELTA-MAS.entitlements"
ICONS_DIR="$PROJECT_DIR/Resources"
MIN_TARGET="13.0"

SWIFT_FLAGS=(
    -D MAS
    -framework Cocoa
    -framework Carbon
    -framework WebKit
    -framework Vision
    -framework UserNotifications
    -framework Security
    -framework ApplicationServices
    -O
    -whole-module-optimization
)

# MAS 分发用 Apple Distribution；本地 spike 回退 Apple Development；最后 ad-hoc
SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -oE '"Apple Distribution[^"]*"' | head -1 | tr -d '"' || true)
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -oE '"Apple Development[^"]*"' | head -1 | tr -d '"' || true)
fi
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="-"
fi

echo "=========================================="
echo " ELTA MAS Build v$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST") ($(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST"))"
echo " 签名身份: ${SIGN_IDENTITY}"
echo "=========================================="

plutil -lint "$PLIST" >/dev/null
plutil -lint "$ENTITLEMENTS" >/dev/null

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "[1/4] 编译 x86_64..."
swiftc -target x86_64-apple-macosx$MIN_TARGET \
    -o "$BUILD_DIR/$BINARY_NAME.x86_64" \
    "${SRC_FILES[@]}" \
    "${SWIFT_FLAGS[@]}"

echo "[2/4] 编译 arm64..."
swiftc -target arm64-apple-macosx$MIN_TARGET \
    -o "$BUILD_DIR/$BINARY_NAME.arm64" \
    "${SRC_FILES[@]}" \
    "${SWIFT_FLAGS[@]}"

echo "[3/4] 合并 Universal Binary + 安装资源..."
lipo -create \
    "$BUILD_DIR/$BINARY_NAME.x86_64" \
    "$BUILD_DIR/$BINARY_NAME.arm64" \
    -output "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME"
rm -f "$BUILD_DIR/$BINARY_NAME.x86_64" "$BUILD_DIR/$BINARY_NAME.arm64"

cp "$PLIST" "$APP_BUNDLE/Contents/Info.plist"
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"
if [ -f "$ICONS_DIR/AppIcon.icns" ]; then
    cp "$ICONS_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# TestFlight/App Store 分发时提供 provisioning profile 路径
if [ -n "${MAS_PROVISIONING_PROFILE:-}" ]; then
    cp "$MAS_PROVISIONING_PROFILE" "$APP_BUNDLE/Contents/embedded.provisionprofile"
    echo "   已内嵌 provisioning profile"
fi

echo "[4/4] 签名（sandbox + hardened runtime）..."
codesign --force --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$APP_BUNDLE"

echo ""
echo "--- 签名验证 ---"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
echo "--- Entitlements ---"
codesign -d --entitlements :- "$APP_BUNDLE" 2>/dev/null
echo ""
echo "构建完成: $APP_BUNDLE"
echo "启动: open \"$APP_BUNDLE\""
echo ""
echo "可选打包 pkg（需要 3rd Party Mac Developer Installer 证书）:"
echo "  productbuild --component \"$APP_BUNDLE\" /Applications --sign \"<installer>\" \"$BUILD_DIR/ELTA.pkg\""
