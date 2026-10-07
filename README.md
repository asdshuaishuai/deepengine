# deepEngine

基于 [raylib](https://github.com/raysan5/raylib) 的 **MoonBit + AI-native 游戏引擎**。

> **raylib 是引擎，我们不重造引擎。**
> 我们做两件事：让 MoonBit 能原生低摩擦地驱动 raylib；补齐 AI Agent 驱动所需的能力
> （声明式入口 + 运行时衍生、确定性验证、不崩谓词）。
>
> 同时，raylib 中有几处阻碍这些目标的通用缺陷，我们在**受管理的 fork** 中直接修复——
> 而不是在适配层堆 workaround。
>
> 完整定位、边界与合规声明见 **[DECLARATION.md](DECLARATION.md)**（治理文件，具约束力）。
> 全部 fork 改动见 **[FORK.md](FORK.md)**。
> **总体规划见 [docs/blueprint.md](docs/blueprint.md)**（v1.1 已批准基线：五层架构 / 验证协议 / 骨架库 / 里程碑 P0–P5 / **程序化优先资产策略——初期零真实素材，计算像素 + 合成电子音**）。

## 上游关系

这是一个**修改版 fork**，改动被严格控制在最小范围：

| 项 | 值 |
|---|---|
| 上游 | https://github.com/raysan5/raylib |
| 基线提交 | `6ecf21f700642c797dd0f2f3d4b1f2c91b71711d` |
| 基线版本 | `6.1.0` |
| 我们的分支 | `deepengine` |
| 上游镜像分支 | `master`（纯上游，不提交） |
| **改动规模** | **3 个文件，+34 / −2 行** |

```bash
cd raylib && git branch -vv          # 分支结构
git diff master deepengine --stat    # 改动范围
```

## 当前状态

**MVP 已达成：AI agent 驱动产生小游戏的闭环打通**（blueprint v1.1 批准后实施）。

| 里程碑 | 状态 |
|---|---|
| 可行性验证（fork D1–D3 / MoonBit FFI / headless 渲染） | ✅ |
| 总体规划 blueprint v1.1（含程序化优先资产策略） | ✅ 已批准 |
| **MVP：agent 只写 .mbg.md 即可创作 + 验证小游戏** | ✅ **达成** |
| P0 收尾：验证器自校准三件套（oracle/starter/nop） | ✅ `engine/calibration/` |
| P2 两族骨架：gravity_side + grid_logic | ✅ 三个示例游戏全 PASS |
| P3 起点：程序化视觉 + chiptune 音效 | ✅ 零素材文件 |
| **P4 wasm 面 + Web Demo** | ✅ kernel 编译 wasm-gc，浏览器可玩 + 可验证（`web-demo/`） |
| **P3：种子化角色（skin 包）** | ✅ `seed → 特征 → SVG`（配色/头型/头饰/眼型/纹样确定性派生）；CLI `skin <seed>` 吐 SVG 工件；web 真 SVG 渲染 + 部件动画；`player seed:N` 进事实源 |
| **Web Demo 换肤** | ✅ 图鉴（16 种子缩略图）+ 任意 seed 输入，即时换角色（纯视图层） |
| **v1.2 运行时衍生 API** | ✅ 内核一等接口：`spawn_coin/platform/spike/goal/despawn`（物理族）+ `grid_spawn_box/wall/goal`（grid 族）——内容不经文本文件直接生成；web 点击画布即时生成；wasm 全导出 |
| **v1.3 指引文件降格（本次）** | ✅ `.mbg.md` 不再是唯一事实源，降为**生命指引** `game.guide.md`：只声明「有哪些东西、怎么解析、怎么渲染组装」。关卡数据与探针外移到 `level.json` / `probes.json`，另可来自运行时 spawn API。装配层 `scene/assemble.mbt` + 零依赖 JSON 解析器；测试 34 → **84/84**（本轮合计 **172/172**） |
| **v1.3 多源组合 + 双入口等价** | ✅ 多个 `json_level` 源叠加进同一世界；`optional` / `empty` / `runtime` 源；`tests/regression.sh` 机械断言双入口逐探针结果一致（改造未改玩法语义）；`calibrate.sh` 扩到两条入口 + 缺源必拒 |
| **render 契约兑现（v1.3 补）** | ✅ 指引 `render` 块的参数真正驱动渲染层：`bevel` / `edge` / `spin` / `teeth` / `flag` / `grip` / `rig` / `dust` + HUD 字段由 `assembly` 声明。五项参数经**像素级验证**（改参数 → PNG 差异）；inspect 输出"声明 → 生效值" |
| **FC/SFC 资源制作与识别面（本次）** | ✅ `engine/retro/`：**硬件约束写成可执行数据**（精灵 3 色 / 扫描线 8 / 图块占用 / 色强调位，均据 nesdev+wiki.superfamicom 核实）+ FC 64 色调色板 + **受约束的程序化人物生成器**（6 姿态 × 6 具名 preset，帽子/脸/胡子/躯干/双腿/鞋，每精灵恒 ≤3 色）+ **CHR 2bpp planar 编解码**（严格互逆，按图块序列组织，可直接喂 ROM 流程）+ **识别闭环**（生成→CHR→读回→普查→预算裁决）+ SVG/ASCII/hexdump 工件 |
| **SFC 去退化（本次修复）** | ✅ 人物造型改为**宽度参数化**（`BodyBox`）：此前下半身坐标写死 8 宽假设，SFC 的 16×16 帧里人物只占左侧 8px、右半全空——SFC 支持名义存在实为退化分支。现同一套逻辑服务 FC 8×16 与 SFC 16×16，并有 6 条 SFC 专属回归测试（占满宽度 / 触达右半 / 躯干宽度 / 跨平台镜像不变量）。未实现项在 `engine/README.md` 写明边界（背景 metatile、4bpp/8bpp、Mode 7） |
| **P0–P4 完整版（MCP 面 / 骨架库全族 / 背景图块生成器）** | 🔜 |

**MVP 证据**（全部可复现）：

- `engine/`——六包实现：kernel（**两族**：gravity_side + grid_logic）/ scene（指引解析 + JSON 内容源 + 装配层 + inline 兼容）/ rendercfg（渲染配置契约）/ **retro（FC/SFC 资源制作与识别）** / bridge + runtime + 双二进制（GPU 交互 / 软件光栅 headless）；**172/172 单测**；
- `engine/retro/`——`retro check fc|sfc` 资源契约门禁 + `retro identify` 识别闭环（CHR 往返逐像素一致、用色在预算内）+ `retro hero` SVG 工件（`shots/retro/*.svg`）；
- `engine/calibration/`——**验证器自校准**：oracle 真 work 被接受 / starter 伪声明被拒 / nop 空输入被拒 / 缺源必拒——**两条入口各自校准**，验证器不是永远绿；
- `engine/tests/regression.sh`——**双入口等价比对**：指引入口与 inline 入口在三个示例上产出逐探针一致的结果；
- `examples/platformer/`、`examples/coinrush/`、`examples/boxpush/`——三个游戏全 PASS（7/7、7/7、8/8），每个含 `game.guide.md` + `level.json` + `probes.json`；
- 验证器非"永远绿"：坏游戏负样本正确拒绝（reward=0）；跨运行报告逐字节一致。

两项已定策：① P2 首发骨架 `gravity_side` + `grid_logic`；② **程序化优先**（Minecraft 思想继承）——MVP 全部视觉为计算像素（色块/圆），资产即参数。

| 验证项 | 结果 |
|---|---|
| MoonBit 可驱动 raylib | ✅ 原生目标 + C stub 端到端跑通 |
| 无头确定性渲染 | ✅ 软件光栅后端可用（修复 D1/D2 后） |
| 两后端输出一致性 | ✅ 纯几何逐像素一致；纹理采样有固有差异（见下） |
| raylib 授权可商用 | ✅ zlib/libpng，允许修改与再分发 |
| 是否存在 MoonBit 绑定 | ❌ raylib 官方 177 个绑定中无 MoonBit——空缺 |

**规划输入**：deepOrca 游戏开发调研六项目全景（OpenGame 消融定量 / VibeGame 约束设计 /
GamePhanes 评测校准 / GameFactory Mechanic 契约 / Sprite Studio 确定性资产 / CCGS 治理），
逐条转化为引擎机制，映射表见 [blueprint 附录](docs/blueprint.md)。

## 目录

```
deepEngine/
├── DECLARATION.md          项目声明（治理文件）
├── FORK.md                 fork 改动清单 —— 与上游的全部分歧
├── NOTICE.md               第三方组件与许可（分发时必须随附）
├── docs/
│   ├── blueprint.md        引擎层总体规划 ★★★（实施基线）
│   └── design.md           可行性验证记录与设计探索
├── engine/                 ★★ MVP 实现（kernel/scene/bridge/runtime/双二进制/web wasm 面）
│   └── README.md           用法与 .mbg.md 语法
├── web-demo/               浏览器演示（三游戏可玩可验证，wasm 内核）
├── examples/
│   ├── platformer/         第一个游戏（verify 7/7 PASS）
│   └── coinrush/           agent 仅写 .mbg.md 创作的游戏（首验即 PASS）
├── demo/                   验证脚本
│   ├── fork_verify.c       fork 三项修复的验证 ★
│   ├── scene.mbg.md        声明式场景格式雏形
│   ├── scene_demo.c        2D/3D/热重载/确定性截图
│   └── headless_probe.c    无窗口渲染验证
├── spike-moonbit/          MoonBit 驱动 raylib 的验证
│   ├── main/main.mbt       场景图 / 节点 / 动画 / 主循环
│   ├── main/stub.c         FFI 桥（UTF-16↔UTF-8 + raylib 封装）
│   └── main/moon.pkg       C stub 与链接配置
├── lib/{gpu,sw}/           raylib 构建产物（从 fork 构建）
└── shots/                  验证截图
```

## Fork 改动（3 处）

每处都在源码中带 `DEEPENGINE:` 标记，详细说明见 [FORK.md](FORK.md)。

| 编号 | 问题 | 为何修在源头 |
|---|---|---|
| **D1** | macOS 下 `PLATFORM_MEMORY` 计时器缺失 → `SetTargetFPS()` 100% CPU 死锁 | 适配层唯一的规避方式是「永不调用该 API」——那是功能残废，不是适配 |
| **D2** | 软件后端像素读回上下颠倒 + 红蓝互换 | 适配层需自行读像素并做探测归一化，约 110 行 workaround，且易随上游变化而失效 |
| **D3** | `TakeScreenshot()` 不刷新渲染批次 → 帧中途截图为空 | 强制每个调用点记得手动 flush，是把内部实现细节泄漏给使用者 |

修复的直接收益：`demo/scene_demo.c` 的适配层代码从约 110 行 workaround **缩减为 3 行**。

### 两后端的渲染差异（非缺陷）

| 区域 | 差异 | 说明 |
|---|---|---|
| 纯几何（圆、矩形、线） | **0.00%** | 完全一致 |
| 纹理采样（文字字形、缩放旋转的精灵） | 0.3%–2.3% | GPU 硬件双线性滤波 vs rlsw 软件实现的固有差异 |

**AI 验证链路固定使用软件后端**（完全确定性），因此该差异不影响验证可靠性；GPU 后端仅用于给人看的交互场景。

## 适配层要解决的问题

「AI-native」在本项目里是可验证的工程约束，不是营销词。六项能力：

| # | 能力 | 为何必要 |
|---|---|---|
| 1 | 声明式入口 + 运行时衍生 | .mbg.md 表达初始意图；内核 spawn API 运行时生成内容（引擎原生路径是衍生，v1.2 解除唯一事实源约束） |
| 2 | 可确定性复现 | 相同输入必须产生相同输出，否则验证无意义 |
| 3 | 可无头渲染 | Agent 常运行于无显示器/无 GPU 环境 |
| 4 | 不崩谓词 | Agent 会产出错误输入，必须拒绝而非崩溃 |
| 5 | 廉价迭代闭环 | 改一次看一次的成本必须极低 |
| 6 | 可解释反馈 | 拒绝时须说明原因，Agent 才能自我修正 |

## 不做什么

按 [DECLARATION.md §二](DECLARATION.md) 的负面清单：

- ❌ 不重写 raylib 任何模块
- ❌ 不做无关改动（每处 fork 改动须通过五条准入标准）
- ❌ 不声称拥有 raylib 或其衍生作品
- ❌ 不把改动版当作原版分发
- ❌ 不删除或篡改 raylib 的 LICENSE 与署名
- ❌ 不在适配层重复实现 raylib 已有的功能

## Fork 改动准入标准

新增任何 fork 改动**必须同时满足**（详见 [DECLARATION.md §四](DECLARATION.md)）：

1. 无法在适配层合理规避
2. 属于通用缺陷（对上游所有使用者有益）
3. 改动最小，不改变公开 API 语义
4. 带 `DEEPENGINE:` 注释指向 FORK.md
5. 有可复现的验证脚本

## 许可

- **raylib**：zlib/libpng，© 2013-2026 Ramon Santamaria (@raysan5)。**本项目使用其修改版**，改动已在 [NOTICE.md](NOTICE.md) 与 [FORK.md](FORK.md) 中明确标注
- **本项目适配层**：MIT，© 2026 deepEngine contributors

分发时必须随附 [NOTICE.md](NOTICE.md)。
