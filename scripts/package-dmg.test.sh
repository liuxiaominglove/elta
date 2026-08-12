#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
pass=0
fail=0
TOTAL_TESTS=7

# ── helpers ──────────────────────────────────────────────────
assert_exit() {
  local expected=$1 actual=$2 desc=$3
  if [ "$expected" -eq "$actual" ]; then
    echo "  ✓ $desc"; ((++pass))
  else
    echo "  ✗ $desc (expected exit=$expected, got=$actual)"; ((++fail))
  fi
}

assert_file_exists() {
  local f=$1 desc=$2
  if [ -f "$f" ]; then
    echo "  ✓ $desc"; ((++pass))
  else
    echo "  ✗ $desc (file missing: $f)"; ((++fail))
  fi
}

assert_dmg_count() {
  local expected=$1 dir=$2 desc=$3
  local actual
  actual=$(ls "$dir"/*.dmg 2>/dev/null | wc -l | tr -d '[:space:]')
  actual=${actual:-0}
  if [ "$expected" -eq "$actual" ]; then
    echo "  ✓ $desc"; ((++pass))
  else
    echo "  ✗ $desc (expected $expected DMG files, got $actual)"; ((++fail))
  fi
}

assert_output_contains() {
  local needle=$1 output_file=$2 desc=$3
  if grep -qF "$needle" "$output_file" 2>/dev/null; then
    echo "  ✓ $desc"; ((++pass))
  else
    echo "  ✗ $desc (output missing '$needle')"; ((++fail))
  fi
}

# ── setup / teardown ──────────────────────────────────────────
setup() {
  TESTDIR=$(mktemp -d /tmp/package-dmg-test.XXXXXX)
  mkdir -p "$TESTDIR/build"
  mkdir -p "$TESTDIR/build/ELTA.app"
}

teardown() {
  rm -rf "$TESTDIR"
}

# 在子 shell 中 source 脚本并执行 package_dmg，捕获输出和退出码
invoke() {
  local mock_def=$1      # create-dmg mock 函数体
  local version=$2
  shift 2

  bash -c "
    $mock_def
    source '$SCRIPT_DIR/package-dmg.sh'
    package_dmg '$version' '$TESTDIR/build' '$TESTDIR/build/ELTA.app'
  " > "$TESTDIR/stdout" 2>&1
  echo $? > "$TESTDIR/exit_code"
}

# ── tests ─────────────────────────────────────────────────────

echo "=== package-dmg.sh 测试套件 (共 $TOTAL_TESTS 项) ==="
echo ""

run_test() {
  local num=$1 desc=$2
  echo "--- 测试 $num: $desc ---"
  ((++test_case))
}

test_case=0

# ── 1. create-dmg 输出空格格式 ─────────────────────────────
run_test 1 "create-dmg 输出空格格式"
setup
invoke "create-dmg() { touch '$TESTDIR/build/ELTA 5.1.31.dmg'; }" "5.1.31"
assert_exit 0 "$(cat "$TESTDIR/exit_code")" "exit=0"
assert_file_exists "$TESTDIR/build/ELTA.v5.1.31.dmg" "生成 ELTA.v5.1.31.dmg"
assert_dmg_count 1 "$TESTDIR/build" "build 目录只有 1 个 DMG"
teardown

# ── 2. create-dmg 输出 dash 格式 ──────────────────────────────
run_test 2 "create-dmg 输出 dash 格式"
setup
invoke "create-dmg() { touch '$TESTDIR/build/ELTA-5.1.31.dmg'; }" "5.1.31"
assert_exit 0 "$(cat "$TESTDIR/exit_code")" "exit=0"
assert_file_exists "$TESTDIR/build/ELTA.v5.1.31.dmg" "重命名为 ELTA.v5.1.31.dmg"
assert_dmg_count 1 "$TESTDIR/build" "只保留一个 DMG"
teardown

# ── 3. create-dmg 输出 dot 格式 ───────────────────────────────
run_test 3 "create-dmg 输出正确格式（dot 格式）"
setup
invoke "create-dmg() { touch '$TESTDIR/build/ELTA.v5.1.31.dmg'; }" "5.1.31"
assert_exit 0 "$(cat "$TESTDIR/exit_code")" "exit=0"
assert_file_exists "$TESTDIR/build/ELTA.v5.1.31.dmg" "文件保持正确命名"
assert_dmg_count 1 "$TESTDIR/build" "只有一个 DMG"
teardown

# ── 4. create-dmg 失败，无 .dmg 文件 ─────────────────────────
run_test 4 "create-dmg 失败，无 .dmg 生成"
setup
invoke "create-dmg() { return 1; }" "5.1.31"
assert_exit 1 "$(cat "$TESTDIR/exit_code")" "exit 非 0"
assert_output_contains "failed" "$TESTDIR/stdout" "stderr 包含 'failed'"
teardown

# ── 5. build 目录有旧 .dmg 残留 ──────────────────────────────
run_test 5 "build 已有旧 DMG 残留"
setup
touch "$TESTDIR/build/OLD-v1.0.dmg"
touch "$TESTDIR/build/OLD-v2.0.dmg"
touch "$TESTDIR/build/some-other-file.txt"
invoke "create-dmg() { touch '$TESTDIR/build/ELTA 5.1.31.dmg'; }" "5.1.31"
assert_exit 0 "$(cat "$TESTDIR/exit_code")" "exit=0"
assert_dmg_count 1 "$TESTDIR/build" "旧 DMG 已清理，只留一个"
assert_file_exists "$TESTDIR/build/ELTA.v5.1.31.dmg" "新 DMG 生成"
assert_file_exists "$TESTDIR/build/some-other-file.txt" "非 dmg 文件不受影响"
teardown

# ── 6. 目标文件名已存在 ──────────────────────────────────────
run_test 6 "目标名称已存在"
setup
touch "$TESTDIR/build/ELTA.v5.1.31.dmg"
invoke "create-dmg() { touch '$TESTDIR/build/ELTA-5.1.31.dmg'; }" "5.1.31"
assert_exit 0 "$(cat "$TESTDIR/exit_code")" "exit=0"
assert_file_exists "$TESTDIR/build/ELTA.v5.1.31.dmg" "覆盖成功"
assert_dmg_count 1 "$TESTDIR/build" "仍然只有一个 DMG"
teardown

# ── 7. create-dmg 输出了多个 .dmg 文件 ───────────────────────
run_test 7 "create-dmg 生成多个 .dmg"
setup
invoke "create-dmg() { touch '$TESTDIR/build/ELTA 5.1.31.dmg'; touch '$TESTDIR/build/ELTA.5.1.31.dmg'; }" "5.1.31"
assert_exit 0 "$(cat "$TESTDIR/exit_code")" "exit=0"
assert_file_exists "$TESTDIR/build/ELTA.v5.1.31.dmg" "有一个 DMG 被重命名为规范名"
assert_dmg_count 1 "$TESTDIR/build" "最终只有一个 DMG"
teardown

# ── summary ───────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "结果: $test_case 个测试 / $pass 个断言通过"
if [ "$fail" -gt 0 ]; then
  echo "失败: $fail 个断言"
fi
echo "=========================================="
[ "$fail" -eq 0 ] && exit 0 || exit 1
