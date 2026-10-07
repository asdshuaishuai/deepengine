# NOTICE — 第三方组件与许可声明

本文件列出 deepEngine 使用的第三方组件及其许可。分发本项目的任何形态（源码、二进制、产品集成）时，**必须**随附本文件。

---

## 1. raylib（修改版）

**用途**：图形渲染与平台抽象后端（本项目唯一的重量级依赖）

| 项 | 值 |
|---|---|
| 项目 | raylib |
| 仓库 | https://github.com/raysan5/raylib |
| 版权 | Copyright (c) 2013-2026 Ramon Santamaria (@raysan5) |
| 许可 | zlib/libpng |
| 基线版本 | `6.1.0` |
| 基线提交 | `6ecf21f700642c797dd0f2f3d4b1f2c91b71711d` |
| **修改情况** | **已修改（修改版）** |

### ⚠️ 修改版声明

本项目**使用并分发了 raylib 的修改版本**。依据 zlib/libpng 许可第 2 条（"Altered source versions must be plainly marked as such, and must not be misrepresented as being the original software"），我们在此**明确标注**：

**本版本不是原始 raylib，而是 deepEngine 的修改版。**

**改动内容**（完整说明见 [FORK.md](FORK.md)）：

| 编号 | 文件 | 改动 |
|---|---|---|
| D1 | `src/platforms/rcore_memory.c`、`src/rcore.c` | 为 `GetTime()` / `InitTimer()` 补上 `__APPLE__` 分支，修复 macOS 下 `PLATFORM_MEMORY` 计时器缺失导致的 `SetTargetFPS()` 死锁 |
| D2 | `src/rlgl.h` | 修正软件光栅后端的像素读回：跳过重复的垂直翻转，校正 BGRA/RGBA 通道序 |
| D3 | `src/rcore.c` | `TakeScreenshot()` 增加渲染批次刷新，修复帧中途截图得到空帧的问题 |

**改动规模**：3 个文件，+34 / −2 行。每处改动在源码中以 `DEEPENGINE:` 注释标记，并指向 `FORK.md` 的对应条目。

**未改动的部分**：raylib 的其余全部代码保持原样。

**如果你需要原始 raylib**：请从 https://github.com/raysan5/raylib 获取。

### 许可全文

```
Copyright (c) 2013-2026 Ramon Santamaria (@raysan5)

This software is provided "as-is", without any express or implied warranty. In no event
will the authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial
applications, and to alter and redistribute it freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not claim that you
  wrote the original software. If you use this software in a product, an acknowledgment
  in the product documentation would be appreciated but is not required.

  2. Altered source versions must be plainly marked as such, and must not be misrepresented
  as being the original software.

  3. This notice may not be removed or altered from any source distribution.
```

### 依赖说明

raylib 本身是零外部依赖设计，其所需的一切第三方库均已 vendored 在 `raylib/src/external/` 内，并随 raylib 一并适用上述 zlib/libpng 许可。其中包括（不限于）：

- GLFW（窗口/输入，zlib/libpng）
- glad（OpenGL 加载器，MIT）
- stb_image / stb_truetype / stb_vorbis / stb_rect_pack（public domain / MIT）
- miniaudio（public domain / MIT-0）
- dr_flac / dr_mp3 / dr_wav（public domain / MIT-0）
- cgltf（MIT）
- rlsw（软件光栅器，zlib/libpng）

各库的完整许可文本见其源文件头部或 `raylib/src/external/` 内对应文件。

---

## 2. MoonBit 编译器与标准库

| 项 | 值 |
|---|---|
| 项目 | MoonBit |
| 仓库 | https://github.com/moonbitlang |
| 用途 | 适配层实现语言与编译工具链 |
| 许可 | 见官方仓库 |

MoonBit **不随本仓库分发**，仅在开发/构建时作为工具链使用。

---

## 3. deepEngine 适配层

| 项 | 值 |
|---|---|
| 版权 | Copyright (c) 2026 deepEngine contributors |
| 许可 | MIT |
| 与 raylib 的关系 | 独立的衍生作品（**不修改** raylib，仅调用其公开 API） |

### 许可全文

```
MIT License

Copyright (c) 2026 deepEngine contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 4. 许可兼容性说明

- raylib 的 **zlib/libpng** 许可与适配层的 **MIT** 许可**完全兼容**，无任何冲突。
- raylib 为 **修改版**，其 zlib/libpng 许可继续适用于 fork 后的代码；我们的修改部分同样在该许可之下（zlib/libpng 允许修改与再分发，前提是标注改动——我们已在 §1 标注）。
- 适配层的 MIT 许可**仅适用于适配层自身**，不改变 raylib 的许可状态。
- 我们不以任何方式声称拥有 raylib 或其衍生权利。

---

## 5. 致谢

deepEngine 的图形能力完全来自 raylib。感谢 Ramon Santamaria (@raysan5) 与 raylib 社区多年来的工作——一个 40,000 行、零依赖、可被单人通读的 C 图形库，是本项目得以成立的前提。

如果你使用 deepEngine 构建了产品，我们建议（但不强制要求）在产品的致谢中同样提及 raylib。
