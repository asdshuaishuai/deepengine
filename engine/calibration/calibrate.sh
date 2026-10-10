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

# expect_cmd <期望码> <说明> <子命令> <参数...>
expect_cmd() {
    local want="$1"; shift
    local label="$1"; shift
    set +e
    "$HEAD" "$@" >/dev/null 2>&1
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

# ---- 体验裁决面自校准（blueprint §3.9）----
#
# 新的一层分数上线就必须过同一道门：**它不能永远说"改进了"**。
# 夹具 v1/v2 只差一个参数（走道上加满尖刺），共用同一份策略集与标准。
#
#   trace v1      → 0  全标准通过（好版本被接受）
#   trace v2      → 2  标准全败（坏版本被拦）
#   compare v1 v2 → 2  keep_a（退化被拒）
#   compare v2 v1 → 0  accept_b（改进被接受）
#   compare v1 v1 → 3  inconclusive（**同版不可判为改进**）
EXP="$HERE/experience"
echo "— 体验裁决面（策略 → 轨迹 → 度量 → 版本裁决）—"
expect_cmd 0 "good      " trace "$EXP/v1.guide.md"
expect_cmd 2 "broken    " trace "$EXP/v2.guide.md"
expect_cmd 2 "拒绝退化  " compare "$EXP/v1.guide.md" "$EXP/v2.guide.md"
expect_cmd 0 "接受改进  " compare "$EXP/v2.guide.md" "$EXP/v1.guide.md"
expect_cmd 3 "同版不可判" compare "$EXP/v1.guide.md" "$EXP/v1.guide.md"
# compare（单轮）与 rsi（多轮）共用同一套裁决规则：判据与探针都从**基线**冻结。
# v1.4 的 compare 取候选声明的标准，实测能被"自私尺子"骗到 accept_b（exit 0）——下面三条钉死它。
expect_cmd 4 "compare 拦操弄" compare "$HERE/rsi/base.guide.md" "$HERE/rsi/c3_selfserving.guide.md"
expect_cmd 3 "compare 探针膨胀" compare "$HERE/rsi/base.guide.md" "$HERE/rsi/c4_morepolicies.guide.md"
expect_cmd 3 "compare 跨族不可比" compare "$HERE/../../examples/platformer/game.guide.md" "$HERE/../../examples/boxpush/game.guide.md"

echo ""
echo "— 递归自改进面（RSI：冻结门 → 多轮 → 台账 → 复算）—"
#
# 单轮 compare 不够：多轮会引入两个新作弊面，本段就是钉死它们的：
#   * 候选改写评判自己的判据（gate shopping）→ 必须仍被拒、且退出码 3 报警；
#   * 候选自带另一套策略集抬高覆盖率 → 必须标记 policy_drift。
# 台账还必须**可复算**，且被篡改时变红——否则"审计链"只是装饰。
RSI="$HERE/rsi"
expect_cmd 0 "接受真改进" rsi run "$RSI/base.guide.md" "$RSI/c1_better.guide.md"
expect_cmd 2 "拒绝退化  " rsi run "$RSI/base.guide.md" "$RSI/c2_worse.guide.md"
expect_cmd 3 "操弄判据上报" rsi run "$RSI/base.guide.md" "$RSI/c3_selfserving.guide.md"
# 比"改判据"更隐蔽的一种：多带策略把覆盖率"测"上去（c4 的世界与 base 完全相同）
expect_cmd 2 "策略集膨胀无效" rsi run "$RSI/base.guide.md" "$RSI/c4_morepolicies.guide.md"
# 原型族不同（physics vs grid）：度量同名不同义，必须判"不可裁决"而不是给出 accept/keep
expect_cmd 2 "跨族不可比" rsi run "$HERE/../../examples/platformer/game.guide.md" "$HERE/../../examples/boxpush/game.guide.md"
expect_cmd 2 "预算即停  " rsi run "$RSI/base.guide.md" "$RSI/c2_worse.guide.md" "$RSI/c2_worse.guide.md" --budget 1
expect_cmd 0 "停滞也算正常停" rsi run "$RSI/base.guide.md" "$RSI/c1_better.guide.md" "$RSI/c2_worse.guide.md" "$RSI/c2_worse.guide.md"

# 台账：跑一次多轮 run 存盘，然后复算；再篡改一处，复算必须变红。
LEDGER="$HERE/rsi_ledger.tmp.json"
"$HEAD" rsi run "$RSI/base.guide.md" "$RSI/c1_better.guide.md" "$RSI/c2_worse.guide.md" "$RSI/c3_selfserving.guide.md" >"$LEDGER" 2>/dev/null || true
expect_cmd 0 "台账可复算" rsi check "$LEDGER"
# 篡改：把某一轮的候选指纹改掉（模拟"记账后动了内容"）
python3 - "$LEDGER" "$HERE/rsi_ledger.tampered.tmp.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
d["rounds"][0]["cand"]["digest"] = "0-0-0"
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=True)
PY
expect_cmd 2 "篡改台账必红" rsi check "$HERE/rsi_ledger.tampered.tmp.json"
rm -f "$LEDGER" "$HERE/rsi_ledger.tampered.tmp.json"

echo ""
echo "校准全部通过（两条入口 + 体验裁决面 + 递归自改进面 + compare/rsi 共用裁决规则）——验证器与裁决器都不是永远绿。"
