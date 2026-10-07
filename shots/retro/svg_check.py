#!/usr/bin/env python3
"""独立核对 retro SVG 工件：解析 rect 元素 → 重建像素图 → PNG。

这是对 clip_svg/frame_svg 的**外部**验证：SVG 由引擎产出，
这里用完全独立的解析器读回来，确认它真的画对了像素。

用法: python3 svg_check.py <in.svg> <out.png>
"""
import re
import sys
from PIL import Image


def parse_svg(path):
    """极简 SVG rect 解析：只取 fill=#RRGGBB 的 rect（跳过棋盘 pattern）。"""
    src = open(path, encoding="utf-8").read()
    m = re.search(r'width="(\d+)"\s+height="(\d+)"', src)
    w, h = int(m.group(1)), int(m.group(2))
    img = Image.new("RGB", (w, h), (16, 16, 22))
    # pattern 里的 rect 是棋盘底，跳过（它们在 <defs> 内）
    defs_end = src.find("</defs>")
    body = src[defs_end:] if defs_end > 0 else src
    for rm in re.finditer(
        r'<rect x="(\d+)" y="(\d+)" width="(\d+)" height="(\d+)" fill="#([0-9A-Fa-f]{6})"',
        body,
    ):
        x, y, rw, rh = (int(g) for g in rm.groups()[:4])
        rgb = rm.group(5)
        color = (int(rgb[0:2], 16), int(rgb[2:4], 16), int(rgb[4:6], 16))
        for yy in range(y, min(y + rh, h)):
            for xx in range(x, min(x + rw, w)):
                img.putpixel((xx, yy), color)
    return img


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    img = parse_svg(sys.argv[1])
    img.save(sys.argv[2])
    colors = img.getcolors(maxcolors=1 << 20)
    print(f"{sys.argv[1]} -> {sys.argv[2]}  {img.size[0]}x{img.size[1]}  colors={len(colors)}")


if __name__ == "__main__":
    main()