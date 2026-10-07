#!/usr/bin/env bash
# 双入口等价回归（v1.3 改造的核心可机械核对证据）
#
# 主张：把 .mbg.md 拆成「指引 + level.json + probes.json」之后，
#       玩法语义没有发生任何改变——两条入口在同一个内核上跑出
#       **逐探针完全一致**的结果。
#
# 主张的反面（若这条挂了意味着什么）：
#   改造悄悄改了物理参数 / 出生点 / 碰撞顺序 / 胜负判定 →
#   v1.3 就不是"重构"而是"行为变更"，下游证据全部作废。
#
# 比对内容：探针名 + pass + detail（detail 含终局 state、帧数/moves、
#           serialize 摘要）。契约指纹不比——它按设计就该不同
#           （指纹覆盖内容源，指引路径与 inline 路径的源文本本就不同）。

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$HERE/.."
HEAD="$ENGINE/_build/native/debug/build/apphead/apphead.exe"

if [ ! -x "$HEAD" ]; then
    echo "缺少 headless 二进制，先跑 engine/build.sh" >&2
    exit 1
fi

fail() { echo "❌ 回归失败: $1" >&2; exit 1; }

# 抽出 results 数组（探针结果），去掉指纹字段后比对
results_of() {
    "$HEAD" verify "$1" 2>/dev/null | sed -E 's/,"contract_fingerprint":"[^"]*"//'
}

GAMES="platformer coinrush boxpush"
echo "— 双入口等价性（inline vs guide）—"
for g in $GAMES; do
    guide="$ENGINE/../examples/$g/game.guide.md"
    inline="$ENGINE/../examples/$g/game.mbg.md"
    if [ ! -f "$guide" ] || [ ! -f "$inline" ]; then
        fail "$g 缺少对照文件（需同时有 game.guide.md 与 game.mbg.md）"
    fi
    rg="$(results_of "$guide")"
    ri="$(results_of "$inline")"
    if [ "$rg" != "$ri" ]; then
        echo "--- guide 结果: $rg" >&2
        echo "--- inline 结果: $ri" >&2
        fail "$g 两条入口结果不一致——改造改变了玩法语义"
    fi
    n=$(echo "$rg" | grep -o '"name":' | wc -l | tr -d ' ')
    echo "✅ $g: 两入口 $n 个探针结果逐条一致"
done

echo ""
echo "双入口等价回归通过——v1.3 改造未改变玩法语义。"