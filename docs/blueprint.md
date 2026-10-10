# deepEngine 引擎层总体规划（Blueprint v1.1）

> **文档性质**：实施级总体规划（**已批准基线**）。纸面设计，未开始编码——可行性验证已全部通过（见 [design.md](design.md)），本文回答"接下来建什么、按什么顺序建、每一步的判据是什么"。
> **v1.1 → v1.2（2026-10-01，方向修正）**：**解除「唯一事实源」约束**——那是 moonviz/deepOffice（文档/原型域）的纪律，游戏引擎的原生路径是**衍生**：多种来源（.mbg.md 加载、运行时 API 生成、agent 即时创建）→ 内核世界 → 派生一切可观察物。`.mbg.md` 从"唯一事实源"降格为**入口格式之一（加载器）**；**内核 API 升格为一等接口**（spawn/修改运行时实体）；往返无损不再是硬承诺（入口文件可 round-trip，运行时状态不必）。验证协议不变（探针针对内核状态，无论内容从哪来）。
>
> **v1.2 → v1.3（2026-10-01，本次实施）**：v1.2 只说了"解除约束"，没说"那文件到底该剩什么"。**同门项目的单一事实源模式在游戏域是错的**——游戏开发本身不是单一的，强行单文件会把关卡数据、探针脚本、渲染配置、装配指令全部揉进一份文档，让每次改动都在"文档即程序"与"程序即文档"之间取舍。本轮把入口拆成三层职责：
> - **生命指引**（`game.guide.md`）——只回答三个问题：**有哪些东西**（内容源清单）、**怎么解析**（parser 名）、**怎么渲染与组装**（render / assembly 配置）。它**不携带**坐标、参数、脚本、地图；
> - **内容源**（`level.json` / `probes.json` / 未来任意格式）——关卡几何与行为探针，配零依赖 JSON 解析器（§2.4）；
> - **运行时 API**——内容由进程内 spawn 生成（v1.2 已有）。
>
> 三者并列进入**装配层**（§2.4），汇入**同一个 GameSpec 与同一个内核**——没有两套世界构建路径。旧 `.mbg.md` 降为 `inline` 入口保留，**双入口等价由 `engine/tests/regression.sh` 机械断言**（逐探针结果比对）：这是"重构而非行为变更"的可核对证据。
>
> **v1.4 → v1.5（2026-10-10，本次实施）**：v1.4 把"接受更好的版本"做成**一次性**裁决（`compare`）。
> 递归自改进（RSIGame）要跑**多轮**，而多轮会立刻涌现两个 v1.4 没防的面，且都以"看起来像进步"的面目出现：
> - **判据漂移（gate shopping）**：`compare` 的标准取自候选声明的——单轮无妨；多轮就等于让候选**改写评判自己的尺子**（把 `progress >= 100` 改成 `>= 0`），下一轮必然"进步"。这是自改进闭环最经典的 reward hacking。
> - **探针集膨胀**：覆盖率是"所有策略走到的格子并集"，候选只要多声明几条探索策略就能让它机械上涨，而**关卡一个像素都没改**——比改判据更隐蔽，因为外观恰好是"测得更严谨"。
>
> **同一轮顺手把 `compare` 的同一个洞补上了**：v1.4 的 `compare` 也把标准取自候选声明的——这在单轮里就已经是真实漏洞（实测：候选自带一份宽松 `criteria.json`，`compare base c3_selfserving → exit 0 accept_b`，一份**打不通**的关卡被判成"改进"）。现在 `compare` 与 `rsi` **共用同一个裁决单元**（`kernel.judge_versions`）：判据与探针都从基线冻结，候选的声明只作对照；新增退出码 **4 = 检测到操弄判据**（0/2/3 合同不变）。
>
> 本轮把自改进的**选择半环**做成一等面（§3.10）：run 开始时**冻结判据门**（取自基线，候选无法影响）与**冻结策略集**（同一套探针测两版）；候选自己声明的门/策略集只作对照，如实标记 `gate_shopping` / `criteria_drift` / `policy_drift`；驱动加**轮预算**（§5.3 的 T=5）与**连续被拒即停**；每轮记 base/cand **体验指纹**形成血统，台账（stdout 单文档）自带冻结门与停止参数，`rsi check` 可按台账**逐轮复算**（改台账 / 改候选内容 / 改基线配置都会红）；被拒轮次按决定项归类成 `rejection_memory`。新增 `kernel/rsi.mbt`、CLI `rsi run` / `rsi check`、自校准 `calibration/rsi/` 四例（真改进 / 退化 / 自私尺子 / 探针膨胀）+ 台账篡改必红，并为 `scene/json.mbt` 补上标准 JSON 的 `\u` 转义（经 Python/`json.dump` 转手的台账必须能读回，否则审计链会断在解析上）。**边界照旧**：候选由 agent 产生，引擎只做选择 + 记账 + 可核验，绝不自己改关卡去"提升"度量（§11）。
>
> **v1.3 → v1.4（2026-10-10）**：外部两项递归闭环工作共同指向本引擎完全缺失的一层——**主分之外没有"体验"通道**：
> - **RGC**（Recursive Game Creator，arXiv 2610.08621）的 Designer→Builder→**Player**→**Reviewer** 体验导向 harness。其 Player 是"通过程序化接口创建并执行**可复用策略**来高效采集**多样轨迹**，以缓解 GUI 慢采集造成的评估偏差"；其 Reviewer 用"**轨迹度量 + 显式文本偏好 + 游戏专属标准**"评测，接受更好的版本并给出下一轮改进意见。
> - **RSIGame**（递归自改进）：把"接受更好的版本"作为闭环的收敛判据。
>
> 本轮把 harness 需要的机械能力做成本引擎原语（§3.9）：**程序化玩家策略**（`script` / `explore(seed,frames)`，同 seed 必同轨迹）→ **逐帧轨迹**（整型化、跨架构确定、终态早停）→ **体验度量**（进展/覆盖/直达/停滞/闲置/多样性；策略集聚合：能力取上限、风险取下限、覆盖取并集）→ **game-specific criteria + 显式偏好序**（文本，不是代码）→ **版本裁决**（`accept_b` / `keep_a` / `inconclusive`）。新增内容源 `policies.json` / `criteria.json`、消费面 `trace` / `compare`（native CLI）与 `web_trace`（wasm 面）、自校准 `calibration/experience/`（拒绝退化 / 接受改进 / **同版不可判为改进**）与 `tests/faces_parity.sh`（CLI 与 wasm 的体验度量逐字段相同）。**主分不变**：体验度量不进 verify 的 binary reward（§3.5 的分离纪律同样适用）。
>
> **v1.0 → v1.1**：批准基线并定策两项——① P2 首发骨架定为 `gravity_side` + `grid_logic`；② **程序化优先资产策略**（Minecraft 思想继承）：初期不设真实素材，一切视觉为计算像素、一切音频为合成电子音（§6.0）。
> **实施进度（2026-09-30）**：**MVP 已达成**——"AI agent 驱动产生小游戏"闭环打通。P0 内核切片（帧步进/语义输入/runtimeState/探针/binary 报告，15/15 单测）+ P1 事实源切片（.mbg.md 解析 + 不崩谓词 P0）+ P2 首族骨架（gravity_side）+ CLI 消费面（run/verify/shot，GPU+软件光栅双二进制）。两个示例游戏 verify 7/7 PASS，其中 coinrush 为 agent 仅写 .mbg.md 创作、首验即过。详见 `engine/README.md` 与主 README。**第二轮（同日）**：P0 退出判据补全（`engine/calibration/` 三件套全绿：oracle 接受 / starter 拒伪 / nop 拒空）；P2 两族达成（grid_logic 第二族：`mode grid` + ASCII `level` 地图 + 推箱语义，`examples/boxpush` 8/8 PASS——两族共享全部管线，仅一个词切换）；P3 起点达成（程序化视觉：金币旋转/玩家眼睛/平台 bevel/尖刺三角/终点飘旗，零图片；chiptune 音效：方波扫频合成四音效，零音频文件）。单测 21/21。下一步：MCP 面（P4）、骨架 errors.md 沉淀、程序化生成器参数化（shape/seed）。
>
> **输入**：① 我们自己的可行性验证（raylib fork D1–D3 / MoonBit FFI / headless 确定性渲染）；② deepOrca 游戏开发调研六项目全景（OpenGame / threejs-game-skills / CCGS / VibeGame / GameFactory-3A / Sprite Studio，含 GamePhanes 评测侧与 3D 域姊妹篇）；③ 同门 moonviz / deepOffice 的已验证范式；④ **体验导向递归闭环两项外部工作**（RGC arXiv 2610.08621 / RSIGame，用户提供参考——见 §3.9 与附录映射）。
>
> 日期：2026-09-30。调研原文：`deepOrca/docs/research/gameStudio/`。遵循调研总口径——**调研仅供参考，引擎以本文的实际设计为准**；本文每一条采纳都注明出处与转化方式。

---

## 0. 一句话与证据链

**deepEngine = 确定性玩法内核 + 衍生式内容管线 + 验证即引擎能力。**

