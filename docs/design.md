# deepEngine 可行性验证记录与设计探索

> **本文档的性质**：可行性验证记录 + 设计探索。
> **实施规划已另有基线：[blueprint.md](blueprint.md)（引擎层总体规划，P0–P5 里程碑）**——
> 项目定位与边界以 [DECLARATION.md](../DECLARATION.md) 为准，fork 改动清单见 [FORK.md](../FORK.md)。
>
> 验证环境：raylib `6.1.0`（fork 分支 `deepengine`，改动 3 文件 / +34/−2 行）、MoonBit `0.1.20260920`、macOS 27.0 arm64
> 日期：2026-09-30

---

## 0. 结论

**基于 raylib 构建 MoonBit + AI-native 游戏引擎，技术路径成立。**

三条关键假设已用可运行代码验证：

| 假设 | 验证方式 | 结果 |
|---|---|---|
| MoonBit 能低摩擦驱动 raylib | 原生目标 + C stub 直连 | ✅ 端到端跑通 |
| 能无 GPU 确定性出图（AI 自我验证的前提） | 软件光栅后端 | ✅ 通过（需 fork 修复 D1/D2） |
| 授权允许商用 | zlib/libpng | ✅ 无限制 |

**最有价值的发现**：raylib 官方 `BINDINGS.md` 列出 177 个语言绑定，**没有 MoonBit**。这不是拥挤的赛道。

**关于 fork 的结论**：我们最初尝试零分叉（改动全留在适配层），实测后改为受管理的 fork。原因见 §5——有些缺陷在适配层只能靠"不用这个 API"绕开，那不是适配。

---

## 1. 为什么是 raylib

### 1.1 硬指标

| 维度 | 数值 | 意义 |
|---|---|---|
| 代码规模 | 40,463 行 C | 单人可通读，维护成本可控 |
| API 表面 | 619 个 `RLAPI` 函数 | 覆盖足够，不必自造轮子 |
| 示例 | 227 个 `.c` | 每个 API 有可运行参考，AI 语料友好 |
| 外部依赖 | **零**（全部 vendored） | 无供应链风险，离线可构建 |
| 平台后端 | 10 个（GLFW/SDL/RGFW/Win32/Web/DRM/Android/Memory…） | 多平台无需自建 |
| 图形后端 | OpenGL 1.1/2.1/3.3/4.3/ES2 + **软件光栅 `rlsw`** | 软件渲染是 AI 验证链路的关键 |
| 授权 | zlib/libpng | 商用闭源无限制，允许修改 |
| 编译期配置 | `CUSTOMIZE_BUILD` + `RAYLIB_CONFIG_FLAGS` | 官方提供的不改源码配置机制 |

### 1.2 架构上恰好适合「计算与渲染分离」

raylib 是**立即模式**渲染：没有保留式场景图，只有 `BeginDrawing()` → 一堆 `Draw*()` → `EndDrawing()`。

这看似缺点，对本项目却是**最大优点**：

```
raylib 的世界：C 层只管「把这一帧画出来」，不持有任何语义
适配层要补的：  MoonBit 层持有场景图 / 动画 / 布局 / 语义
```

两边职责天然正交——我们不需要跟 raylib 争「谁拥有场景」，它压根没有场景。MoonBit 的事实源 + 场景图放在上层，raylib 是纯粹的**光栅化后端**。

**这个判断是分层设计成立的基础**：正因 raylib 不持有语义，我们对语义层的所有扩展都无需触碰它。fork 改动因此可以严格限制在"通用缺陷修复"范围内。

### 1.3 与 MoonViz / deepOffice 的范式对齐

| 维度 | MoonViz | deepOffice | deepEngine |
|---|---|---|---|
| 事实源 | `.mbt.md` | `.mbt.md` / DOF | `.mbg.md` |
| 计算内核 | 100% MoonBit | 100% MoonBit | MoonBit（场景/动画/布局） |
| 后端 | SVG / PNG / Terminal | OOXML / PDF | raylib（fork） |
| Agent 接口 | 52 tools | 24 tools | 待设计 |
| 质量门 | P0–P4 不崩谓词 | 结构硬门槛 + 视觉软提示 | P0–P4 + 像素回归 |
| 输出承诺 | 可编辑的声明 | 可编辑的 PPTX | **可重放的确定性帧** |

前两个项目验证了「声明式事实源 + MoonBit 内核 + Agent 工具面 + 谓词门禁」这套组合可复制。deepEngine 是同一范式换后端——**且后端从「序列化」换成了「实时渲染」**，这是关键差异，也是主要技术挑战来源（见 §6）。

---

## 2. 分层架构

