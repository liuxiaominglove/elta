#!/bin/sh
# 在 macOS 上运行 Core 单元测试（Windows 专属项目不参与）
# 用法: sh windows/test-core.sh [额外的 dotnet test 参数]
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
DOTNET="dotnet"
if ! command -v dotnet >/dev/null 2>&1; then
    DOTNET="$HOME/.dotnet/dotnet"
fi

exec "$DOTNET" test "$DIR/tests/Elta.Core.Tests/Elta.Core.Tests.csproj" "$@"
