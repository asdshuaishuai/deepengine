#!/usr/bin/env bash
# 构建 deepEngine 的两个二进制（同一 stub，不同 raylib 后端）：
#   app     → GPU（GLFW+OpenGL），交互游玩
#   apphead → 软件光栅（PLATFORM_MEMORY），headless 验证
#
# 依赖：raylib fork（见 ../FORK.md）已构建出 lib/gpu 与 lib/sw 两个库。

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

if [ ! -f "$ROOT/lib/gpu/libraylib.a" ] || [ ! -f "$ROOT/lib/sw/libraylib.a" ]; then
    echo "缺少 raylib fork 库。请先构建：" >&2
    echo "  cd raylib/src && make -j8 && cp libraylib.a $ROOT/lib/gpu/" >&2
    echo "  make clean && make -j8 PLATFORM=PLATFORM_MEMORY GRAPHICS=GRAPHICS_API_OPENGL_SOFTWARE && cp libraylib.a $ROOT/lib/sw/" >&2
    exit 1
fi

cd "$HERE"
moon build --target native

GPU="$HERE/_build/native/debug/build/app/app.exe"
HEAD="$HERE/_build/native/debug/build/apphead/apphead.exe"
echo ""
echo "deepengine (GPU):      $GPU"
echo "deepengine-headless:   $HEAD"
echo ""
echo "用法（推荐指引入口 game.guide.md）："
echo "  $GPU run     <game.guide.md>                # 交互游玩"
echo "  $HEAD verify <game.guide.md> --shot p.png  # headless 验证（exit 0=PASS 2=FAIL）"
echo "  $HEAD inspect <game.guide.md>              # 只装配不渲染，看源载入情况"
echo "  $HEAD shot   <game.guide.md> --out p.png   # 确定性截图"
echo ""
echo "兼容旧 inline 入口（.mbg.md，回归基线）：把 <game.guide.md> 换成 <game.mbg.md>"
echo ""
echo "自检："
echo "  moon test --target native    # 84 个单测"
echo "  ./calibration/calibrate.sh   # 验证器自校准（两入口）"
echo "  ./tests/regression.sh        # 双入口等价比对"
