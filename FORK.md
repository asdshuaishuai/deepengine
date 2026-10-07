# FORK.md — 与上游的分歧清单

> 本文件记录 raylib fork 相对上游的**全部改动**。每一条都必须在代码中以 `DEEPENGINE:` 注释标记，并在此处给出根因、修复与验证方式。
>
> **原则：改动越少越好。** 能修在源头就不在适配层绕，但也不为了"顺手"而扩大分歧面——每多一处改动，上游同步成本就多一分。

---

## Fork 结构

| 项 | 值 |
|---|---|
| 上游 | https://github.com/raysan5/raylib |
| 远端名 | `upstream`（fetch/push 均指向原仓库） |
| 基线提交 | `6ecf21f700642c797dd0f2f3d4b1f2c91b71711d`（2026-09-28） |
| 基线版本 | `6.1.0` |
| 我们的分支 | `deepengine` |
| 便携补丁 | `patches/raylib-fork-d1-d3.patch`（上游 + 此补丁 = 本 fork 全部差异） |
| 镜像分支 | `master`（纯上游，不含我们的改动） |
| 改动规模 | **3 个文件，+34 / −2 行** |

### 分支约定

```
upstream/master ──► master（本地镜像，只做 fetch，永不提交）
                        │
                        └──► deepengine（我们的改动全部在此）
```

- `master` 永远与上游一致，用于对比和 rebase。
- `deepengine` 承载全部改动，**不得在 master 上提交**。

---

## 分歧清单

### D1 — macOS 下 `PLATFORM_MEMORY` 计时器缺失

| 项 | 值 |
|---|---|
| 文件 | `src/platforms/rcore_memory.c`（`GetTime()`）<br>`src/rcore.c`（`InitTimer()`） |
| 类型 | 上游缺陷（macOS 平台分支遗漏） |
| 影响 | macOS + `PLATFORM_MEMORY` 下**完全不可用** |

**现象**：调用 `SetTargetFPS()` 后进程 100% CPU 死循环，永不返回。

**根因**：

`GetTime()` 与 `InitTimer()` 的 `clock_gettime(CLOCK_MONOTONIC)` 分支都写作：

```c
#if defined(__linux__) || defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__EMSCRIPTEN__)
```

**`__APPLE__` 不在列表中**。于是 macOS 上：

1. `InitTimer()` 不设置 `CORE.Time.base`（恒为 0）；
2. `GetTime()` 走不到任何分支，恒返回 `0.0`；
3. 帧限速器 `WaitTime()` 内含 `while (GetTime() < destinationTime) { }` 忙等——因为时间永不前进，**死循环**。

值得注意的是：同文件 `WaitTime()` 的休眠分支**已经**处理了 `__APPLE__`（用 `usleep`）。也就是说这个平台是"半支持"状态——**能睡但测不了**，两者叠加必然死锁。

**修复**：两个分支各加上 `|| defined(__APPLE__)`。

**验证**：`demo/fork_verify.c` 在软件光栅后端调用 `SetTargetFPS(60)` 并确认 `GetTime()` 推进（此前该调用会挂死）。

---

### D2 — 软件光栅后端的像素读回方向与通道错序

| 项 | 值 |
|---|---|
| 文件 | `src/rlgl.h`（`rlReadScreenPixels()`） |
| 类型 | 上游缺陷（后端语义不一致） |
| 影响 | 软件后端所有截图与像素读取**结果错误** |

**现象**：软件后端读回的图像上下颠倒，且红蓝通道互换。

**根因**（三重因素叠加）：

1. `rlsw` 的 `sw_framebuffer_output_fast()` / `sw_framebuffer_output_copy()` **已经**从下往上遍历行（`for (int y = height - 1; y >= 0; y--)`），即输出已经是**屏幕朝向**（top-down）；
2. 而 `rlReadScreenPixels()` 依据"glReadPixels 返回 bottom-up"的 OpenGL 约定**又翻转一次** → 双重翻转 = 上下颠倒；
3. `rlsw` 默认输出 BGRA（`RLSW_FRAMEBUFFER_OUTPUT_BGRA` 默认为 `true`，见 `rlsw.h`），但函数请求的是 `GL_RGBA` → R/B 互换。

补充：`rcore.c` 中定义的 `SW_GL_FRAMEBUFFER_COPY_BGRA` 宏**全代码库无任何引用**（疑似改名后未同步），本应协调此事的开关实际失效。

**修复**：为软件后端单独分支——只做通道交换，跳过翻转。硬件路径保持原逻辑不变。

```c
#if defined(GRAPHICS_API_OPENGL_SOFTWARE)
    // 软件后端：仅校正通道序，跳过翻转（rlsw 已输出 top-down）
#else
    // 硬件后端：保持原有翻转逻辑
#endif
```

