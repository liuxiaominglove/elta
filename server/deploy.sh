#!/bin/bash
# ============================================
# ELTA 使用统计 API 部署脚本
# 把 server/ 代码 + systemd 单例 + cron 装到腾讯云服务器。
#
# 用法:
#   ./server/deploy.sh
#
# 注意: nginx 反代与 sync-elta-release.sh 的 latest.json 写入
#       需手动改（见本脚本末尾提示，或 README）。
# ============================================
set -euo pipefail

SERVER="root@106.53.167.38"
DIR="/var/www/elta-api"
PORT="8787"
LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== 1/5 上传 server 代码 ==="
ssh "$SERVER" "mkdir -p $DIR"
scp "$LOCAL_DIR/core.py" "$LOCAL_DIR/server.py" "$LOCAL_DIR/downloads.py" \
    "$LOCAL_DIR/count-downloads.py" "$LOCAL_DIR/sync-github.py" \
    "$LOCAL_DIR/admin.html" "$SERVER:$DIR/"

echo "=== 2/5 安装 systemd 单例 ==="
scp "$LOCAL_DIR/elta-api.service" "$SERVER:/etc/systemd/system/elta-api.service"

echo "=== 3/5 配置管理口令（/etc/elta-api.env）==="
ssh "$SERVER" '
  if [ ! -f /etc/elta-api.env ]; then
    read -rsp "输入看板口令 ELTA_ADMIN_PASSWORD: " pw
    echo
    printf "ELTA_ADMIN_PASSWORD=%s\n" "$pw" > /etc/elta-api.env
    chmod 600 /etc/elta-api.env
  else
    echo "已存在 /etc/elta-api.env，跳过"
  fi
'

echo "=== 4/5 启动服务 ==="
ssh "$SERVER" 'systemctl daemon-reload && systemctl enable --now elta-api && systemctl status elta-api --no-pager | head -5'

echo "=== 5/5 安装 cron ==="
ssh "$SERVER" '
  CRON="/var/spool/cron/root"
  touch "$CRON"
  grep -q "count-downloads.py" "$CRON" || echo "*/5 * * * * /usr/bin/python3 /var/www/elta-api/count-downloads.py >> /var/log/elta-api.log 2>&1" >> "$CRON"
  grep -q "sync-github.py" "$CRON" || echo "0 * * * * /usr/bin/python3 /var/www/elta-api/sync-github.py >> /var/log/elta-api.log 2>&1" >> "$CRON"
  echo "cron 已更新:"
  crontab -l | grep "elta-api"
'

echo ""
echo "================================================"
echo " 还需手动完成（本脚本不自动改，防误操作）:"
echo "================================================"
echo " 1) nginx: 把 /etc/nginx/conf.d/elta.conf 里的"
echo "       location /api/ { return 404; }"
echo "    替换为 proxy_pass 到 127.0.0.1:$PORT，并加 /admin 反代"
echo "    （需传 X-Real-IP 供 IP 兜底去重）"
echo " 2) /root/sync-elta-release.sh 末尾追加 latest.json 写入:"
echo "       VERSION_NO_V=\${TAG#v}"
echo "       echo \"{\\\"version\\\":\\\"\$VERSION_NO_V\\\",\\\"url\\\":\\\"https://autoelta.com/download/\$BASE\\\"}\" > $DIR/latest.json"
echo "================================================"