内容从多种来源进入内核（.mbg.md 加载 / 运行时 spawn API / agent 即时创建），一切可观察物从内核状态派生——引擎原生路径，v1.2 起「唯一事实源」不再是本项目的约束（那是 moonviz/deepOffice 的纪律，不是引擎的）。

这不是口号，每一段都有调研证据支撑：

| 设计支柱 | 证据 | 出处 |
|---|---|---|
| **框架 > 模型**：投资骨架/协议/验证层的边际收益大于换更强模型 | 消融：骨架库+活协议合计 BH 60.5→72.4（+12）；专用模型 GameCoder-27B 仅 +1.1；同框架换 Claude 直接到 72.4 | OpenGame arXiv 2604.18394 |
| **AI 只产源数据，引擎确定性派生一切可观察物** | 三域三次独立出现：2D 精灵（Sprite Studio "AI 只画源画，绑定与动画必须确定性渲染"）、3D 重建（img2threejs "Scripts enforce, the model judges"）、3D 运动（CozyClay sparse IK 修正） | Sprite Studio / 3D 域报告 |
| **程序化优先，初期零素材**（Minecraft 思想继承） | 一切视觉 = 参数化像素生成、一切音频 = 合成器电子音 → 资产即参数、参数即文本，整个游戏 100% 可 diff、可复现、零外部依赖；OpenGame 的 ABC 记谱→本地合成证明零模型音频路线可行 | Minecraft 先例 + OpenGame 音频管线 |
| **验证不是可选项**："能跑 ≠ 可玩"，完成 = 实现 + 验证证据 | 三方独立收敛：VibeGame "不算证据"四反例、GameFactory 6 维评审、GamePhanes binary 主分 | 三项目 |
| **玩法内核必须无渲染可测** | `UI → Mechanic → runtime` 单向依赖；Mechanic 无 UI/渲染器/截图可编译测试评估 | GameFactory-3A Mechanic 契约 |
| **把 LLM 失效模式编译进 API 语义，而非写进提示词** | 省略即继承 / pivot 级联 / 模板强制，每条针对一个可预测的 LLM 失效 | VibeGame 四约束 |
| **验证器自身也要校准** | starter 必败 + oracle 必成 + NOP=0；自审计 rubric（evidence_basis / unsupported_claims） | GamePhanes |

**最大的单一投资依据**是 OpenGame 消融表——骨架库与活协议是全部机制里贡献最大的组合（+12 BH），而我们的引擎恰好能把这两样做成**引擎原语**而非提示词资产。

---

## 1. 总体架构（五层）

对已验证三层结构的**关键修订**：把 MoonBit 层拆成「玩法内核」与「场景呈现」两层。依据是 GameFactory 的 Mechanic 契约——内核必须能在无渲染器、无 UI、无截图的环境下被探针直接驱动，这正是 headless 验证的架构前提。

```
┌─────────────────────────────────────────────────────────────────┐
│  F  消费面（四面同源，moonviz 模式）                              │
│     native 可执行 · CLI（stdin ops）· MCP 工具面 · 内核 wasm      │
├─────────────────────────────────────────────────────────────────┤
│  L2 玩法内核  kernel/（纯 MoonBit，零渲染依赖）          ← 核心   │
│     状态机 / 帧步进 / 语义输入 / 探针协议 / runtimeState          │
│     契约：state · events · commands（Mechanic 等价物）            │
├─────────────────────────────────────────────────────────────────┤
│  L1 场景呈现  scene/（MoonBit）                          ← 核心  │
│     场景图 / 动画时间轴 / 布局 / 资产清单 / 谓词门禁               │
│     .mbg.md 解析与生成（往返无损）                                │
├─────────────────────────────────────────────────────────────────┤
│  B   FFI 桥  bridge/（C stub，已验证）                            │
│     UTF-16↔UTF-8 / 句柄 / flush 哨兵封装                          │
├─────────────────────────────────────────────────────────────────┤
│  L0 光栅后端  raylib fork（已就位：D1–D3，3 文件 +34/−2）         │
│     GPU（交互）+ 软件光栅（验证，逐像素确定）                      │
└─────────────────────────────────────────────────────────────────┘
```

### 依赖方向（硬约束）

```
F → L2 → L1 → B → L0          渲染层绝不反向污染内核
```

- **L2 不 import 任何渲染符号**。内核的测试与探针在无窗口环境直接运行（`moon test` 级别）。
- L1 持有场景语义，但**不持有玩法状态**——玩法状态只在 L2。
- L0 只做光栅化（fork 纪律见 [FORK.md](../FORK.md)，五条准入标准不变）。

### 三态状态（run 不可变）

每个构建产物带三态：`generation_status / assembly_status / verification_status`。
**生成只能设 generated；装配才能设 assembled；验证通过才能设 verified。静态检查或场景文件解析成功永远不能声称 verified。**（GameFactory 三态直移）运行记录不可变，修复创建新 run 并记 `parent_run_id` / `repair_of` / 失败摘要。

---

## 2. 入口与衍生：指引是生命指引，内容源与内核 API 并列

> **v1.2 修订**：本节原题为「事实源」，现改为「入口与衍生」。`.mbg.md` 是 agent 叙事友好的**入口格式**（加载器产物），与**运行时 spawn API**（v1.2 起内核一等公民）、程序化生成器并列，都是内容来源。内核世界是唯一的**运行时真相**；入口文件可往返，运行时衍生状态不必回写。
>
> **v1.3 实施**：本节的三层结构已落地为 `game.guide.md` + `level.json` + `probes.json`（§2.4）。

**全文本、可 diff、可由 agent 与编辑器双向编辑**——"The whole game structure is explicit data"（VibeGame 原则直移）。

### 2.4 内容源与装配层（v1.3 实施）

入口按职责切分为三块，**没有一块是唯一事实源**：

```
mygame/
├── game.guide.md     # 生命指引：有哪些东西 / 怎么解析 / 怎么渲染组装
├── level.json        # 内容源：关卡几何（parser json_level）
├── probes.json       # 内容源：行为探针声明（parser json_probes）
└── errors.md         # 失败记忆（每骨架/每项目，见 §5）
```

**指引文件回答三个问题，不回答第四个**：

| 指引声明 | 含义 | 不含 |
|---|---|---|
| `source <名>` + `path` + `parser` | **有哪些东西、怎么解析** | 源的内容本身 |
| `render` 层配置 | **怎么渲染**（层、参数、程序化种子来源） | 坐标、图元、素材字节 |
| `assembly` | **怎么组装**（HUD 字段、挂载关系） | 实体数组、碰撞体 |

关卡数据（坐标、物理参数、ASCII 地图）、行为脚本、探针期望——**全部住在内容源里**。

**装配层**（`engine/scene/assemble.mbt`）按指引声明的顺序跑各 parser，
合并成唯一一份 `GameSpec`，再 `build` 成内核世界。三条纪律：

1. **零 IO**：`assemble` 收一个 `(String) -> String?` 的 reader，不碰文件系统。
   native 面注入 `mbg_read_file`，wasm 面注入内存注册表（`web_put_source`）——**同一份装配逻辑**。
2. **未注册 parser 报错**，不静默忽略。内容源缺失报错，除非声明 `optional`。
3. **双入口汇入同一结构**：旧 `.mbg.md` 作为 `inline` parser 走同一装配路径，
   没有第二套世界构建（`DECLARATION.md` 禁 workaround 重复）。

**等价性是可核对的**：`engine/tests/regression.sh` 断言双入口在同一内核上产出
**逐探针一致**的结果。这条断言的意义——若它挂了，说明"重构"偷偷改成了"行为变更"，
下游全部证据作废（blueprint §3.6「代码一变，上轮证据作废」）。

### 2.1 四条 AI-native 语义（编译进 schema，不是提示词）

VibeGame 四约束逐条转化。**每条对应一个可预测的 LLM 失效模式**：

| 语义 | 规则 | 对抗的失效 |
|---|---|---|
| **省略即继承** | `collider.w/h` 省略 → 继承视觉 `displayW/H`；一切可选字段的原则："When in doubt, omit; the inherited default is usually what you want" | 防御性写码 → 值分裂在场景与脚本两处，双 source of truth |
| **pivot 四级级联** | `clip.pivot > frame.pivot > asset.pivot > [0.5,1]`（脚锚默认）；碰撞体 pivot 显式 > 视觉解析原点 > `[0.5,0.5]` | 跨帧尺寸不一时的原点漂移（角色"浮空"） |
| **UI 走声明路线** | HUD/菜单/文本是声明式节点（引擎自绘 TTF），不是"随手用最方便的 API"；未样式化的默认矩形 = placeholder，**不得交付** | AI 抄近路用底层 API 产生不可维护 UI |
| **程序化实体必须走模板** | `spawn nodes/bullet.node.mbg.md` 是唯一实例化途径；**模板必须在某场景数据里可见**（disabled 占位引用即可）——只出现在脚本字符串里的路径对静态扫描不可见 | 模板未预载 → 运行时才发现的实例化失败 |

**配套单位纪律**：一切尺寸/偏移为 world px，无第二坐标系；禁止脚本运行时改碰撞体尺寸/位置（攻击判定是专用子节点，只 enable/disable）——VibeGame errors.md #4/#5 的教训前置为 schema 禁令。

### 2.2 一等字段：帧耦合事件

