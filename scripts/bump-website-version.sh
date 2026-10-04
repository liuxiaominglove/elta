#!/bin/bash
# bump-website-version.sh — 官网版本号单命令更新（确定性、无构建）
#
# 用法:
#   scripts/bump-website-version.sh <win|mac> <X.Y.Z>            # 更新官网版本号与直链（原地写）
#   scripts/bump-website-version.sh <win|mac> <X.Y.Z> --check    # 只校验：页面已是该版本则退出 0，否则退出 1
#
# 说明:
#   - 版本源单一：Windows = tag `win-vX.Y.Z` / `Elta.Windows.csproj <Version>`；mac = `Resources/Info.plist`。
#   - 旧版本模式用「版本无关」正则匹配，故脚本幂等：重复执行为空操作。
#   - 用临时文件 + mv 落盘（兼容 BSD/GNU sed，不依赖 `sed -i`）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEBSITE="$ROOT/website"

usage() {
  echo "Usage: $(basename "$0") <win|mac> <X.Y.Z> [--check]" >&2
  exit 2
}

[ $# -ge 2 ] || usage
PLATFORM="$1"
VERSION="$2"
MODE="${3:-bump}"
[ "$MODE" = "bump" ] || [ "$MODE" = "--check" ] || usage
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "bad version: '$VERSION' (expect X.Y.Z)" >&2; exit 2; }

# 每平台的目标文件集合
case "$PLATFORM" in
  win)
    FILES=("$WEBSITE/index.html" "$WEBSITE/install.html")
    EXPRS=(
      -e "s#ELTA-Windows-v[0-9][0-9.]*-win-x64-single\.zip#ELTA-Windows-v${VERSION}-win-x64-single.zip#g"
      -e "s#Windows（v[0-9][0-9.]*）#Windows（v${VERSION}）#g"
      -e "s#Windows v[0-9][0-9.]*#Windows v${VERSION}#g"
    )
    ;;
  mac)
    FILES=("$WEBSITE"/*.html)
    EXPRS=(
      -e "s#ELTA\.v[0-9][0-9.]*\.dmg#ELTA.v${VERSION}.dmg#g"
      -e "s#macOS（v[0-9][0-9.]*）#macOS（v${VERSION}）#g"
      -e "s#macOS v[0-9][0-9.]*#macOS v${VERSION}#g"
      -e "s#ELTA v[0-9][0-9.]*#ELTA v${VERSION}#g"
    )
    ;;
  *)
    usage
    ;;
esac

if [ "$MODE" = "--check" ]; then
  stale=0
  for f in "${FILES[@]}"; do
    if ! diff -q <(sed "${EXPRS[@]}" "$f") "$f" >/dev/null 2>&1; then
      echo "STALE: $(basename "$f") 未处于 ${PLATFORM} v${VERSION}"
      stale=1
    fi
  done
  if [ "$stale" -eq 0 ]; then
    echo "OK: 官网 ${PLATFORM} 版本已是 v${VERSION}"
  fi
  exit "$stale"
fi

changed=0
for f in "${FILES[@]}"; do
  if ! diff -q <(sed "${EXPRS[@]}" "$f") "$f" >/dev/null 2>&1; then
    sed "${EXPRS[@]}" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    echo "bumped: $(basename "$f") -> ${PLATFORM} v${VERSION}"
    changed=1
  fi
done

if [ "$changed" -eq 0 ]; then
  echo "no change: 官网 ${PLATFORM} 版本已是 v${VERSION}"
fi
