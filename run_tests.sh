#!/bin/bash
set -euo pipefail

# =============================================
# ELTA Unit Test Runner
# 编译并运行单元测试
# =============================================

cd "$(dirname "$0")"
PROJECT_DIR="$(pwd)"

echo "========================================"
echo " ELTA Unit Tests"
echo "========================================"
echo ""

# ---- 编译阶段 ----
echo "[1/2] Building test executable..."

SRC_FILES=(
  "$PROJECT_DIR/Sources/AIProvider.swift"
  "$PROJECT_DIR/Sources/HotkeyHelpers.swift"
  "$PROJECT_DIR/Sources/Helpers.swift"
  "$PROJECT_DIR/Sources/SettingsManager.swift"
  "$PROJECT_DIR/Sources/TextPreprocessor.swift"
)

TEST_FILES=(
  "$PROJECT_DIR/Tests/GlobalsForTesting.swift"
  "$PROJECT_DIR/Tests/TestRunner.swift"
  "$PROJECT_DIR/Tests/AIProviderTests.swift"
  "$PROJECT_DIR/Tests/HotkeyHelpersTests.swift"
  "$PROJECT_DIR/Tests/SettingsManagerTests.swift"
  "$PROJECT_DIR/Tests/TextPreprocessorTests.swift"
  "$PROJECT_DIR/Tests/BuildScriptTests.swift"
  "$PROJECT_DIR/Tests/main.swift"
)

ALL_FILES=("${SRC_FILES[@]}" "${TEST_FILES[@]}")

TEST_BIN="$PROJECT_DIR/Tests/test_runner"

swiftc \
  -suppress-warnings \
  -o "$TEST_BIN" \
  -framework Cocoa \
  -framework Carbon \
  -framework Security \
  -framework ApplicationServices \
  "${ALL_FILES[@]}"

echo "[1/2] Build succeeded."
echo ""

# ---- 运行阶段 ----
echo "[2/2] Running tests..."
echo ""

"$TEST_BIN"
EXIT_CODE=$?

echo ""

# ---- 清理 ----
if [ -f "$TEST_BIN" ]; then
  rm -f "$TEST_BIN"
fi

# Clean up test log
LOG_FILE="$HOME/Library/Logs/elta_test.log"
[ -f "$LOG_FILE" ] && rm -f "$LOG_FILE"

exit $EXIT_CODE