```mbg
frame_events attack {
  clip: "attack"
  hit_start: 3      # 玩法读帧索引的唯一合法入口
  hit_end: 5
  on: "hitbox_enable"
}
```

玩法逻辑读原始帧索引**必须**先在此声明（VibeGame `Frame-coupled events` 直移）。这是 placeholder 资产可被无损替换的前提——资产换了帧数，耦合点仍可追溯。

### 2.3 资产 key 四点一线

`manifest 条目 key → 场景/节点引用 → 动画 clip 帧名 → 代码引用`，静态检查强制四点一致（OpenGame asset_protocol 的 key 一致性链直移——这是其 debug_protocol 里最高频错误类别）。

---

## 3. 确定性与可验证性（引擎的核心竞争力）

这一章是引擎区别于"又一个 raylib 绑定"的全部理由。**验证能力做进引擎，agent 才能闭环。**

### 3.1 帧步进（已验证基础的进化）

```moonbit
// kernel 顶层 API —— 帧推进是纯函数语义
let s2 = kernel.step(s1, input)     // 一帧 = 一次纯调用
let sN = kernel.run(s0, inputs, 90) // 跑到第 90 帧，确定性
```

- 时间 = `frame/60`（已验证），**无 wall-clock 路径**。
- `continue(N)` 语义：调用返回时恰好 N 次 update 已完成——"agent 的墙上时钟与游戏时间解耦"（VibeGame 帧门设计直移，但我们的实现更干净：MoonBit 无 JS 事件循环约束，帧步进就是函数调用，不需要 WS/HTTP 挂起）。
- 渲染是状态的**纯投影**：`render(state) → pixels`。软件光栅后端逐像素确定（已验证）。

### 3.2 语义输入注入

```moonbit
kernel.press("jump")    // 语义动作，不是键码
kernel.hold("right", frames: 12)
kernel.release("jump")
```

- 注入点在**内核输入边界**（input map：语义动作 → 键位，是数据不是代码）。
- `isPressed/isHeld/isReleased` 对游戏逻辑照常工作；释放边由帧步进合成（不依赖真实事件循环）。
- 回放 = 输入序列 + 初始状态 → 必然重放（确定性回放的实现基础）。

### 3.3 可观察性原则："everything important must stay observable"

内核不知道游戏里什么重要，所以**游戏自声明**：

```moonbit
pub fn runtime_state(self) -> Map[String, Json]  // 每个节点可选实现
```

- 应暴露清单（VibeGame 同款判据）：激活的面板/模态、选中实体、当前教学步、影响验收的 HUD 值、AI 阶段/待执行动作。
- 快照（`kernel.snapshot()`）= 场景结构 + 全部 runtimeState → **状态类验收判据走快照断言，不走截图**（比截图+VLM 硬得多）。
- 配套纪律：加新状态机时，`runtime_state` 对照需求判据的审计是交付前最后一步（errors.md #6 教训）。

### 3.4 探针协议（headless 反馈通道）

```
DE_EVENT {"t":"state","node":"player","state":"JUMP","frame":123}
DE_EVENT {"t":"hp","node":"boss","value":87}
DE_EVENT {"t":"probe","name":"coyote_third_tick","pass":true}
```

- 行前缀 JSON 协议（GamePhanes `GAMEPHANES_EVENT` 直移）：grep 友好、引擎日志穿插不干扰解析、坏行可单独报告。
- headless 模式（软件光栅，已验证）是唯一验证渲染路径；GPU 仅用于给人看。

### 3.5 评分模型：binary 主分 + 诊断分（分离）

```json
{
  "reward": 0,                    // binary：全部必需行为断言过 = 1，否则 0
  "diagnostics": { "passed": 16, "total": 18,
                   "failed": ["coyote_third_tick", "land_buffer_jump"] },
  "evidence_basis": ["snapshot@f0", "snapshot@f90", "pixels@f90"],
  "unsupported_claims": ["未证明不同 seed 的一致性", "未覆盖菜单返回路径"],
  "contract_fingerprint": "sha256:…"
}
```

- **主分零 LLM**：必需断言全过才 PASS（GamePhanes binary 主分直移）。
- **诊断分只做 near-miss 定位，绝不替代主分**——Kimi K3 案例（16/18 过、正常收尾、reward 仍 0，死在两个 off-by-one）证明"长任务正常收尾"完全不能隐含"边界正确"。
- **自审计三字段**（GamePhanes rubric 直移）：agent 读报告时明确知道"哪些**没**被证明"，防过度自信跳过复验。
- 断言集必须**显式枚举边界条件**（coyote 第三帧收/第四帧拒这类），因为正常路径通过不隐含边界正确。

### 3.6 "不算证据"清单（引擎验收协议，直接采用）

| 不算证据 | 引擎对策 |
|---|---|
| "帧在动" ≠ 可运行 | 粒子/tween 维持帧熵而玩法逻辑已死——验收要求**状态 diff**，不收"画面在动" |
| eval 单测 ≠ 证据 | 单测绕过游戏循环，只证明函数存在，不证明玩法可达——验收走内核全循环探针 |
| 旧轮次证据过期 | 代码一变，上轮证据作废——证据绑定 run 的 contract_fingerprint |
| 为过测试改引擎 = workaround | 生产路径禁测试专用开关；发现即拒收，要求修根因 |

**最低证据三件**（可机械核对，VibeGame 直移）：① 角色响应输入（前后位置 diff + 前后截图）；② 主行为触发（快照状态变化：HP 降/弹道实例化/状态翻转，任一）；③ 无输入时 AI 仍活动（t=0 vs t≈2s 位置必变，全冻结 = AI 没启动）。

### 3.7 验证器自校准（每个探针套件上线前必须过）

```
starter（故意带 bug 的工程）→ 探针必须 FAIL
oracle（参考解）            → 探针必须 PASS
NOP（什么都不做）           → 必须 0 分
```

三者缺一，分数无意义（GamePhanes 最小充分校准对直移）。这是防"永远绿的验证器"的 CI 级检查——**我们自己的探针套件也过这道门**，否则 agent 的"自验证通过"不可信。

### 3.8 四层证据词汇

`Artifact（文件/schema 存在）→ Engine（解析/启动）→ Behavior（有序事件/状态转移/边界/生命周期）→ Diagnostics（不变量解释）`。
**行为分只归 Behavior 层**——场景文件解析成功永远换不来通过。

### 3.9 体验裁决面：策略 → 轨迹 → 度量 → 版本裁决（v1.4 实施）

主分（§3.5）回答"**这个游戏对不对**"（binary、零 LLM）。它不回答"**这个游戏好不好玩**"。
RGC 与 RSIGame 把后半个问题交给一个递归闭环：Designer → Builder → Player → Reviewer
→ 接受更好的版本 → 下一轮。引擎不做闭环里属于 LLM 的部分（Designer/Builder 是 agent 的活），
只把闭环需要、且**必须可校准**的四块能力做成原语——否则每一环都要 agent 自己发明，
而且发明出来的东西无法自证不是永远绿。

| 环节 | 引擎原语 | 为什么必须在引擎里 |
|---|---|---|
| **Player**：可复用策略 / 多样轨迹 | `kernel.Policy`（`script` / `explore(seed,frames)`）+ `run_policy` / `run_policy_grid` → `Trace` | RGC 指出的最大偏差来源是"GUI 慢采集 + 一条手写路径"。策略必须是**确定性数据**（同 seed 必同轨迹、同世界必同度量），校准才有对象 |
| **轨迹事实** | 逐帧 `Sample`（整型化，跨架构确定）+ 派生量（cells / revisits / stall / path_len / jumps） | 度量若有第二个事实源（截图 / VLM / 墙钟）就不可复现——不再满足 §3.1 |
| **Reviewer**：轨迹度量 | `metrics_of` → `Metrics`（progress / coverage / directness / stall / idle / diversity / revisit）+ 策略集聚合 `Experience` | 度量只从轨迹来；零 LLM |
| **game-specific criteria + 显式偏好** | `criteria.json`（标准集 + `prefer` 偏好序）→ `eval_criteria` | RGC 的 "explicit textual preferences" 落成**文本而非代码**：改质量门不用改引擎 |
| **接受更好的版本** | `adjudicate` → `accept_b` / `keep_a` / `inconclusive` | RSIGame 递归自改进的最小可核对形态 |

**聚合语义（上下限分离）**：能力类（进展 / 覆盖 / 直达 / 多样性）取**最好那条**策略；
风险类（停滞 / 闲置）取**最差那条**；覆盖度用所有策略的**并集**重算；
另报 `stuck_ratio`（一个目标都没完成且未通关的策略占比）。
两类都取单边会说谎：只看最好，"有一条路径会卡死"被吞掉；只看最差，一条笨策略就把可玩上限抹平。

**裁决次序（先硬门后偏好）**：标准通过数 → 终局序（won > playing > dead）→ 偏好序逐项
→ 全同即 `inconclusive`。终局序是第二道硬门，专门拦住"覆盖度涨了但游戏打不通了"被接受。
**"改动即进步"不是结论**：同版比较必须返回 inconclusive。

