#!/bin/bash
set -e

package_dmg() {
  local APP_VERSION=$1
  local BUILD_DIR=$2
  local APP_BUNDLE=$3

  # 清理旧 DMG，防止重复上传
  rm -f "$BUILD_DIR"/*.dmg

  # 生成 DMG（CI 环境无开发者证书，跳过签名）
  create-dmg --overwrite --no-code-sign "$APP_BUNDLE" "$BUILD_DIR" || {
    echo "create-dmg failed" >&2
    return 1
  }

  # 找到生成的 DMG（不管 create-dmg 输出什么格式）
  GENERATED=$(ls -t "$BUILD_DIR"/*.dmg 2>/dev/null | head -1)
  if [ -z "$GENERATED" ]; then
    echo "create-dmg failed: no .dmg generated" >&2
    return 1
  fi

  # 如果 create-dmg 生成了多个文件，列出警告
  local count
  count=$(ls "$BUILD_DIR"/*.dmg 2>/dev/null | wc -l)
  if [ "$count" -gt 1 ]; then
    echo "WARNING: create-dmg generated $count .dmg files, using: $GENERATED" >&2
    # 只保留最新那个，其他删掉
    for f in "$BUILD_DIR"/*.dmg; do
      [ "$f" = "$GENERATED" ] || rm -f "$f"
    done
  fi

  # 统一重命名为 ELTA.v{VERSION}.dmg
  TARGET="$BUILD_DIR/ELTA.v${APP_VERSION}.dmg"
  mv -f "$GENERATED" "$TARGET"
  echo "DMG: $TARGET"
}

# 如果直接运行脚本（非 source），执行 package_dmg
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  if [ $# -ne 3 ]; then
    echo "Usage: $(basename "$0") <version> <build_dir> <app_bundle>" >&2
    exit 1
  fi
  package_dmg "$1" "$2" "$3"
fi