```
┌─────────────────────────────────────────────────────────────┐
│  L2  适配层（MoonBit）                          ← 主要工作   │
│      场景图 / 时间轴 / 布局 / 谓词 / 声明式事实源              │
├─────────────────────────────────────────────────────────────┤
│  L1  FFI 桥（C stub）                           ← 工作       │
│      UTF-16↔UTF-8 / 句柄 / 参数编解码                         │
├─────────────────────────────────────────────────────────────┤
│  L0  raylib fork（C）                           ← 修复集中地  │
│      平台后端 / 光栅化 / 资源加载 / 数学                       │
└─────────────────────────────────────────────────────────────┘
```

**分层纪律**（详见 DECLARATION §六）：

- **L0 修改必须逐条登记**：`FORK.md` 是唯一权威清单，代码中 `DEEPENGINE:` 注释与之对应
- **L1 无状态、无游戏语义**：只做类型/编码转换与调用转发
- **L2 承载全部语义**：所有游戏/场景/动画概念只存在于 MoonBit 层

**与 raylib 的三种合法交互方式**：公开头文件、官方编译期配置宏、构建产物。

---

## 3. MoonBit ↔ raylib 接入（实测）

### 3.1 配置方式

`moon.pkg` 中声明 C stub 与链接参数，这是 MoonBit 官方支持的路径：

```json
options(
  "is-main": true,
  "native-stub": [ "stub.c" ],
  link: {
    "native": {
      "stub-cc-flags": "-I/path/to/raylib/src",
      "cc-link-flags": "-L/path/to/raylib/src -lraylib -framework Cocoa -framework IOKit -framework CoreVideo -framework OpenGL -framework QuartzCore",
    },
  },
)
```

> **注意**：编译 stub 用 `stub-cc-flags`（不是 `cc-flags`，后者不作用于 stub）。

### 3.2 FFI 声明

MoonBit 侧声明外部函数，**指针类型参数必须标 `#borrow`**（否则报 `unannotated_ffi`）：

```moonbit
///|
#borrow(title)
extern "c" fn mbg_init(title : String) = "mbg_init"

///|
#borrow(text)
extern "c" fn mbg_text(
  text : String, cx : Double, cy : Double,
  size : Double, r : Int, g : Int, b : Int
) -> Double = "mbg_text"
```

C 侧用 MoonBit 官方头 `moonbit.h`：

```c
#include "moonbit.h"

/* MoonBit String 是 UTF-16（moonbit_string_t = uint16_t*），raylib 要 UTF-8
   —— 边界必须转码，这是实测必踩的坑 */
static const char *mbt_to_cstr(moonbit_string_t s) {
    int32_t len = Moonbit_array_length(s);
    return utf16_to_utf8(s, len);
}
```

### 3.3 接入成本实测

| 环节 | 实际情况 |
|---|---|
| MoonBit 调 C | 直接可用，`extern "c"` + `native-stub` |
| 链接系统框架 | 直接可用，`cc-link-flags` 传 `-framework` |
| 字符串传递 | **需手写 UTF-16→UTF-8 转码**（约 40 行 C，含代理对处理） |
| 返回值 | 标量零成本；结构体需拆解或返句柄 |
| 构建产物 | `_build/native/debug/build/main/main.exe` |
| 编译速度 | 首次 ~30s，增量 <5s |

**结论**：MoonBit 与 C 结合确为低摩擦。代价集中在字符串编码边界，是可一次性封装掉的固定成本。

---

## 4. AI-native 的六个必要条件

适配层要补齐的能力。六项**全部实现在 L1/L2，但第 3 项依赖 L0 支撑**——这正是 fork 修复的意义。

| # | 能力 | 验证状态 |
|---|---|---|
| 1 | **声明式事实源** — Agent 以文本表达意图并增量修改 | 🔶 格式雏形已验证（`.mbg.md`） |
| 2 | **确定性复现** — 相同输入产生相同输出 | ✅ 软件后端完全确定性 |
| 3 | **无头渲染** — 无显示器/GPU 环境可出图 | ✅ 已验证（依赖 fork D1/D2） |
| 4 | **不崩谓词** — 拒绝错误输入而非崩溃 | 🔶 仅 P0 级（解析错误回报） |
| 5 | **廉价迭代闭环** — 改一次看一次成本极低 | ✅ 热重载已验证 |
| 6 | **可解释反馈** — 拒绝时说明原因 | 🔶 部分（解析错误含行号） |

### 4.1 声明式事实源

`.mbg.md`：markdown 中 fence 内的 ops 被解析执行，prose 被忽略。同一份文件既是人类文档也是可执行程序。