**判据取自基线（v1.5 修正）**：v1.4 曾让 `compare` 优先取**候选**声明的标准（"候选要达到的质量门才是门"）。
这在单轮里就已经是真实漏洞——候选自带一份宽松 `criteria.json`，就能把打不通的关卡判成 `accept_b`。
判据是**尺子**，尺子不能由被量的那一方提供。现在 `compare` 与 `rsi`（§3.10）共用 `kernel.judge_versions`：
判据与偏好序取自**基线**，探针集取基线声明的，候选自己的声明只作对照并如实标记
（`criteria_drift` / `gate_shopping` / `policy_drift` / `mode_drift`）；`compare` 新增退出码 4 = 检测到操弄判据。

**与主分的关系**：体验度量**不进** verify 的 binary 主分。两套分数各有职责——
混在一起，两个都不可信（同 §3.5 诊断分纪律）。诊断归属也照 §9.1：度量只描述
"发生了什么"，不宣称"这更好"——更好由**声明的标准与偏好序**裁决。

**自校准**（§3.7 的门同样适用于新一层）：`calibration/experience/` 的 v1/v2 只差一个
参数（走道上加满尖刺，关卡数据看起来没变、玩起来全变了），断言
`trace v1 → 0`、`trace v2 → 2`、`compare v1 v2 → keep_a`、`compare v2 v1 → accept_b`、
`compare v1 v1 → inconclusive`。裁决器若"永远接受改进"，这条立刻红。

**四面同源**：编排只有一份（`scene/experience.mbt` 的 `run_experience`）——
native CLI `trace`/`compare` 与 wasm `web_trace` 只是调用方；
`tests/faces_parity.sh` 机械断言两面的体验度量**逐字段相同**（篡改任一字段即红）。

**已写明的边界**：`explore` 是**分束采样**策略（不是逐帧噪声，噪声轨迹读不出可解释行为）；
策略帧数上限 `MAX_POLICY_FRAMES=3600`，截断会如实报告（`truncated`）；
覆盖度分母是"画布 64px 分块数 / 自由格数"，**不是可达格数**（可达性由 progress + 多条策略间接体现）；
视觉证据仍走 `verify --shot` / `shot` 通道，本层不做像素判断（VLM 判官按 §3.5 属诊断分）。

---

### 3.10 递归自改进面：冻结门 → 多轮 → 台账 → 复算（v1.5 实施）

§3.9 把"接受更好的版本"做成**一次性**裁决（`compare`）。递归自改进要跑**多轮**，
而多轮会立刻暴露两个 v1.4 没有防的面——它们的共同特征是**看起来像进步**：

| 作弊面 | 形态 | 为什么单轮无妨、多轮致命 |
|---|---|---|
| **判据漂移（gate shopping）** | 候选自带一份更松的 `criteria.json`（`progress >= 100` → `>= 0`） | 单轮只是"换个标准看一次"；多轮等于候选**改写评判自己的尺子**，下一轮必然"进步"——自改进闭环最经典的 reward hacking |
| **探针集膨胀** | 候选自带更多探索策略（覆盖率 = 策略并集，多几条就涨） | 关卡**一个像素都没改**，覆盖率自己就上去了；外观还是"测得更严谨"——比改判据更隐蔽 |

**冻结门**：run 开始时把判据 + 偏好序定成 `Gate`（取自**基线**，候选无法影响），此后每轮都用它判；
候选自己声明的门只作对照，并如实标记 `criteria_drift`（判据文本与冻结门不同）、
`gate_shopping`（按它自己的门**更好看**）、`self_passed` vs `frozen_passed`（两把尺子的通过数并排给人看）。

**冻结策略集**：判定时一律用**基线声明的**策略集测所有版本（同一套探针测两版）；
候选自己声明的策略集只用于标记 `policy_drift`——它意味着"这版独立跑 `trace` 的数字会和台账不一致"，
不报就是引擎在骗人。

**原型族可比性**：度量**同名不同义**（grid 的 `progress` 是"箱子归位"，physics 是"金币/终点"），
所以候选与基线的 `mode` 不同时**不予裁决**（`inconclusive` + `deciding=mode` + `mode_drift=true`），
而不是硬比出一句 `keep_a`——那是可比性谎言。

**预算与停滞**（§5.3 的 T=5 落成机械规则）：轮预算 `--budget`（默认 5）+ 连续被拒 `--stall`（默认 2）即停，
`stop_reason` ∈ `exhausted` / `budget` / `stalled`。没有它，闭环会把"反复小改"累积成"进步"。

**血统与台账**：每轮记 base/cand 的**体验指纹**（`experience_digest`，只由可复现的聚合事实算出），
形成 `base → 每轮 → incumbent` 的可核对血统；`rsi_problems` 机械自检血统连通性
（接受/拒绝必须与裁决一致，序号与 base 链必须接得上）。台账自带**冻结门本体**与**停止参数**，
`rsi check <ledger.json>` 按台账**复算**：逐轮候选指纹、裁决、冻结门通过数、接受计数、停止原因、
末端指纹全部重算比对——改台账、改候选内容、改基线配置都会红。
**不可复算的台账 = 审计链断了**（§9.2 run 不可变）。停止参数也必须进台账，否则复算无法重现同一次停止
（会给出别的轮数），"可复算"就成了一句空话。
`rejection_memory` 把被拒轮次按**决定项**归类（如 `criteria × 2`），是 §5.2 errors.md 的机械形态：
agent 读它就知道这一路已被试过并否决，不必重复同一种无效改动。

| 命令 | 退出码 |
|---|---|
| `rsi run <base.guide.md> <cand...> [--budget N] [--stall N]` | 0 = 至少接受一次改进；2 = 一轮都没接受；3 = 检测到操弄判据（优先报）；1 = 装配/参数错 |
| `rsi check <ledger.json>` | 0 = 逐轮复算一致；2 = 有不一致（逐条列出）；1 = 读不了/不是合法台账 |

**自校准**（`calibration/rsi/`，与 §3.7 同一道门；四个候选共用基线的门与探针集）：

| 候选 | 与基线的差异 | 期望 |
|---|---|---|
| `c1_better` | 加两块悬浮平台（覆盖 25→31；标准通过数与终局都不变，由偏好序的 `coverage` 裁定） | **接受**（exit 0） |
| `c2_worse` | 走道上加尖刺（数据看着只多一个字段，可达性被破坏） | **拒绝**（keep_a，exit 2） |
| `c3_selfserving` | 与 c2 **同关卡**，自带一把"只有它自己过"的门（`progress <= 50` + `stall_max <= 40`：基线 0/2、它 2/2） | 仍按冻结门**拒绝**（0/3），并标 `gate_shopping`（exit 3） |
| `c4_morepolicies` | 与基线 **同关卡**，多带 4 条探索策略（独立跑 9 条时覆盖率 26 > 基线 25） | 冻结探针下两者度量逐字段相等 → `inconclusive`，**不接受**（exit 2） |

外加台账复算用例与**篡改台账必红**用例，以及**跨族不可比**用例（physics 基线 vs grid 候选 → `inconclusive`）。裁决器若"每轮都接受改进"，或候选能靠换尺子/带探针过关，这几条立刻红。
本轮还做了四条**证伪**（每条机制都必须能被推翻）：把判定换成候选自己的门 → `c3`（打不通的关卡）被判 `accept_b`
并接管 incumbent；把 `gate_shopping` 恒置 false → 报警消失（exit 3 → 2）；把评测换成候选自带的策略集 →
`c4`（世界未改）被接受且理由写着"coverage: 25 → 26"；删掉血统自检里的 incumbent 校验 →
"逐轮相连但末端不对"的单测立刻变红。

**已写明的边界**：候选的产生（Designer/Builder）不是引擎的活——本层只做**选择 + 记账 + 可核验**，
绝不自己改关卡去"提升"度量（§11）；"接受"只意味着**按冻结门与偏好序**更优，不意味着绝对质量更高；
度量只覆盖声明的策略集，未被任何策略走到的玩法路径不在证据内（台账自带 `unsupported_claims`）；
被拒候选的**内容**不归档（只记指纹与决定项）——需要留档时由 agent 自己保留文件；
`rsi` 只在 CLI 面（多文件 + 多轮驱动 + 台账落盘是 shell/CI 的活），wasm 面不导出。

---

## 4. 谓词门禁与质量体系

继承 moonviz 的 P0–P4 分级，并入两项调研升级：

| 级别 | 语义 | 例 |
|---|---|---|
| P0 | 硬错误，拒绝 | 颜色非法、引用不存在的资产 key、四点一线断裂 |
| P1 | 结构冲突 | 分镜越界、场景引用的节点模板不存在 |
| P2 | 语义可疑 | 字号低于可读阈值、`frame_events` 外读帧索引、运行时改碰撞体（静态可查的） |
| P3 | 风格建议 | 命名不一致、层级过深 |
| P4 | 提示 | 可优化项 |

两项升级：

1. **三值裁决**（CCGS 直移）：门禁结论为 `PASS / CONCERNS / FAIL`——CONCERNS = 带已知风险放行，比二值诚实。裁决记录进 run。
2. **静态检查分工原则**（VibeGame 直移）：结构规则（字段/类型/枚举/必需）住在 **schema**（声明式定义，MoonBit 生成校验器）；只有 schema 表达不了的（跨文件引用、key 四点一线、模板可见性）才写成代码规则。分级 `ERROR/WARN/PREVIEW/PASS`；**PREVIEW 输出可视化**（场景渲染 + 碰撞盒 + pivot 点 + 帧带叠加图）而非文字描述。

