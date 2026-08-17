#!/bin/bash
set -e
# ============================================
# 上传 DMG 到腾讯云服务器，供官网国内直链下载
# 用法: ./scripts/upload-dmg.sh build/ELTA.v5.2.1.dmg
# ============================================

SERVER="root@106.53.167.38"
DIR="/var/www/elta-downloads"

DMG="$1"
if [ -z "$DMG" ]; then
  echo "Usage: $0 <path/to/ELTA.vX.Y.Z.dmg>" >&2
  exit 1
fi
if [ ! -f "$DMG" ]; then
  echo "错误: 文件不存在: $DMG" >&2
  exit 1
fi

BASE=$(basename "$DMG")

echo "上传 $BASE → $SERVER:$DIR/"
ssh "$SERVER" "mkdir -p $DIR"
scp "$DMG" "$SERVER:$DIR/"

echo "更新 latest.dmg 软链 → $BASE"
ssh "$SERVER" "ln -sf $DIR/$BASE $DIR/latest.dmg && ls -l $DIR/latest.dmg"

echo ""
echo "完成。国内直链: https://autoelta.com/download/latest.dmg"
