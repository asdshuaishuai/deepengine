#!/usr/bin/env bash
# 四面同源核对（blueprint §8）：CLI `trace` 与 wasm `web_trace` 的体验度量逐字段相同。
#
# 主张：体验评估只有一份实现（scene/experience.mbt 的 run_experience），
#       native CLI 与 wasm 宿主只是两个调用方。
#
# 主张的反面（若这条挂了意味着什么）：
#   有人给某个消费面另写了一套策略执行/度量计算 → 同一条轨迹在两个面上
#   给出不同数字 → 所有"用浏览器验证过"的结论都不可信。
#
# 前置：两个产物都要新。缺 wasm 产物时脚本会自动增量构建。

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ENGINE="$HERE/.."
ROOT="$ENGINE/.."
HEAD="$ENGINE/_build/native/debug/build/apphead/apphead.exe"
WASM="$ENGINE/_build/wasm-gc/debug/build/web/web.wasm"
ELECTRON="${DSH_ELECTRON:-/Applications/ZCode.app/Contents/MacOS/ZCode}"

if [ ! -x "$HEAD" ]; then
    echo "缺少 headless 二进制，先跑 engine/build.sh" >&2
    exit 1
fi

if [ ! -f "$WASM" ]; then
    echo "缺少 wasm 产物，先跑： cd engine && moon build --target wasm-gc" >&2
    exit 1
fi

# wasm 产物过旧会让这条测试说谎（比的是旧代码）——如实拦住
NEWEST_SRC="$(find "$ENGINE/kernel" "$ENGINE/scene" "$ENGINE/web" -name '*.mbt' -newer "$WASM" -print -quit 2>/dev/null)"
if [ -n "$NEWEST_SRC" ]; then
    echo "wasm 产物早于源码（${NEWEST_SRC}）——请先跑： cd engine && moon build --target wasm-gc" >&2
    exit 1
fi

fail() { echo "❌ 四面同源失败: $1" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for g in platformer coinrush boxpush; do
    guide="$ROOT/examples/$g/game.guide.md"
    [ -f "$guide" ] || fail "$g 缺 game.guide.md"
    "$HEAD" trace "$guide" > "$TMP/$g.native.json" 2>/dev/null || true
    if [ ! -s "$TMP/$g.native.json" ]; then
        fail "$g 的 CLI trace 没有产出"
    fi
    out="$(ELECTRON_RUN_AS_NODE=1 "$ELECTRON" "$HERE/faces_parity.mjs" "$g" "$TMP/$g.native.json" 2>&1)" \
        || fail "$g: $out"
    echo "✅ $g: CLI 与 wasm 体验度量逐字段一致"
done

echo ""
echo "四面同源核对通过——体验评估只有一份实现。"