> 单语言栈的结构性优势：VibeGame 的预览工具是引擎的平行重实现，已发生 docstring 与实现漂移。我们运行时与检查器同用 MoonBit 内核 + raylib 渲染，**结构性消除双实现漂移**。

---

## 5. 骨架库与失败记忆（投资优先级最高——有消融背书）

OpenGame 消融：骨架库 +6、活协议 +5、合计 +12 BH，是全部机制里最大单项收益。**我们的差异化：把这两样做成引擎原语，不是提示词资产。**

### 5.1 物理优先原型族（5 族）

分类学原则：**按物理/运动规则分类，不按题材**（OpenGame `classify-game-type` 直移）：

| 原型族 | 物理形状 | 例 |
|---|---|---|
| `gravity_side` | 重力 + 刚体 + 碰撞 | 平台跳跃、横版动作 |
| `top_down` | 无重力 + 8 向移动 + 碰撞 | 俯视射击、RPG 走位 |
| `grid_logic` | 离散网格 + 回合/下落 | 消除、推箱子、俄罗斯方块 |
| `path_wave` | 路径跟随 + 波次生成 | 塔防 |
| `ui_driven` | 无物理循环 | 视觉小说、卡牌、解谜菜单 |

每族一个**可运行骨架**：`骨架 = 共享内核配置 + modules/<族> + 该族 API 约束文档 + errors.md + 静态检查规则集`。agent 从骨架出发，**只覆写声明钩子**而非从零写（OpenGame hook-driven 消融：去掉它 BH −10.1、IA −11.6，全部工作流消融里最狠的一条）。

引擎内置 `classify` 工具：需求 → 物理形状 → 族推荐。

### 5.2 errors.md 失败记忆（双形态）

**格式**（VibeGame 直移，含闭环行）：

```markdown
## N. 动画冻在第 0 帧
### Symptom  — 角色移动但动画不播
### Cause     — 每帧无条件 setAnim("run")，默认 restart 每帧重置索引
### Fix       — 幂等状态设置器：if (self.state == s) { return }
**Spec update**: 已加入 kernel 检查规则 `no_per_frame_anim_set`（P2）
```

**双形态**（OpenGame 调研结论直移）：

- **叙事档案**（errors.md）——利于沉淀，条目可追溯回案例；
- **执行协议**（checklist + grep 式检查命令）——利于执行，长在静态检查器里。

**闭环是关键**：每条教训的 `Spec update` 必须指向一个未来会被读到/执行的地方（检查规则、schema、骨架文档）。理想态是**互转**：检查规则注释回指 errors.md 条目，errors.md 条目可编译成规则。

**反伪造纪律**（VibeGame 明确警告）：errors.md 的价值来自真实项目跑通后的沉淀。**凭空编写会产生假先验**。初期骨架的 errors.md 从零开始，只提升真实承重过的教训（"Ship only what was load-bearing in a real task"）。

### 5.3 修复循环预算

迭代修复收益集中在 T=0→3，**T=5 后平台化**（OpenGame 消融）。内核验证循环设预算上限 5 轮，超限即 FAIL 并产出诊断报告——不无限自旋。

---

## 6. 资产管线：程序化优先，"AI 只产源，引擎确定性派生"

### 6.0 三级资产层：程序化是默认，不是兜底（Minecraft 思想继承）

**初期不设真实素材。一切可观察物由参数程序化生成：视觉 = 计算像素，音频 = 合成器电子音。**

| 层 | 形态 | 启用时机 | 依赖 |
|---|---|---|---|
| **Tier 0 程序化** | 参数 → 引擎内置生成器 → 像素/波形 | **P0–P4 的唯一资产层** | 零外部依赖，零成本，零许可负担 |
| Tier 1 AI 源图 | AI 生成源画（§6.1 三道锁全程管着） | P5 之后按需 | 付费 API 纪律（§9.3） |
| Tier 2 真实素材 | 手工/外包素材 | 引擎语义稳定后 | 内容寻址 + 帧名契约 |

**为什么程序化优先不只是省钱——它是架构决定：**

1. **资产即参数，参数即文本**。`shape/color/seed/pattern` 写在 manifest.mbg.md 里，整个游戏（含全部资产定义）保持 **100% 文本可 diff**——agent 的每一次修改都是可见的文本变更，review、回滚、回归全部沿用既有机制；
2. **确定性免费获得**。生成器是纯函数（同 seed 同输出），像素级回归测试不需要任何素材管理；
3. **零身份漂移**。Sprite Studio 三道锁对抗的"AI 跨帧身份漂移"在 Tier 0 **结构性不存在**——没有 AI 画的帧；
4. **零素材即零管线债**。初期没有二进制资产 = 没有素材库、没有许可证审查、没有付费 API 流程（§9.3 整章暂缓生效）、没有"美术后到"的协调成本；
5. **Minecraft 已验证这条路的审美合法性**——计算像素 + 电子音不仅是可行，本身可以成为风格。

**迁移通道免费获得**：§6.2 的 placeholder 枢纽机制在 Tier 0 就是运行时本体（语义帧名 → 程序化生成帧），将来升 Tier 1 时**沿用同一替换协议**（只换 manifest 条目、场景与代码零改动）。程序化层不是"以后扔掉的脚手架"，是第一版正式资产层。

### 6.1 三道锁（Tier 1 起生效；Sprite Studio 直移）

1. **权限声明**：AI 生成**源资产**（源画/帧名/参数），**永不发明动画时序、姿态帧或派生物**；
2. **内容寻址锁定**：manifest 每条目记源文件 SHA-256；源变则派生缓存失效拒用；
3. **确定性派生**：图集拼装、动画帧序、rig 变换全部由引擎确定性计算（软件光栅，最近邻采样）——同源必出同帧，字节级可重现。

> Tier 0 下这三道锁的对应物：AI 只写**生成参数**（同样不许发明帧时序——帧序是状态机与动画表的职责）；内容寻址锁定改为**参数指纹**（同参数 → 同帧，CI 断言）；确定性派生则是生成器本身的纯函数契约。

### 6.2 程序化条目与替换枢纽（VibeGame placeholder 机制直移 + 扩展）

```mbg
# manifest.mbg.md —— 无 path 即程序化条目（Tier 0 唯一形态）
player_idle  procedural_atlas frames:[idle_0..3] pivot:(0.5,1) \
             body:{shape:block, color:#4a9eff, size:16} \
             anim:{kind:bob, amp:2, hz:2, phase:0}
sword_icon   procedural_image shape:diamond color:#ff3366 size:12
hit_fx       procedural_atlas frames:[spark_0..5] \
             gen:{kind:radial_burst, colors:[#fff,#ff3366], seed:7}

# 音频同样是程序化参数（§6.4）
jump_sfx     synth:{wave:square, freq_slide:[220,440], dur:0.12, decay:fast}
bgm_grass    tune:{notation:abc, tempo:132, voices:[square,triangle]}
```

- 条目用**真实语义帧名**（`idle_0..3`）——场景与代码**从第一天就是最终形态**；
- `shape`/`color`/`seed`/`pattern`/`anim` 是**生成参数**（文本，可 diff），不是运行时二进制；
- 升级 Tier 1/2 时**只换 manifest 条目**（同 key 同帧名），场景/代码零改动；
- 配套 §2.2 帧耦合事件声明——玩法读帧索引的唯一合法入口，资产升级不破坏耦合。

这使"代码先行、美术后到"从流程口号变成**机制**；而在程序化优先阶段，它进一步意味着"美术"本身就是声明式文本。

### 6.3 生成规则库（资产协议要点）

- **视图纪律**：side view 一律朝右（朝左用确定性 hflip，**永不因朝向重新生成**）；top-down **三方向各 1 帧 > 单方向多帧**（方向覆盖优先于帧数）——程序化生成器直接内置此纪律（top_down 族的生成器默认产出三方向帧组）；
- **帧数判据**：由状态内在身体运动决定——循环运动（idle/walk）多帧；保持姿态（jump/fall/dash）**单帧即可**，引擎平移；
- **可切片规则**：程序化生成按格生成，天然不跨格；Tier 1 起对源图执行同规则检查；
- **数值可感知阈值**（Sprite Studio 直移，用于自动验收"动起来了"）：跨周期 ≥8° 旋转 / ≥1.5 逻辑像素平移 / ≥5% 缩放才算可感知运动；±2° 或 0.999–1.001 缩放 = "数值在动但像素静止"，**自动拒绝**——对程序化动画参数同样生效（`amp` 太小的 bob 会被验收打回）；
- **具名 IP**："name it, do not hand-describe it"——知名角色点名，手工描述只留给原创角色（Tier 1 起生效）。

### 6.4 音频：合成器电子音是一等公民（不是兜底）

**Tier 0 全部音频由引擎内置合成器生成**（OpenGame 零外部模型路线直移并升级为一等能力）：

