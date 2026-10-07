#!/usr/bin/env bash
# 验证器自校准三件套（blueprint §3.7，GamePhanes 最小充分校准对直移）。
#
#   oracle  真实可通关 + 探针真实   → verify 必须 exit 0（接受真工作）
#   starter 不可通关 + 探针撒谎     → verify 必须 exit 2（拒绝伪声明）
#   nop     空文件                  → verify 必须 exit 1（拒绝"无输入即成功"）
#
# 三者缺一，验证器分数无意义。任何探针/内核改动后必须重跑本脚本。
#
# v1.3：两条入口各自校准（inline `.mbg.md` 与指引 `.guide.md`）——
# 新入口若不校准，就等于没校准：验证器在新路径上可能永远绿。

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HEAD="$HERE/../_build/native/debug/build/apphead/apphead.exe"

if [ ! -x "$HEAD" ]; then
    echo "缺少 headless 二进制，先跑 ./build.sh" >&2
    exit 1
fi

fail() { echo "❌ 校准失败: $1" >&2; exit 1; }

# expect <期望码> <说明> <文件...>
expect() {
    local want="$1"; shift
    local label="$1"; shift
    set +e
    "$HEAD" verify "$@" >/dev/null 2>&1
    local got=$?
    set -e
    [ "$got" -eq "$want" ] || fail "$label 应 exit $want, got $got"
    echo "✅ $label: exit $got"
}

echo "— inline 入口（.mbg.md）—"
expect 0 "oracle  " "$HERE/oracle.mbg.md"
expect 2 "starter " "$HERE/starter.mbg.md"
expect 1 "nop     " "$HERE/nop.mbg.md"

echo "— 指引入口（.guide.md）—"
expect 0 "oracle  " "$HERE/oracle.guide.md"
expect 2 "starter " "$HERE/starter.guide.md"

echo "— 指引入口：缺源必须拒绝（不能静默用空世界通过）—"
expect 1 "missing " "$HERE/broken.guide.md"

echo ""
echo "校准三件套全部通过（两条入口）——验证器不是永远绿。"
