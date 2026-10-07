# lib/ —— raylib fork 构建产物

`lib/gpu/libraylib.a`（交互）与 `lib/sw/libraylib.a`（headless 验证）由
[raylib fork](../FORK.md)（D1–D3 修复版）构建后拷入，不入库：

```bash
# 兄弟目录克隆 fork 并打补丁（或直接用上游 + patches/raylib-fork-d1-d3.patch）
cd .. && git clone https://github.com/raysan5/raylib.git && cd raylib
git apply ../deepEngine/patches/raylib-fork-d1-d3.patch

# GPU 版
cd src && make -j8 && cp libraylib.a ../../deepEngine/lib/gpu/
# SW 版（headless）
make clean && make -j8 PLATFORM=PLATFORM_MEMORY GRAPHICS=GRAPHICS_API_OPENGL_SOFTWARE
cp libraylib.a ../../deepEngine/lib/sw/
```