- **波形层**：square / triangle / saw / noise 四通道 + 包络（attack/decay/sustain/release）+ 频率滑奏——参数全部声明在 manifest（见 §6.2 示例）；
- **记谱层**：ABC 记谱法文本 → 本地合成（OpenGame 验证过的 8-bit chiptune 路线）——旋律是文本，可 diff、可回归；
- **确定性**：同参数 → 同波形（字节级）——音频回归与像素回归同一套机制；
- 外部音频生成（Tier 1）才走付费 API 纪律（§9.3），初期整章不生效。

---

## 6.5 FC/SFC 资源制作与识别（v1.3 实施）

> §6.0 说「程序化优先」，但没说**按什么约束程序化**。不锚定约束，
> 生成出来的只是普通彩色方块图，不是 FC/SFC 时代的东西。
> 本节把约束写成可执行数据，让生成器**必须遵守**。

### 6.5.1 硬件约束 = 可执行数据（`engine/retro/retro.mbt`）

全部数字经 nesdev / famicom.party / wiki.superfamicom.org / SnesLab 核实：

| 约束 | FC | SFC | 出处 |
|---|---|---|---|
| 精灵有效色（**不含恒透明的 index 0**） | **3** | 15（精灵恒 4bpp = 16 减透明） | PPU OAM / CGRAM |
| 背景 metatile 色 | 4 | 2/4/8 bpp 按 BG 模式 | attribute table |
| 每扫描线精灵 | 8 | 32 | OAM / $213E |
| 精灵尺寸 | 8×8 / 8×16 | 8/16/32/64 方形（同时仅两种尺寸） | PPUCTRL / OBSEL |
| 图块（8×8）占用 | 2 /帧（8×16） | 4 /帧（16×16） | CHR / VRAM |
| 色强调 | 3 位（PPUMASK bit5/6/7）+ 灰度 | — | colour emphasis |
| 调色板 | 8 组 × 4 色 = 32 项 | CGRAM 256 色 BGR555 | palette RAM |

**没有权威的 FC hex 调色板**——PPU 输出 64 个模拟电压，任何 hex 表都是显示器侧近似。
本项目用社区流通的 2C02 NTSC 表作为**风格锚点**（非真值），并在源码里注明性质。

### 6.5.2 生成策略：在约束内生成，不是生成后量化

**「先生成彩色图再量化到 4 色」是错的**——FC 精灵只有 3 色 + 透明，
量化只会得到抖动色斑（dithering artifacts）。那是"把彩色图塞进 4 格"，
不是"用 4 格画画"。真实 FC 美术是**一开始就知道只有 3 笔**。

因此生成器：
- 调色板**固定 4 槽**（index0 透明 + 3 实体色），取自 FC 调色板；
- 造型靠**色阶分配**（哪块用帽色/皮肤色/衣色），不靠颜色渐变；
- **轮廓靠透明像素**，不靠黑色描边——黑色也是 1 个色位；
- 姿态差异只动**下半身与手臂**，上半身逐帧稳定（FC 动画通用手法）。

### 6.5.3 制作 → 识别的闭环

`retro identify` 走完整链路，每一步都可核对：

```
生成帧 → to_chr（2bpp planar，按图块序列）→ from_chr 读回 → 逐像素比对
       → 剔除透明标记 → 颜色普查 → 量化到 FC 调色板 → 预算裁决 → JSON 报告
```

两条纪律：

1. **CHR 编解码严格互逆**（往返逐像素一致，有测试）。按**图块序列**组织
   （8×16 = 2 个 8×8 图块，行优先）——这是真实 CHR 的布局，产出字节可直接喂 ROM 流程。
2. **透明标记必须在普查前剔除**：洋红不是"第 4 色"而是"没有颜色"。
   算进去会让 FC 精灵误报成 4 色超预算——这是识别能力最容易犯的错，
   故有专门测试（`distinct_with_alpha - 1 == distinct_opaque`）。

### 6.5.3.1 同一套造型逻辑跨平台（BodyBox）

人物造型是**宽度参数化**的：身体框 `body_box(fw) = {x: 1, w: fw - 2}`
由帧宽推导，所有下半身坐标按框计算。FC 8×16 → 6px 身体，SFC 16×16 → 14px 身体。

**为什么这条值得单列**：早先把下半身坐标写成绝对值（`fill_rect(f, 3, 12, ...)`），
于是 SFC 的 16 宽帧里人物只占左侧 8px、右半全空——**SFC 支持名义上存在，
实际上走了退化分支**。一个走退化分支的"SFC 支持"比没有更危险：它看起来能用，
但产出的是残缺资源，而残缺资源在真机上表现为"人物只剩半边"，极难归因。

教训落到纪律上：**平台差异必须体现在数据抽象里，不能靠分支掩盖**。
若当初就有 `BodyBox`，这个缺陷在写测试时就会暴露（包围盒宽度不足）。

回归防护：SFC 帧横向包围盒 ≥ 帧宽 3/4、必须触达右半区、
躯干行宽度 == `body_box(16).w`、`walk2` 镜像不变量在两个平台都成立。

### 6.5.4 产出物形态（blueprint §6.0「资产即参数」）

| 工件 | 用途 | 为什么是这个形态 |
|---|---|---|
| CHR hexdump | 喂 ROM 制作流程 / 人工核对 | 真实硬件的数据布局 |
| ASCII 预览 | 终端里最快自检 | 不需要任何工具 |
| SVG（放大 + 棋盘透明底） | 人眼视觉审查 / 贴文档 | nearest-neighbor，像素不模糊 |
| JSON 识别报告 | agent 直接消费 | binary 主分 + 自审计字段 |
| 调色板文本 | diff / 喂外部工具 | 纯文本可版本化 |

**外部核对器**（`shots/retro/svg_check.py`）：用完全独立的 Python 解析器读回引擎
产出的 SVG 重建像素图——这不是单元测试的重复，而是**跨语言实现的交叉验证**。
它已经抓到一个真 bug（`hexc` 让每个通道各自加 `#`，拼出 `#A6#27#21` 非法颜色，
SVG 在浏览器里**静默渲染失败**）。

---

## 7. 玩法内核契约（Mechanic 等价物）

每个游戏模块对外只暴露三件套（GameFactory Mechanic 契约直移，schema 化）：

```
state    —— 暴露给 UI/探针的可观测值（非空，"real behavior, not placeholders"）
events   —— 玩法转换/通知（探针订阅的就是它）
commands —— UI/宿主可调用的动作（语义输入注入打在这里）
```

- **依赖方向唯一**：`UI/渲染 → 内核`。内核在无 UI、无渲染器、无截图环境下编译、测试、评估（headless 探针直接驱动 commands、断言 state、监听 events）；
- 探针轨迹与 agent 轨迹在数据上**硬隔离**（evaluator_probe 单独标记，不计入 agent 决策记录——防自验证数据污染）。

---

## 8. 消费面（四面同源）

moonviz 已验证的模式（CLI/MCP/WASM/SDK 四面同一内核），deepEngine 对应：

| 面 | 形态 | 用途 |
|---|---|---|
| **native** | 可执行（raylib 后端） | 交互游玩、给人看 |
| **CLI** | stdin ops / 探针与裁决命令 | shell 组合、CI（`run` / `verify` / `trace` / `compare` / `rsi run` / `rsi check` / `shot` / `inspect`） |
| **MCP** | 工具面（JSON in/out） | Agent 直驱（对标 moonviz 52 tools） |
| **内核 wasm** | 仅 L2（纯 MoonBit，无 raylib） | 嵌入宿主（如 deepOrca）做纯逻辑验证与体验度量（`web_trace`） |

**同源不是口号，是可判据**：探针面由 `tests/regression.sh` 断言双入口逐探针一致；
体验面（§3.9）由 `tests/faces_parity.sh` 断言 CLI 与 wasm 的度量**逐字段相同**。

**deepOrca 接缝预案**（从其 engine-integration-plan 学到的消费方视角，将来若被消费）：

- 消费方会要：版本握手（`version_info()`）、sha512 产物锚点、实例化契约探针、canonical 键控会话缓存、超时隔离、内存棘轮；
- 内核 wasm 面从第一天就带 `version_info()` + 导出面契约测试，**避免将来为嵌入补协议**；
- worker 隔离/棘轮属宿主职责，不进内核。

---

## 9. 治理（流程纪律）

### 9.1 归属层修复

验证失败的诊断输出**直接标注归属层**（资产/导入/玩法/UI/场景/渲染），修复必须修在归属层——**"never patch an asset problem inside gameplay code"**（GameFactory 修复纪律直移）。诊断 → 自动修复尝试（收紧参数/改变换/重验）→ 仍败才升级，**不把验证失败当半成品甩回用户**（Sprite Studio 纪律直移）。

### 9.2 run 不可变 + 引用不引文

- 修复创建新 run，记 `parent_run_id`/`repair_of`/失败摘要（审计链）；
- 任务/故事引用契约的 **TR-ID 而非正文**（"stays fresh"——契约改了引用不携带陈旧文本），内嵌契约版本指纹检测过期（CCGS 直移）。

### 9.3 付费 API 纪律（Tier 1 起 / P5 后生效）

> **程序化优先使其在 P0–P4 整体不触发**：初期没有任何外部生成调用——这正是 §6.0 的直接收益之一。