**验证**：`demo/fork_verify.c` 截图方向与颜色均正确；且 GPU 与软件后端产出**逐字节一致**的截图（md5 相同）。

---

### D3 — `TakeScreenshot()` 不刷新渲染批次

| 项 | 值 |
|---|---|
| 文件 | `src/rcore.c`（`TakeScreenshot()`） |
| 类型 | 上游缺陷（API 时序陷阱） |
| 影响 | 帧中途截图得到空帧 |

**现象**：在 `BeginDrawing()` 与 `EndDrawing()` 之间调用 `TakeScreenshot()`，得到的是**背景色**，所有已绘制的几何丢失。

**根因**：rlgl 采用批处理。`DrawRectangle()` / `DrawText()` 等调用只是把几何写入批次队列，真正的提交发生在 `EndDrawing()`。而 `TakeScreenshot()` 直接读取帧缓冲，**不触发 flush**，因此读到的是尚未绘制任何内容的状态。

**修复**：在函数开头调用 `rlDrawRenderBatchActive()` 强制提交。

**为何修在这里而非要求调用方处理**：这是引擎的**批处理边界**问题。让每个调用点都记得先 flush，是把内部实现细节泄漏给调用方；修在函数内部则使该 API 在所有调用点都正确。这也是本项目"能修在源头就不在适配层绕"原则的直接体现。

**验证**：`demo/fork_verify.c` 在帧中途截图（无手动 flush）得到完整画面。

---

## 各后端渲染差异说明（非缺陷）

修复后，GPU 与软件后端在**纯几何**上逐像素一致，但在**纹理采样**上存在固有差异：

| 区域 | 差异 | 说明 |
|---|---|---|
| 纯几何（圆、矩形、线） | **0.00%** | 完全一致 |
| 纹理采样（文字字形、缩放旋转的精灵） | 0.3%–2.3% | GPU 硬件双线性滤波 vs rlsw 软件实现的舍入差异 |
| HUD 帧率数字 | 2.6% | 两端帧率不同导致数字不同（非渲染差异） |

**这不是缺陷**，而是两种光栅化实现的固有差异，无法也不应消除。

**对项目的影响**：AI 验证链路固定使用**软件后端**（完全确定性），因此该差异不影响验证可靠性。GPU 后端仅用于给人看的交互场景。

---

## 与上游同步

### 拉取上游更新

```bash
cd raylib
git fetch upstream
git checkout master && git merge --ff-only upstream/master   # 更新镜像
git checkout deepengine
git rebase master                                            # 变基我们的改动
```

由于改动面极小（3 处，均带 `DEEPENGINE:` 标记），rebase 冲突风险很低。

### 冲突处理原则

1. 若上游**独立修复**了同一问题 → **丢弃我们的改动**，采用上游方案；
2. 若上游**部分修复** → 保留上游实现，仅补差；
3. 若上游改动与我们冲突且无修复 → 保留我们的改动，并复核是否仍必要。

### 与上游的互动：不回馈，只同步

**本项目不向上游提交 issue 或 PR。**

原因：我们的开发方式是 AI 驱动，没有人工通读过 raylib 源码。在没有真实理解上游设计意图的情况下提 issue/PR，质量没有保障，也是对上游社区的不尊重。因此：

- **所有缺陷一律内部解决**——修在自己的 fork 分支上，用 `FORK.md` 与代码内 `DEEPENGINE:` 标记留痕；
- **对上游只有一种互动**：`git fetch` 同步；
- 若上游未来**独立修复**了同一问题，冲突处理原则见上节——届时采用上游方案，丢弃我们的改动。

这不影响许可合规：zlib 许可只要求「修改版必须标注」，不要求回馈上游。标注义务由本文件与 `NOTICE.md` 履行。

---

## 新增分歧的准入标准

向 fork 添加任何改动前，必须同时满足：

1. **无法在适配层合理规避**——若适配层能干净解决，就不该动上游；
2. **属于通用缺陷**，而非 deepEngine 专属需求；
3. **改动最小**——不做无关重构、不改变公开 API 语义；
4. **带 `DEEPENGINE:` 注释**，指向本文件的对应条目；
5. **有可复现的验证**——`demo/` 下有对应验证脚本。

不满足以上任一条件，一律拒绝。

---

## 变更记录

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-09-30 | D1–D3 | 初始 fork：修复 macOS 计时器、软件后端像素读回、截图批次刷新 |
| 2026-09-30 | 政策 | 确立「不回馈上游」策略：所有缺陷内部解决，对上游只同步不反馈 |
