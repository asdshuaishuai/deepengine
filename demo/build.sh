#!/usr/bin/env bash
# Build the deepEngine verification probes against raylib.
#
# raylib source is used AS-IS — never modified (see DECLARATION.md §三).
# Two backends are built from the same pristine source, differing only in
# compile-time flags (raylib's official CUSTOMIZE_BUILD mechanism):
#
#   gpu — PLATFORM_DESKTOP (GLFW + OpenGL), for interactive runs
#   sw  — PLATFORM_MEMORY + software rasterizer, for headless deterministic runs
#
# Usage:
#   ./build.sh                    # build everything with the gpu backend
#   ./build.sh sw                 # build everything with the sw backend
#   ./build.sh gpu zerofork       # build one target

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RAYLIB_DIR="${RAYLIB_DIR:-$HERE/../../raylib}"
BACKEND="${1:-gpu}"
ONLY="${2:-}"

# Frameworks required on macOS; harmless elsewhere via the guard below
FRAMEWORKS=""
if [ "$(uname -s)" = "Darwin" ]; then
    FRAMEWORKS="-framework Cocoa -framework IOKit -framework CoreVideo -framework OpenGL -framework QuartzCore"
fi

case "$BACKEND" in
    gpu) LIB="$HERE/../lib/gpu/libraylib.a" ;;
    sw)  LIB="$HERE/../lib/sw/libraylib.a" ;;
    *)   echo "unknown backend: $BACKEND (expected: gpu | sw)" >&2; exit 2 ;;
esac

if [ ! -f "$LIB" ]; then
    echo "missing library: $LIB" >&2
    echo "build raylib first, e.g.:" >&2
    echo "  cd $RAYLIB_DIR/src && make -j8                                          # gpu" >&2
    echo "  cd $RAYLIB_DIR/src && make -j8 PLATFORM=PLATFORM_MEMORY \\" >&2
    echo "      GRAPHICS=GRAPHICS_API_OPENGL_SOFTWARE && cp libraylib.a $HERE/../lib/sw/" >&2
    exit 1
fi

build_one() {
    local name="$1"
    echo "  [$BACKEND] $name"
    # shellcheck disable=SC2086
    clang -std=c99 -O2 -Wall "$HERE/$name.c" -I"$RAYLIB_DIR/src" "$LIB" $FRAMEWORKS -o "$HERE/$name"
}

echo "backend=$BACKEND"
echo "lib=$LIB"

if [ -n "$ONLY" ]; then
    build_one "$ONLY"
else
    build_one fork_verify
    build_one scene_demo
    build_one headless_probe
fi

echo "done"
