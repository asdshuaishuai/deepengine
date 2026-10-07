#!/usr/bin/env bash
# retro 资源面回归（v1.3）
#
# 与 moon test 的分工：
#   moon test  = 引擎内部逻辑（生成、编解码、门禁）
#   本脚本    = **跨语言交叉验证**——用独立的 Python 实现读回引擎产出的 SVG
#               重建像素图。若两边对同一份工件的解读不一致，说明至少有一边错。
#
# 这不是重复测试：MoonBit 与 Python 是两套独立实现，能抓住单侧实现里的
# 格式 bug（已抓到一次：hexc 让每个通道各自加 '#'，拼出 #A6#27#21 非法颜色，
# SVG 在浏览器里静默渲染失败——引擎内测试当时全绿）。

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$HERE/.."
ROOT="$ENGINE/.."
HEAD="$ENGINE/_build/native/debug/build/apphead/apphead.exe"
SHOTS="$ROOT/shots/retro"

if [ ! -x "$HEAD" ]; then
    echo "缺少 headless 二进制，先跑 engine/build.sh" >&2
    exit 1
fi

fail() { echo "❌ retro 回归失败: $1" >&2; exit 1; }

mkdir -p "$SHOTS"
cd "$SHOTS"

echo "— 资源契约门禁（引擎自检）—"
for plat in fc sfc; do
    "$HEAD" retro check "$plat" >/dev/null 2>&1
    [ $? -eq 0 ] || fail "$plat 资源契约未过（用色超预算或帧组为空）"
    echo "✅ $plat check: exit 0"
done

echo "— CHR 往返（识别闭环的核心不变量）—"
for pose in idle walk1 walk2 jump fall duck; do
    out=$("$HEAD" retro identify fc "$pose" 2>/dev/null)
    echo "$out" | grep -q '"roundtrip_identical":true' \
        || fail "$pose 的 CHR 往返不一致（to_chr/from_chr 不互逆）"
    echo "$out" | grep -q '"ok":true' \
        || fail "$pose 识别判定为不合规"
    echo "$out" | grep -q '"errors":\[\]' \
        || fail "$pose 报告里有错误：$out"
done
echo "✅ 六姿态 CHR 往返 + 合规判定全部通过"

echo "— SVG 工件跨语言交叉验证 —"
# 配色 × 姿态组合：每份 SVG 都必须能被独立解析器读回
i=0
for preset in plumber green_cap tan_hero ninja ice fire; do
    i=$((i + 1))
    f="xcheck_${preset}"
    "$HEAD" retro hero fc --scale 8 --preset "$preset" > "$f.svg"
    python3 svg_check.py "$f.svg" "$f.png" >/dev/null \
        || fail "$preset 的 SVG 无法被独立解析器读回"
    # 颜色数 = 1 背景 + 2 棋盘 + 3 实体色 = 6 以内（FC 精灵 3 色上限的体现）
    n=$(python3 -c "
from PIL import Image
print(len(Image.open('$f.png').getcolors(maxcolors=1<<20)))")
    [ "$n" -le 8 ] || fail "$preset 的 SVG 有 $n 种颜色，超过预期（调色板失控）"
    echo "✅ $preset: SVG 可读回，$n 色"
done

echo "— 调色板文本 —"
"$HEAD" retro palette > fc_palette.txt
# 64 项但去重后更少：2C02 NTSC 表里黑色重复出现多次（每亮度档的暗端）
# 这是硬件表的真实性质，不是缺陷——所以断言是"条目数 = 64"而非"唯一色数 = 64"。
entries=$(grep -o '#[0-9A-F]\{6\}' fc_palette.txt | wc -l | tr -d ' ')
uniq_n=$(grep -o '#[0-9A-F]\{6\}' fc_palette.txt | sort -u | wc -l | tr -d ' ')
[ "$entries" -eq 64 ] || fail "FC 调色板应有 64 项，实际 $entries"
[ "$uniq_n" -lt 64 ] || fail "去重后应 <64（黑色重复），实际 $uniq_n —— 调色板表可能被改坏"
echo "✅ FC 调色板 64 项（去重 $uniq_n 色，黑色在 NTSC 表中重复）"

echo ""
echo "retro 资源面回归全部通过——生成、编解码、识别、跨语言验证。"