```mbg
bg 11 13 19
rect card 72 96 460 236 #191e2c 28
circle orb1 0 0 8 #30a46c
orbit orb1 880 300 150 60 0     # 中心 / 半径 / 角速度 / 相位
text title 112 136 40 #eef1f7 "AI-native game engine"
```

**设计要点**：fence 机制让 Agent 可读写文件而不破坏文档性内容。

### 4.2 确定性

demo 用 `frame/60` 作为时钟，**不依赖 wall-clock**：

```c
float t = (float)framesCounter/FPS;   // 第 90 帧在任何机器上都是同一画面
```

**这不是洁癖**：若时间来自 wall-clock，同一份输入在不同机器/负载下会产生不同帧，Agent 的像素级验证完全失效。

配合**软件光栅后端**（完全确定、无驱动差异），AI 验证链路可以做到逐像素可复现。

#### 4.2.1 跨目标整数宽度陷阱（v1.4 实测，体验轨迹面）

体验面（blueprint §3.9）要求**策略 → 轨迹**在同一 seed 下跨目标逐位相同。
写探索策略的伪随机时踩到一个真实差异：

- **native 目标**（C 后端）里 MoonBit `Int` 是 **64 位**；**wasm-gc 目标**里是 **32 位**。
- 因此教科书写法 `s = (s * 1103515245 + 12345) % 2^31` 在两端会**分叉**
  （32 位下乘法溢出被截断，64 位下不会）——同 seed 在 wasm 与 native 给出不同轨迹。

选型结论：**16 位仿射发生器 `s = (s * 75 + 74) % 65537`**（Zx81 式，取值域 65537），
乘积上界约 `65536*75 ≈ 4.9e6 < 2^23`，在 32 位与 64 位下都不溢出，两端结果逐位相同。
**不要求密码学质量**——只要求两件事，且两件都有测试看住：跨目标逐位一致
（`engine/tests/faces_parity.sh`：CLI ↔ wasm 度量逐字段相同）、同 seed 可复现
（`trace_wbtest.mbt`：同 seed 必同轨迹、异 seed 必分叉）。

**推广**：凡是"要在 native 与 wasm 两面得到同一结果"的引擎逻辑，都不许依赖
目标的整数宽度或浮点结合序——轨迹采样因此全部**整型化**（位置/进度取整后再入样本）。

#### 4.2.2 自改进闭环的两个"不可复现"陷阱（v1.5 实测，递归自改进面）

递归自改进（blueprint §3.10）把"接受更好的版本"从一次性比较推进到多轮。
多轮之后，**可复现性**的敌人不再是浮点，而是"谁有权定义判据与探针"：

1. **判据漂移**：若每轮用候选自己声明的标准判，候选就获得了改写评判自己的尺子的能力
   （`progress >= 100` → `>= 0`）。实测（证伪实验）：把 `kernel/rsi.mbt` 的判定源从冻结门
   换成候选自己的门，`calibration/rsi/c3_selfserving.guide.md`（**打不通的关卡**）立刻被判
   `accept_b` 并接管 incumbent。对策：run 开始时从**基线**冻结判据 + 偏好序（`Gate`），
   候选的门只作对照并标记 `gate_shopping`。
2. **探针集膨胀**：覆盖率是"所有策略走到的格子并集"，候选多声明几条探索策略就能让它上涨，
   而关卡一个像素都没改。实测（证伪实验）：改用候选自带的策略集评测，
   `c4_morepolicies.guide.md`（与基线**同关卡**，多带 4 条策略）被接受，理由写着
   `coverage: 25 → 26`。对策：评测一律用**基线声明的**策略集（同一套探针测两版），
   候选自带的只标记 `policy_drift`。

两者的共同教训：**"比较"要成立，被判的东西与判它的尺子必须来自不同一方，且尺子在比较期间不可变**。
另一个副产品是**台账必须自带配置**（冻结门 + 停止参数）——否则 `rsi check` 复算时只能去读当前文件，
"事后把基线标准改松"就会被悄悄吞掉（复算会用新尺子量旧记录，然后报告"一致"）。

**跨工具互操作陷阱**：台账要能经别的程序转手（agent 常 `json.load`/`json.dump`），
而 Python `json.dump` **默认把非 ASCII 转成 `\uXXXX`**；本引擎的零依赖 JSON 解析器原先显式拒绝
`\u`（"内容源不需要"），于是标准工具产出的台账直接读不回来——**审计链断在解析上**。
实测：篡改台账的校准用例因此 exit 1（"不是合法 JSON"）而不是期望的 exit 2。
对策：补上 `\u` 转义（含代理对，按 UTF-16 码元逐个落成 `Char`），并加单测；
该用例随即变为 exit 2。**教训**：自造的解析器可以比标准窄，但一旦要读"别的程序写的"文件，
窄就是缺陷——尤其当那份文件是审计证据。