外部生成（图像/音频/3D）走六步硬流程：**暂停 → 完整成本估算（含单价页与本次批量估算）→ 等明确答复 → 用户自己导 key（只设会话环境）→ 拒绝则本地/open 兜底 → 无路线能产出可交付资产时报告缺口而非静默降级**（GameFactory 直移）。凭证探测**字面输出**（`KEY=SET|MISSING`），"key unavailable" 不是合法跳过理由除非贴出探测输出；跳过理由闭集 5 条（threejs-skills 直移）。

### 9.4 措辞纪律

报告区分 **invoked ≠ loaded**（技能被调用 ≠ 文档被读入上下文）——反"声称读过"幻觉的直白防御（threejs-skills 直移）。

### 9.5 引擎版本知识缺口

raylib 6.1 / MoonBit 0.1.x 均可能比 agent 训练数据新。引擎文档**版本钉住**（绑定锚点 commit 生成 API 参照），SKILL 文档标注"训练截止后风险"（CCGS `/setup-engine` 直移）。

---

## 10. 里程碑（每阶段有可判 exit）

> 原则：**先内核后画面、先验证后生成、先 2D 后 3D、先程序化后素材**（P0–P4 全程零素材：计算像素 + 合成电子音，见 §6.0）。每个 P 的 exit 是可运行判据，不是"完成度百分比"。

### P0 — 内核地基（最高优先）

内核帧步进 + 语义输入 + runtimeState + 探针协议 + **验证器自校准**。

**Exit 判据**：
- `kernel.step/run/press/snapshot` 纯函数语义成立（同输入同输出，CI 双跑断言）；
- 探针套件过三件套校准：带 bug 的 starter 工程 → FAIL；参考解 → PASS；NOP → 0 分；
- 一条 DE_EVENT 行协议端到端跑通（headless）。

### P1 — 指引与内容源

**指引文件**（`game.guide.md`：有哪些东西 / 怎么解析 / 怎么渲染组装）+ **内容源**（§2.4）
+ 四条 AI-native 语义 + schema 静态检查 + 谓词门禁 P0–P4 + 三值裁决 + PREVIEW 可视化。

**Exit 判据**：
- ~~往返无损（parse → canonical → parse' 字节一致）~~ —— **v1.2 起取消**：
  引擎的原生路径是衍生不是往返，强制往返无损会把架构锁死在文档域的纪律上；
- 四点一线 key 检查、模板可见性检查、pivot 级联、省略即继承全部有测试；
- PREVIEW 输出叠加图（场景+碰撞盒+pivot）；
- 已有 demo 场景迁移到新结构无信息丢失。

**已达成（v1.3）**：指引解析 + JSON 内容源 + 装配层落地；「省略即继承」有测试
（`assemble_wbtest.mbt`）；双入口等价由 `engine/tests/regression.sh` 机械断言。
**未达成**：四点一线 key 检查、pivot 级联、模板可见性、PREVIEW 叠加图
（这些属于资产/节点体系，随骨架库 P2/P3 落地）。

### P2 — 渲染接入 + 骨架库 v1

L1 场景图 → bridge → raylib 渲染打通（GPU 交互 + SW 验证双路）；**`gravity_side` 与 `grid_logic` 两族骨架**（已定：一个验物理循环、一个验离散逻辑，覆盖面最互补）+ 每骨架 errors.md（从零开始，只沉淀真实教训）。

**Exit 判据**：
- 骨架开箱可玩（**纯程序化资产**，零二进制素材），人玩 3 局（vertical slice 硬门——"人未玩即 FAIL"，CCGS 直移）；
- headless 探针在骨架上跑通最低证据三件；
- 骨架带 API 约束文档 + 静态规则集，agent 从骨架出发改钩子产出一个可玩变体（验收走 binary 主分）。

### P3 — 程序化资产层

**视觉生成器**（shape/pattern/seed 参数 → 像素帧组）+ **合成器音频**（波形/包络/ABC 记谱 → 波形）+ manifest 程序化条目 + 参数指纹确定性 + 可感知阈值验收 + 升级替换通道（预留 Tier 1）。

**Exit 判据**：
- 同参数双跑，视觉帧与音频波形均逐字节一致（参数指纹 CI 断言）；
- 替换演示：只换 manifest 条目（程序化 → 另一组程序化参数），场景/代码零改动，游戏行为不变（帧耦合事件保持）——即 Tier 1 的迁移通道已被验证；
- 方向/帧数规则进生成器默认值；可感知阈值进验收；
- 骨架全部音画来自程序化层，项目目录**除文本外零二进制**。

### P4 — 消费面

CLI + MCP 工具面 + 内核 wasm 面（带 version_info 与导出契约测试）。

**Exit 判据**：
- MCP 面驱动完整"分类 → 骨架 → 修改 → 验证"闭环（一次真实 agent 会话）；
- wasm 面过导出契约探针（消费方视角，参照 deepOrca vendor 纪律）。

**已达成（v1.4–v1.5）**：CLI 面（`run` / `verify` / `trace` / `compare` / `rsi run` / `rsi check` / `shot` / `inspect`）+
内核 wasm 面（`version_info()` + 导出面契约烟测 `web/smoke_web.mjs`，含体验度量）；
体验裁决面（§3.9）在 CLI 与 wasm 两面同源，由 `tests/faces_parity.sh` 机械断言；
递归自改进面（§3.10）只在 CLI 面（多文件 + 多轮 + 台账落盘），带自校准与台账复算。
**未达成**：MCP 工具面——"分类 → 骨架 → 修改 → 验证"闭环仍需 MCP 工具封装。

### P5 — 扩展（按需排期）

- 其余三族骨架（top_down / path_wave / ui_driven）；
- 物理（简单刚体 + 射线，不自研引擎级物理）；
- **Tier 1 资产接入**（AI 源图/外部音频，三道锁 + 付费 API 纪律此时才生效）；
- 3D 声明式场景（引用 3D 域报告六段：几何生成/确定性校验/资产工程化/场景编排/运动生成/镜头语言——④⑤⑥ 三段在开源界也是空白，是机会也是风险，**必须在 2D 验证闭环成熟后启动**）；
- 音频调度（事件驱动）。

---

## 11. 明确不做（负面清单补充）

| 不做 | 理由 |
|---|---|
| **初期真实素材 / 外部生图 / 外部生音频（P0–P4）** | 程序化优先（§6.0）：计算像素 + 合成电子音覆盖全部初期需求；零成本、零许可负担、零身份漂移、100% 文本可 diff |
| 自研引擎级物理 | 简单刚体/射线够用；Box2D 级需求出现时再评估接入 |
| 3D 先行 | 2D 验证闭环（探针/骨架/资产）未成熟前不碰 3D 声明式 |
| 编辑器先行 | 消费面（MCP/CLI）先行；GUI 编辑器等引擎语义稳定 |
| 专用模型训练 | OpenGame 消融已证框架增益（+9.6）>> 模型增益（+1.1） |
| vendor 任何调研对象代码 | AGPL 红线（CozyClay）+ 全部价值在机制层不在代码层（两轮调研一致结论） |
| 向 raylib 上游回馈 issue/PR | 已定政策：AI 驱动开发、未通读上游源码，缺陷内部解决（见 FORK.md） |
| **用 LLM/VLM 给体验打分（进主分或进裁决）** | 体验裁决面（§3.9）只从**轨迹**出度量，零 LLM：一旦引入主观判官，"这版更好"就无法复现；VLM 若要用于视觉主观项，只能按 §3.5 走**诊断分**，且不进 `reward`、不参与 `adjudicate` |
| **从截图/像素算体验度量** | 与上同源：像素是渲染层产物（§1 依赖方向），体验是玩法层事实；两者混用会让"内核不碰渲染"的契约失效 |
| **自动改关卡以"提升"体验度量** | 引擎只出证据与裁决，不自己优化——Designer/Builder 是 agent 的职责；引擎自动调参会让"是谁改的"与"为什么更好"都不可审计（§9.1 归属层纪律） |
| **把候选自己声明的判据当作判定依据（多轮尤其）** | 与上一条同源：等于让候选**改写评判自己的尺子**（gate shopping），"每轮都进步"必然是幻觉；判定只认 run 开始时冻结的基线之门（§3.10） |
| **把候选自带的策略集当作比较基准** | 覆盖率是策略并集，多带几条策略就能机械上涨而关卡未改；比较必须用冻结探针集，候选自带的策略集只用来标记 `policy_drift`（§3.10） |
| **把被拒候选的度量当成"没发生"** | 拒绝必须留下决定项（`rejection_memory`）与指纹；否则下一轮 agent 会重新试同一种无效改动，闭环退化成随机游走（§3.10/§5.2） |

---

## 12. 风险表（含新增）