**MoonBit 工具链注记**：`derive(Eq)` 在本工具链会触发 `implicit_impl_as_method` 弃用警告
（隐式方法提升），本仓库的纪律是不添新警告，故枚举比较统一走 `*_name()` 辅助函数；
构造 UTF-16 码元用 `Int::unsafe_to_char()`（`String` 以码元计长，`substring(i,i+1)` 取一个码元）。

### 4.3 无头渲染

raylib 的 `PLATFORM_MEMORY` + `GRAPHICS_API_OPENGL_SOFTWARE` 可在纯 CPU 上渲染。

**实测：在 macOS 上这条路原本不可用**，需修复 D1（计时器）与 D2（像素读回）后才通。打通后，Agent 可在无显示器环境出图并做像素回归。

### 4.4 迭代闭环

热重载已验证：改 `.mbg.md` → mtime 变化 → 运行时重载，无需重启、无需重编译。

实测：运行中把 `bg 11 13 19` 改成 `bg 24 14 38`、把一个小圆改成 46px 大圆，**同一进程内立即生效**。

---

## 5. Fork 修复（实测发现的上游缺陷）

> 完整技术细节见 [FORK.md](../FORK.md)。此处记录**为何选择 fork 而非适配层规避**。

### 5.1 决策过程

初版设计坚持零分叉，把 4 项上游行为全部在适配层规避。实测后改为 fork，理由：

| 问题 | 零分叉方案 | 问题所在 | fork 方案 |
|---|---|---|---|
| macOS `SetTargetFPS()` 死锁 | 永不调用该 API | **功能残废**——一个正常 API 变成禁区 | 修复计时器，API 恢复可用 |
| 像素读回错序 | 适配层自行读像素 + 运行时探测归一化（~110 行） | workaround 庞大、易随上游变化失效 | 修复读回，适配层只需 `TakeScreenshot()` |
| 截图批次未刷新 | 调用方手动 flush | **实现细节泄漏**给使用者 | 函数内部 flush，任何调用点都正确 |
| 默认字体无 CJK | 适配层始终加载 TTF | 这**确实是**适配层的责任 | 不动上游 |

**判断标准**：若某缺陷的唯一"适配"方式是**放弃使用某个 API**，或**强迫调用方了解引擎内部机制**，那就应当修在源头。

修复的直接收益：`scene_demo.c` 的 workaround 从约 **110 行缩减为 3 行**。

### 5.2 改动规模

```
src/platforms/rcore_memory.c |  6 +++++-
src/rcore.c                  | 12 +++++++++++-
src/rlgl.h                   | 18 ++++++++++++++++++
3 files changed, 34 insertions(+), 2 deletions(-)
```

每处改动都带 `DEEPENGINE:` 注释，指向 FORK.md 条目。

### 5.3 准入标准

为避免 fork 演变成失控分叉，新增改动须**同时满足**五条：无法在适配层合理规避 / 属于通用缺陷 / 改动最小 / 带标记注释 / 有可复现验证。详见 DECLARATION §四。

---

## 6. 适配层待建清单

> 探索性清单，非承诺的实施计划。项目当前处于「声明与可行性验证已完成，尚未开发」阶段。

raylib 提供的是**绘图原语**，不是游戏引擎。适配层需在 MoonBit 侧补齐：

| 能力 | 说明 | 优先级 |
|---|---|---|
| **场景图** | 节点树、父子变换、可见性、层级 | P0 |
| **时间轴 / 动画** | 关键帧、缓动、时间重映射、确定性采样 | P0 |
| **空间布局** | 锚点、填充、约束求解 | P0 |
| **谓词引擎** | P0–P4 分级、可解释报错 | P0 |
| **`.mbg.md` 往返** | 解析 + 生成 + 无损 round-trip | P0 |
| **FFI 封装** | 隐藏编码细节、句柄管理 | P0 |
| **Agent Tools API** | MCP 工具面，JSON in/out | P1 |
| **确定性回放** | 输入序列 → 帧序列，可重放 | P1 |
| **物理** | 碰撞检测、简单刚体 | P1 |
| **输入抽象** | 把即时输入转成声明式绑定 | P1 |
| **音频调度** | 事件驱动而非即时调用 | P2 |

**工作量判断**：MoonViz 已有 layout / 谓词 / 声明式往返 / Agent API 的成熟实现，**架构决策可复用**（非代码移植，领域不同）。真正从零的是时间轴、物理、确定性回放。