| 风险 | 严重度 | 对策 |
|---|---|---|
| 浮点跨架构不确定 | 高 | 关键路径定点数/整数化（网格坐标用整数像素——GamePhanes kinetic-vault 同款断言：整型子像素 + 半开边界矩形）；回归用容差 |
| 骨架库假先验 | 高 | errors.md 只提升真实承重教训；骨架初期从零错误档案开始 |
| 探针"永远绿" | 高 | 三件套自校准进 CI（starter/oracle/NOP）；探针套件自身也过门 |
| **体验度量"看起来在涨"** | 高 | 上下限分离聚合（能力上限 / 风险下限 / 覆盖并集）+ 终局序硬门；自校准里**同版必须不可判为改进**（`calibration/experience/`）——否则"每轮都进步"是幻觉 |
| **体验度量混进主分** | 高 | 结构性禁止：`reward` 只由探针算；体验面单独命令、单独退出码（§3.5/§3.9） |
| **自改进"每轮都进步"是幻觉** | 高 | 冻结门 + 冻结探针集 + 轮预算/连续被拒即停 + 血统自检；自校准四例（真改进/退化/自私尺子/探针膨胀）任一失效即红（§3.10） |
| **台账不可复算（审计链断）** | 中 | 台账自带冻结门与停止参数，`rsi check` 逐轮复算并列出差异；`calibration/rsi/` 含篡改台账必红用例；改字段不改指纹也会被抓（§3.10） |
| **闭环把预算烧在同一个死角** | 中 | 连续被拒达 `--stall` 即停（默认 2）+ `rejection_memory` 告知"这一路试过了"；停止原因进台账（§3.10/§5.3） |
| **策略集太窄 → 体验结论过宽** | 中 | 报告里逐策略列清并给出 `stuck_ratio`/覆盖并集；"只测了一条路"在报告里无处隐藏（unsupported_claims 同源纪律） |
| fork 漂移 | 中 | 五条准入标准不变；CI 校验 DEEPENGINE 标记与 FORK.md 一致 |
| MoonBit 工具链演进 | 中 | 版本门禁（moonviz 同款）；内核代码避免实验特性 |
| 程序化美术表现力上限 | 中 | Minecraft 先例证明像素+电子音可成风格；Tier 1 迁移通道从 P3 起已验证，瓶颈出现时随时升级，场景/代码零改动 |
| SW 渲染性能 | 低 | 验证低分辨率少帧；交互走 GPU |
| 双实现漂移（检查器 vs 运行时） | 低 | 单语言栈结构性消除：同一 MoonBit 内核既跑运行时又跑检查器 |
| scope 膨胀 | 中 | 本文负面清单 + 每 P 的 exit 判据硬约束 |

---

## 13. 与同门项目的边界

| | moonviz | deepOffice | **deepEngine** |
|---|---|---|---|
| 对象 | UI 原型 | 办公文档 | **可玩游戏** |
| 时间语义 | 静态画板 + 状态 | 时间轴（动画一等公民） | **帧循环（实时模拟一等公民）** |
| 验证 | 谓词 + lint | 结构门槛 + 静态化导出 | **行为探针 + binary 主分 + 体验裁决面 + 自改进台账复算 + 自校准** |
| 内容来源 | .mbt.md（唯一事实源） | .mbt.md / DOF（唯一事实源） | **指引 + 多内容源 + 运行时 API**（`game.guide.md` 声明"有什么、怎么解析、怎么渲染组装"，数据住 `level.json` / `probes.json` / `policies.json` / `criteria.json` / 自改进台账 / spawn API，v1.3–v1.5） |
| 共同点 | MoonBit 内核 · 不崩谓词 · Agent 工具面 | 同 | 同（**不再共享**"唯一事实源/往返无损"——引擎域解除该约束） |

deepOffice 的 anim 时间轴经验可复用到 L1 动画系统；moonviz 的 layout/谓词/52 工具面经验可复用到 L1 与 MCP 面。**不共享代码，共享架构决策**（领域不同）。

---

## 附录：调研 → 设计决策映射总表

| 调研发现 | 出处 | 引擎落点 | 章节 |
|---|---|---|---|
| 骨架+活协议 +12 BH；hook 驱动 −10.1 去除 | OpenGame 消融 | 骨架做成引擎原语；agent 只覆写钩子 | §5 |
| 物理优先 5 原型族分类 | OpenGame | `classify` + 骨架族 | §5.1 |
| 修复 T=5 平台化 | OpenGame | 修复循环预算上限 5 | §5.3 |
| 省略即继承 / pivot 级联 / 模板强制 / UI 路线 | VibeGame 四约束 | schema 语义 | §2.1 |
| placeholder_atlas 语义帧名 + 帧耦合事件 | VibeGame | manifest 原生 + 一等字段 | §2.2/§6.2 |
| runtimeState 可观察 | VibeGame | 内核快照 API | §3.3 |
| "不算证据"四条 + 最低证据三件 | VibeGame | 验收协议 | §3.6 |
| 帧门 continue(N) + 语义输入注入 | VibeGame | 内核纯函数步进 | §3.1/§3.2 |
| VLM = semantic judge 非测量仪 | VibeGame | 视觉主观项外部模型二元判官（诊断分，非主分） | §3.5 |
| oracle/NOP 双向校准 | GamePhanes | 探针套件 CI 门 | §3.7 |
| evidence_basis/unsupported_claims/fingerprint | GamePhanes | 验证报告 schema | §3.5 |
| binary 主分 + 诊断分 | GamePhanes | 评分模型 | §3.5 |
| 行前缀事件协议 + 探针/玩家轨迹隔离 | GamePhanes | DE_EVENT + 轨迹标记 | §3.4/§7 |
| Mechanic 契约 UI→Mechanic→runtime | GameFactory | 内核三件套 + 依赖方向 | §1/§7 |
| 三态状态 + run 不可变 | GameFactory | 构建产物状态机 | §1/§9.2 |
| 6 维评审 + 归属层修复 | GameFactory | 验收维度 + 诊断归属标注 | §3.6/§9.1 |
| 付费 API 六步 + 闭集跳过理由 | GameFactory/threejs-skills | 外部生成纪律 | §9.3 |
| AI 只画源 + SHA 锁定 + 确定性派生 | Sprite Studio | 资产管线三道锁（Tier 1） | §6.1 |
| 可感知阈值 8°/1.5px/5% | Sprite Studio | 动画自动验收 | §6.3 |
| 自动修复不甩回用户 | Sprite Studio | 修复编排 | §9.1 |
| **程序化优先（计算像素 + 电子音，初期零素材）** | **Minecraft 思想（用户定策）+ OpenGame ABC→本地合成** | **Tier 0 资产层：参数即资产、100% 文本可 diff、付费 API 纪律 P0–P4 不触发** | §6.0/§6.2/§6.4 |
| 三值门禁 PASS/CONCERNS/FAIL | CCGS | 谓词裁决 | §4 |
| 引用 TR-ID 不引正文 + 版本指纹 | CCGS | 契约引用纪律 | §9.2 |
| 人玩 3 局 vertical slice 硬门 | CCGS | P2 exit 判据 | §10 |
| 引擎版本知识缺口钉版本 | CCGS | 文档版本锚定 | §9.5 |
| invoked≠loaded | threejs-skills | 报告措辞纪律 | §9.4 |
| 四面同源（CLI/MCP/WASM/SDK） | moonviz | 消费面设计 | §8 |
| 消费方视角（锚点/探针/缓存/棘轮） | deepOrca engine-integration-plan | wasm 面预案 | §8 |
| **coding-native Player：可复用策略 + 程序化接口采集多样轨迹（反 GUI 慢采集偏差）** | **RGC arXiv 2610.08621** | **`Policy`（script/explore）+ `Trace` + 策略集聚合（能力上限/风险下限/覆盖并集）** | §3.9 |
| 轨迹度量 + 显式文本偏好 + game-specific criteria | RGC | `Metrics` + `criteria.json`（标准集 + `prefer`） | §3.9 |
| Reviewer 接受更好版本、给出下一轮意见，闭环 | RGC | `adjudicate` → accept_b / keep_a / inconclusive | §3.9 |
| 递归自改进（版本接受即收敛判据） | RSIGame | 同上 + `calibration/experience/`（同版必须不可判为改进） | §3.9 |
| **主分之外需要独立的体验通道** | **RGC + RSIGame（用户提供参考）** | **体验度量不进 binary 主分；两套分数各有职责** | §3.5/§3.9 |
| **多轮自改进的两个作弊面（判据漂移 / 探针膨胀）** | **RGC + RSIGame（本轮自查）** | **冻结门 `Gate` + 冻结策略集 + `gate_shopping`/`criteria_drift`/`policy_drift` 如实标记** | §3.10 |
| 修复循环预算 T=5 | OpenGame | 自改进轮预算 `--budget`（默认 5）+ 连续被拒 `--stall` 即停 + `stop_reason` | §3.10/§5.3 |
| errors.md 失败记忆 | OpenGame | `rejection_memory` 按决定项归类被拒轮次 | §3.10/§5.2 |
| run 不可变 / 引用不引文 | GameFactory/CCGS | 体验指纹血统 + 台账自带冻结门与停止参数 + `rsi check` 复算（篡改即红） | §3.10/§9.2 |

---

*本文是 deepEngine 的总体规划基线（v1.5 起：并入"程序化优先"资产策略——Minecraft 思想继承，初期零真实素材，P0–P4 全程计算像素 + 合成电子音；v1.4 增补 §3.9 体验裁决面、v1.5 增补 §3.10 递归自改进面，输入为 RGC / RSIGame 两项外部参考）。实施期间的重大决策变更回写本文并记变更日志；可行性验证细节见 [design.md](design.md)；fork 纪律见 [FORK.md](../FORK.md)；治理声明见 [DECLARATION.md](../DECLARATION.md)。*