---

## 7. 技术风险

| 风险 | 严重度 | 说明与对策 |
|---|---|---|
| **浮点跨架构不确定性** | 高 | 不同 CPU 浮点结果可能有微差，破坏逐像素一致。对策：固定运算顺序、关键路径定点数、回归用容差 |
| **GPU 与软件后端渲染差异** | 中 | 纹理采样有 0.3%–2.3% 固有差异（硬件滤波 vs 软件实现）。对策：**验证链路固定用软件后端**，GPU 仅用于交互 |
| **C 层内存安全** | 中 | Agent 生成的内容进入 C 层，指针错误会崩溃。对策：FFI 面只传标量 + 句柄，不传裸指针 |
| **MoonBit 生态成熟度** | 中 | 当前 0.1.x，API 可能变动。对策：固定工具链版本，CI 加版本门禁 |
| **fork 与上游漂移** | 中 | 改动面扩大后 rebase 成本上升。对策：严格执行五条准入标准；CI 校验改动清单与代码标记一致 |
| **软渲染性能** | 低 | `rlsw` 比 GPU 慢一个量级。对策：验证用低分辨率 + 少帧；交互走 GPU |
| **二进制体积** | 低 | 静态链接 raylib + MoonBit 运行时，可控 |

**关于 fork 漂移**：这是选择 fork 后**新增的主要风险**，需靠纪律控制。当前 +32 行的改动面下，rebase 成本接近于零；关键是**不放松准入标准**。

---

## 8. 待决问题

1. **产品定位**：「给 Agent 用的游戏引擎」还是「交互式内容引擎」？前者要补物理/输入/存档，后者要补富文本/表单/过渡。
2. **确定性程度**：「同机可复现」还是「跨机器逐像素一致」？当前软件后端已是后者（同机），跨架构需避免浮点差异。
3. **3D 的声明式表达**：2D 的 ops 协议已验证，3D 场景语法需单独设计，复杂度不是一个量级。
4. **与 MoonViz 的边界**：UI 布局复用 MoonViz 还是重写？
5. **运行时形态**：独立可执行，还是嵌入宿主（Viewer / 编辑器 / 网页）？

---

## 附录 A：验证产物

| 文件 | 说明 |
|---|---|
| `demo/fork_verify.c` | **fork 三项修复的验证**（帧限速不死锁、中途截图完整、颜色方向正确）★ |
| `demo/scene.mbg.md` | 声明式场景文件（`.mbg.md` 雏形） |
| `demo/scene_demo.c` | 2D / 3D / 热重载 / 确定性截图 |
| `demo/headless_probe.c` | 无窗口软件渲染验证 |
| `spike-moonbit/main/main.mbt` | MoonBit 侧：场景图 / 节点 / 动画 / 主循环 |
| `spike-moonbit/main/stub.c` | FFI 桥：UTF-16↔UTF-8 + raylib 封装 |
| `shots/fork_verify.png` | fork 验证截图 |
| `shots/final_sw.png` | 软件后端渲染（58 fps，计时器工作） |
| `shots/final_gpu.png` | GPU 后端渲染 |

## 附录 B：复现方式

```bash
# 1. 确认 fork 状态
cd raylib && git branch -vv          # deepengine 分支应领先 master
git diff master deepengine --stat    # 应显示 3 文件改动

# 2. 构建 raylib —— GPU 版（交互用）
cd src && make -j8
cp libraylib.a ../../deepEngine/lib/gpu/

# 3. 构建 raylib —— 软件光栅版（headless 验证用）
make clean && make -j8 PLATFORM=PLATFORM_MEMORY GRAPHICS=GRAPHICS_API_OPENGL_SOFTWARE
cp libraylib.a ../../deepEngine/lib/sw/

# 4. 验证 fork 修复
cd ../../deepEngine/demo
./build.sh sw fork_verify && ./fork_verify /tmp/out.png

# 5. 渲染声明式场景（两个后端）
./build.sh sw  && ./scene_demo --hidden --shot /tmp/sw.png  --frames 60
./build.sh gpu && ./scene_demo --hidden --shot /tmp/gpu.png --frames 60

# 6. MoonBit 验证
cd ../spike-moonbit && moon build --target native
./_build/native/debug/build/main/main.exe --shot out.png --frames 90
```

## 附录 C：版本锚点

```
raylib   6.1.0 @ 6ecf21f7（2026-09-28）
         分支 deepengine，改动 3 文件 / +34/−2 行
moon     0.1.20260920 (914d7da)
macOS    27.0 (26A5425a) arm64
```
