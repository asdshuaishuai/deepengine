# deepEngine engine/ —— MVP 实现

blueprint（[../docs/blueprint.md](../docs/blueprint.md)）的最小可运行切片：
**AI agent 驱动产生小游戏** 已闭环——agent 写**生命指引**（`game.guide.md`，声明有哪些东西、
怎么解析、怎么渲染组装），**关卡数据与探针住在独立内容源**（`level.json` / `probes.json`，
或运行时 spawn API），引擎负责装配、运行、验证、出证据。

## 两条入口

| 入口 | 文件 | 角色 |
|---|---|---|
| **指引**（推荐） | `game.guide.md` | 生命指引：只声明内容源清单、解析器、渲染与组装配置。**不携带关卡数据。** |
| **inline**（基线） | `game.mbg.md` | 旧单文件入口，数据与指引混在一起。保留作回归对照，不再是推荐用法。 |

两者汇入**同一个 `GameSpec` 与同一个内核**——没有两套世界构建路径
（`DECLARATION.md` 禁 workaround 重复）。等价性由 `tests/regression.sh` 机械断言。

## 项目结构

```
examples/boxpush/
├── game.guide.md    # 生命指引：有哪些源、怎么解析、怎么渲染组装
├── level.json       # 内容源：关卡几何（json_level 解析）
├── probes.json      # 内容源：行为探针声明（json_probes 解析）
├── policies.json    # 内容源：玩家策略集（json_policies 解析，v1.4）
├── criteria.json    # 内容源：质量门 + 偏好序（json_criteria 解析，v1.4）
└── game.mbg.md      # inline 入口回归基线（非推荐）
```

## 指引文件语法

缩进块式；散文（fence 外）只是文档，不参与解析：

```
game "Box Push" mode: grid        # 标题 + 原型族（决定物理形状）

source levels                     # 声明一个内容源
  path "level.json"               # 相对本文件目录
  parser json_level               # 解析器名（注册表 key）
  optional                        # 可选：缺失不报错

source probes
  path "probes.json"
  parser json_probes

render                            # 渲染配置（参数化，不含坐标）
  hero: procedural seed: player.seed
  layer platforms  bevel: 28
  layer coins      spin: 0.18

assembly
  hud "state moves boxes pos"
```

**可用 parser**：`json_level`（关卡几何）/ `json_probes`（探针）/ `inline`（旧单文件）
/ `empty`（显式空源）/ `runtime`（内容由 spawn API 生成）。**未注册的 parser 报错**，
不静默忽略。

## 结构（对应 blueprint 五层）

```
engine/
├── kernel/    L2 玩法内核：帧步进 / 语义输入 / 探针 / binary 报告（零渲染依赖）
│              + trace.mbt（策略 → 轨迹）+ metrics.mbt（体验度量 + 版本裁决）
│              + rsi.mbt（递归自改进：冻结门 / 预算与停滞 / 血统 / 台账）
├── scene/     L1 入口与装配：guide.mbt（指引解析）+ json.mbt（零依赖 JSON）
│              + assemble.mbt（装配层）+ parse.mbt（inline 兼容）→ GameSpec
│              + experience.mbt（体验评估的**唯一编排**，CLI 与 wasm 共用）
├── bridge/    B  FFI 声明（stub.c 在 app 包编译，C 符号最终链接解析）
├── runtime/   渲染映射 + CLI 分发（run / verify / trace / compare / rsi / shot / inspect）
├── app/       GPU 二进制 deepengine（交互，链 lib/gpu）
├── apphead/   SW 二进制（headless 验证，链 lib/sw——软件光栅，逐像素确定）
├── calibration/ 验证器自校准（两条入口各自三件套 + 缺源必拒）
│                experience/ 体验裁决面自校准（拒绝退化 / 接受改进 / 同版不可判）
│                rsi/ 递归自改进自校准（真改进 / 退化 / 自私尺子 / 探针膨胀 + 台账篡改必红）
├── tests/     regression.sh（双入口等价比对）+ faces_parity.sh（CLI↔wasm 度量逐字段一致）
└── build.sh
```

## 运行时衍生 API（v1.2——引擎原生路径）

内容不必来自文本文件。内核直接生成/修改实体（clone/serialize/探针全部兼容衍生实体）：

```
kernel.spawn_coin(g, x, y, w) -> Int      # 物理族：金币（返回 id，越界 -1）
kernel.spawn_platform(g, x, y, w, h)      # 平台（改变可通行性）
kernel.spawn_spike(g, x, y, w)            # 尖刺
kernel.spawn_goal(g, x, y, w, h)          # 设置/移动终点
kernel.despawn_coin(g, id)                # 移除金币
kernel.grid_spawn_box/wall/goal(g, x, y)  # grid 族三件
```

wasm 同面导出（`web_spawn_*`）；web demo 点击画布即生成（物理=金币，grid=箱子）。
**定位**：`.mbg.md` 是入口格式之一（加载器）；内核 API 是一等接口；「唯一事实源/往返无损」自 v1.2 起不是本引擎的约束（区别于 moonviz/deepOffice）。

## 资源制作与识别面（`retro` 命令，FC/SFC）

```
apphead.exe retro presets                        # 有哪些具名造型
apphead.exe retro ascii   fc idle               # 终端里直接看像素（最快自检）
apphead.exe retro chr     fc idle               # CHR hexdump（32 字节 = 2 个 8x8 图块）
apphead.exe retro svg     fc idle --scale 16     # 单帧 SVG
apphead.exe retro hero    fc --scale 12         # 六姿态动画 clip → SVG
apphead.exe retro hero    fc --preset ninja     # 换配色
apphead.exe retro identify fc idle              # 识别闭环（JSON 报告）
apphead.exe retro check   fc                    # 资源契约门禁（exit 2 = 超预算）
apphead.exe retro palette                       # FC 64 色调色板文本
```

### 硬约束来自真实硬件（不是美术偏好）

| 约束 | FC | SFC | 出处 |
|---|---|---|---|
| 精灵有效色（不含透明） | **3** | 15（恒 4bpp） | PPU OAM / CGRAM |
| 背景 metatile 色 | 4 | 2/4/8 bpp 按模式 | nametable attribute |
| 每扫描线精灵 | 8 | 32 | OAM |
| 精灵尺寸 | 8×8 / 8×16 | 8/16/32/64 方形 | PPUCTRL / OBSEL |
| 图块（8×8）占用 | 2 /帧（8×16） | 4 /帧（16×16） | tiles_per_sprite |
| 色强调 | 3 位（PPUMASK bit5/6/7） | — | colour emphasis |

**「生成彩色图再量化」是错的**：FC 精灵只有 3 色，量化只会得到抖动色斑。
本引擎**在约束内直接生成**——调色板固定 4 槽，造型靠色阶分配而非颜色渐变，
轮廓靠透明像素而非黑色描边（黑色也是 1 个色位）。

### 识别闭环

`retro identify` 走完整链路并逐项核对：

```
生成帧 → to_chr（2bpp planar）→ from_chr 读回 → 逐像素比对
       → 剔除透明 → 颜色普查 → 量化到 FC 调色板 → 预算裁决 → JSON
```

**透明标记必须先剔除**：洋红不是"第 4 色"而是"没有颜色"，算进去会让
FC 精灵误报成 4 色超预算（这是识别最容易犯的错，已有专门测试）。

CHR 编解码严格互逆，且按**图块序列**组织（8×16 = 2 个 8×8 图块，
行优先）——这是真实 CHR 的布局，产出的字节可直接喂 ROM 制作流程。

### 人物造型是宽度参数化的（`BodyBox`）

同一套造型逻辑同时服务 FC 8×16 与 SFC 16×16：身体框由帧宽推导
（`body_box(fw) = {x: 1, w: fw - 2}`），所有下半身坐标按框计算。

**这不是可有可无的抽象**：早先把下半身坐标写成绝对值
（`fill_rect(f, 3, 12, ...)`），于是 SFC 的 16 宽帧里人物只占左侧 8px、
右半全空——**SFC 支持名义上存在，实际上走了退化分支**。一个走退化分支的
"SFC 支持"比没有更危险：它看起来能用，但产出的是残缺资源。

回归防护（`retro_wbtest.mbt`）：SFC 帧的横向包围盒必须 ≥ 帧宽的 3/4、
必须触达右半区、躯干行宽度必须等于 `body_box(16).w`，
且 `walk2` 镜像不变量必须在两个平台都成立。

**当前能力边界**（写实，不夸大）：

| 能力 | FC | SFC |
|---|---|---|
| 人物精灵（6 姿态 × 6 preset） | ✅ 8×16 | ✅ 16×16 |
| 精灵色预算 | 3 色 | ✅ 同（生成器仍只用 3 色，远低于 SFC 的 15 色上限） |
| CHR 2bpp 导出 | ✅ 2 图块/帧 | ✅ 4 图块/帧（2bpp 平面格式；SFC 常用 4bpp，未实现） |
| 图块切分 / 调色板量化 / 识别闭环 | ✅ | ✅（SFC 额外提供 BGR555 打包） |
| **背景 metatile / nametable 生成** | ❌ 未实现 | ❌ 未实现 |
| **SFC 4bpp/8bpp 位平面** | — | ❌ 未实现（当前只出 2bpp） |
| **Mode 7 仿射变换** | — | ❌ 未实现 |

`retro` 的 ASCII 输出可直接看出平台差异：

```
$ retro ascii fc idle        $ retro ascii sfc idle
........                    ................
.111111.                    .11111111111111.
.1111111                    .111111111111111
..12212.                    ..122222222221..
..22222.                    ..222222222222..
....333.                    ............333.
.333333.                    .33333333333333.
...
```

### 具名造型（preset）

`plumber` / `green_cap` / `tan_hero` / `ninja` / `ice` / `fire`。
命名用"看得见的特征"而非通用词（blueprint §6.3「name it, do not
hand-describe it」）——名字本身就是美术指令。

六姿态：`idle` / `walk1` / `walk2` / `jump` / `fall` / `duck`。
`walk2` 的下半身是 `walk1` 的精确左右镜像（步态循环闭合，有测试保证）；
除 `duck`（压扁需下移头部）外所有姿态上半身逐像素稳定——这是 FC 动画的基本手法。

## Web 面（wasm-gc）

```
moon build --target wasm-gc          # 产出 _build/wasm-gc/debug/build/web/web.wasm
cd web && ELECTRON_RUN_AS_NODE=1 /Applications/ZCode.app/Contents/MacOS/ZCode smoke_web.mjs  # 烟测
cd .. && python3 -m http.server 8742  # 浏览器打开 http://127.0.0.1:8742/web-demo/
```

导出面（`web/main.mbt`）：`web_load` / `web_load_guide` / `web_reload_guide` /
`web_put_source` / `web_clear_sources` / `web_step` / `web_grid_move` / `web_frame` /
`web_verify` / **`web_trace`** / `web_reset` / `web_spawn_*` / `version_info`——
与 native 共享同一 kernel/scene，玩法语义单一来源（blueprint §8 四面同源）。

`web_trace` 与 CLI `trace` **共用 `scene.run_experience` 的同一份编排**；
`tests/faces_parity.sh` 断言两面的体验度量**逐字段相同**（篡改任一字段即红）。

wasm 面无文件 IO（Mechanic 契约），所以指引入口分两步：宿主先用
`web_put_source(path, text)` 注册内容源，再 `web_load_guide(guideText)`。
装配层拿到的是内存 reader，与 native 面的 `mbg_read_file` 是同一份装配逻辑。

## 快速开始

```bash
./build.sh

# 交互游玩（GPU 窗口）
_build/native/debug/build/app/app.exe run ../examples/platformer/game.guide.md

# headless 验证（零窗口，exit 0=PASS / 2=FAIL，stdout JSON 报告）
_build/native/debug/build/apphead/apphead.exe verify ../examples/platformer/game.guide.md --shot out.png

# 只装配不渲染——看指引声明了哪些源、实际载入了哪些（诊断用）
_build/native/debug/build/apphead/apphead.exe inspect ../examples/boxpush/game.guide.md

# 体验度量：跑完整个策略集（零渲染、零 LLM），exit 0=标准全过 / 2=有标准未过
_build/native/debug/build/apphead/apphead.exe trace ../examples/platformer/game.guide.md

# 版本裁决：A 基线 vs B 候选（判据与探针都从 A 冻结），0=accept_b / 2=keep_a / 3=inconclusive / 4=操弄判据
_build/native/debug/build/apphead/apphead.exe compare \
    ../engine/calibration/experience/v1.guide.md ../engine/calibration/experience/v2.guide.md

# 递归自改进：基线 + 按序候选（0=接受过改进 2=一轮没接受 3=发现操弄判据），台账落盘后可按它复算
H=_build/native/debug/build/apphead/apphead.exe
$H rsi run calibration/rsi/base.guide.md calibration/rsi/c1_better.guide.md > /tmp/ledger.json \
    && echo "exit=$?（接受改进）"
$H rsi check /tmp/ledger.json                                 # 0=逐轮复算一致 2=不一致

# 单元测试（240 个：kernel 72 + scene 76 + skin 6 + rendercfg 19 + retro 67，逐包实测）
moon test --target native

# 验证器自校准（两条入口各自过三件套 + 缺源拒绝 + 体验裁决面 + 自改进面自校准）
./calibration/calibrate.sh

# 双入口等价比对（改造没改玩法语义的机械证据）
./tests/regression.sh

# 四面同源：CLI 与 wasm 的体验度量逐字段一致
./tests/faces_parity.sh
```

## 内容源：level.json

关卡几何。**省略即继承**（blueprint §2.1）——未声明的字段走引擎默认值。

```json
{
  "canvas":    { "w": 960, "h": 540, "bg": "#0b0d13" },
  "physics":   { "gravity": 2000, "jump": -700, "speed": 260 },
  "player":    { "x": 80, "y": 460, "w": 28, "h": 40, "seed": 0, "color": "#4a9eff" },
  "platforms": [ { "x": 0, "y": 500, "w": 960, "h": 40, "color": "#2b3448" } ],
  "coins":     [ { "x": 340, "y": 368, "w": 20 } ],
  "spikes":    [ { "x": 520, "y": 484, "w": 40, "h": 16 } ],
  "goal":      { "x": 800, "y": 140, "w": 60, "h": 60 }
}
```

grid 族（`mode: grid`）改用 `level` 字段，ASCII 地图进 `rows_map`：

```json
{
  "level": {
    "cols": 12, "rows": 9, "cell": 48,
    "rows_map": ["############", "#.p..#..b..#", "...", "############"]
  }
}
```

字符集：`#` 墙 `p` 玩家 `b` 箱 `g` 目标 `.` 地板。

## 内容源：probes.json

```json
{
  "probes": [
    { "name": "beat_it", "script": "right:16, jump:1, right:33", "expect": "state==won" }
  ]
}
```

探针脚语法：`right:N` / `left:N` / `jump:N`（原地按住）/ `wait:N`，逗号分隔；
grid 族另有 `up:N` / `down:N`。**路线跳 = `jump:1, right:N`**（起跳沿 1 帧 + 空中横移）。

期望键（physics 族）：`state` / `coins` / `x` / `y` / `frame`；
grid 族另有 `moves` / `boxes_on`。运算符 `==` `>=` `<=` `!=`。

## inline 入口（.mbg.md，回归基线）

markdown + ```mbg fence——数据与指引混在同一个 fence 里。保留作对照：

```mbg
canvas 960 540 bg:#0b0d13
physics gravity:2000 jump:-700 speed:260
player x:80 y:460 color:#4a9eff
platform x:0 y:500 w:960 h:40
coin x:340 y:368
spike x:520 y:484 w:40
goal x:800 y:140 w:60 h:60

probe beat_it script:"right:16, jump:1, right:33" expect:"state==won"
```

inline 入口的语法与 grid 族说明见上；`level <cols> <rows> cell:<px>` + ASCII 地图行
是它的 grid 写法，指引入口的等价写法是 `level.json` 的 `level.rows_map`。

角色种子：指引入口写 `render` 块的 `hero: procedural seed: player.seed`，
种子值本身在 `level.json` 的 `player.seed`；inline 入口写 `player seed:N`。
缺省 0 = 经典蓝；同种子双端同角色；CLI `apphead.exe skin <N>` 输出该种子的 SVG 工件。

## 验证报告（stdout JSON）

```json
{"reward":1,"passed":7,"total":7,
 "contract_fingerprint":"663025-679129-970",
 "results":[...逐探针 pass/detail...],
 "evidence_basis":["kernel double-run serialize compare",...],
 "unsupported_claims":["未覆盖非脚本路径...","截图未做逐字节回归..."]}
```

stdout 只输出这一个 JSON 文档（解析警告走 stderr）——agent 可直接 `json.loads(stdout)`。

- **reward 是 binary 主分**：全部必需探针（4 个通用 + 全部声明）过才 1——零 LLM；
- 通用探针（引擎内置）：确定性双跑 / 输入响应 / 原地稳定 / 非 NaN；
- `unsupported_claims` 自声明"没证明什么"——agent 读报告时明确边界；
- 退出码：0 = PASS，1 = 解析错，2 = FAIL。

## 体验裁决面（`trace` / `compare`，v1.4 / v1.5）

**主分回答"这个游戏对不对"；这一层回答"这个游戏好不好玩"，并裁决"改完是不是更好了"。**
参考：RGC（arXiv 2610.08621）的 coding-native Player / Reviewer 闭环；RSIGame 的递归自改进。
与主分**严格分离**——体验度量不进 `reward`（blueprint §3.9 / §3.5）。

```
apphead.exe trace   <game.guide.md>                     # 策略 → 轨迹 → 度量 + 标准
apphead.exe compare <baseline.guide.md> <candidate.guide.md>   # 版本裁决（判据与探针都从基线冻结）
```

### 四段链

| 段 | 内容 | 确定性 |
|---|---|---|
| **策略** | `script`（手写路线）/ `explore(seed, frames)`（种子化分束探索） | 同 seed 必同轨迹（有测试）；帧数上限 3600，截断如实报 `truncated` |
| **轨迹** | 逐帧 `Sample`（整型化）+ 派生量（cells/revisits/stall/path/jumps） | 跨架构逐字节确定；到终态即早停（终态后的空转不算进度） |
| **度量** | progress / coverage / directness / stall_max / stall_ratio / idle_ratio / diversity / revisit / jumps | 只从轨迹来，零 LLM 零截图 |
| **裁决** | `criteria.json` 标准集 → `adjudicate` → `accept_b` / `keep_a` / `inconclusive` | 先硬门后偏好，全同即不可判 |

### 聚合语义：上下限分离（重要）

| 类别 | 取法 | 回答的问题 |
|---|---|---|
| 能力（progress / coverage / directness / diversity） | **最好那条**策略 | 至多能玩到什么程度 |
| 风险（stall_ratio / idle_ratio / stall_max） | **最差那条**策略 | 至少会卡到什么程度 |
| 覆盖度 | 所有策略的**并集** | 合起来走到过哪些格（单策略覆盖不够） |
| `stuck_ratio` | 毫无进展的策略占比 | 多少策略根本动不起来 |

两端都给的理由：只看最好，"有一条路径会卡死"被吞掉；只看最差，一条笨策略就把可玩上限抹平。

实测（`examples/platformer`，4 条策略）：

```
expert_route  终局=won     进展=100% 覆盖= 13% 停滞= 0 直达=77%
explore_a     终局=playing 进展= 33% 覆盖= 15% 停滞=36 直达= 2%
explore_b     终局=playing 进展=  0% 覆盖=  9% 停滞=22 直达= 3%
explore_c     终局=dead    进展=  0% 覆盖= 11% 停滞=30 直达=23%
聚合: 终局 won · 进展 100% · 覆盖 25%(并集 34/135 格) · 停滞 36(最差) · stuck 2/4
```

专家路线证明**可通关**，探索策略证明**可达空间**——两者互不替代。

对照案例（`examples/coinrush`，同样 4 条策略）：

```
expert_route  终局=won     进展=100% 覆盖=17% 停滞= 0 直达=64%   ← 唯一通关路径
explore_a/b/c 终局=dead/playing/dead，进展全 0%                  ← 盲走必死
聚合: 终局 won · 进展 100% · 覆盖 25%(并集 34/135) · 停滞 40 · stuck 3/4
```

同一个引擎把"**可通关且多条路都行**"（platformer）与"**可通关但只认精确路线**"
（coinrush，低容错）区分开了——这是 binary 主分给不出的信息，也正是 RGC 用
"多样策略 + 轨迹度量"替代"一条手写路径 + 截图"的理由。

### 内容源：policies.json / criteria.json

```json
{ "policies": [
  { "name": "expert_route", "kind": "script", "script": "right:16, jump:1, right:33" },
  { "name": "explore_a", "kind": "explore", "seed": 7, "frames": 900 }
] }
```

```json
{ "criteria": [
    { "name": "solvable",      "metric": "progress",  "op": ">=", "value": 100 },
    { "name": "room_explored", "metric": "coverage",  "op": ">=", "value": 20 },
    { "name": "no_dead_wall",  "metric": "stall_max", "op": "<=", "value": 60 }
  ],
  "prefer": ["progress", "coverage", "directness", "stall_max"] }
```

指引里照常声明（parser 名 `json_policies` / `json_criteria`）：

```
source policies
  path "policies.json"
  parser json_policies

source criteria
  path "criteria.json"
  parser json_criteria
```

**门禁（P0，都不静默）**：未知 `kind` / `kind=script` 缺 `script` / `frames<=0` /
未知度量名 / 非法运算符 / `prefer` 里未知度量 —— 全部报错。
理由：**标准写错名字却"通过了"比标准失败危险得多**，那是假证据。

**缺省**：未声明 `policies.json` 的游戏（含旧 `.mbg.md` 入口）走缺省探索策略
（`default_explore` seed 7 / 600 帧），`trace` 在任何游戏上都能用；
`inspect` 会如实报出"声明了几条、实际用几条"。

### 可用度量（自省见 `trace` 输出的 `known_metrics`）

| key | 含义 | 方向 |
|---|---|---|
| `outcome_rank` | won=2 / playing=1 / dead=0 | ↑ |
| `progress` | 已完成目标 / 目标总数（%） | ↑ |
| `coverage` | 访问格 / 场地格（%），聚合用并集 | ↑ |
| `directness` | 净位移 / 路径长度（%）——乱走低、直奔目标高 | ↑ |
| `stall_max` | 最长连续不动帧 | ↓ |
| `stall_ratio` / `idle_ratio` | 停滞 / 闲置帧占比（%） | ↓ |
| `diversity` | 用到的语义动作种类数 | ↑ |
| `revisit` | 重复踏入同一格的帧占比（诊断项） | ↓ |
| `jumps` / `path_len` / `frames` / `action_switches` | 原始量 | 中性 |
| `stuck_ratio` / `stuck_policies` / `policies` | 策略集层面 | ↓ |

### 裁决次序（先硬门后偏好）

1. **标准通过数**（game-specific criteria = 这版到底做没做到）——多者胜；
2. **终局序**（won > playing > dead）——拦住"覆盖度涨了但游戏打不通了"被接受；
3. **偏好序**逐项比较（`criteria.json` 的 `prefer`，缺省 `progress → coverage → directness → stall_max → stuck_ratio → idle_ratio → diversity`），首个差异即决定；
4. 全同 → `inconclusive`：**"改动即进步"不是结论**。

**判据与探针都取自 A（基线），不由候选提供**（v1.5 修正）：v1.4 曾让 `compare` 优先用候选声明的标准，
实测可被一份宽松 `criteria.json` 骗到 `accept_b`（把**打不通**的关卡判成"改进"）。
判据是尺子，尺子不能由被量的那一方提供——现在 `compare` 与 `rsi run` 共用同一个裁决单元
（`kernel.judge_versions`），候选自己的声明只作对照并如实标记：

| 标记 | 含义 |
|---|---|
| `criteria_drift` | 候选声明的判据与冻结门不同 |
| `gate_shopping` | 按候选**自己的门**比按冻结门更好看（想换尺子）→ `compare` 退出码 **4** |
| `policy_drift` | 候选声明的策略集与冻结探针集不同（它独立跑 `trace` 的数字会和这里不一致） |
| `mode_drift` | 原型族不同（physics vs grid）→ 度量同名不同义，**不予裁决**（`inconclusive`） |

`compare` 的退出码：0 = accept_b / 2 = keep_a / 3 = inconclusive / **4 = 检测到操弄判据**（优先报）/ 1 = 装配失败。

### 自校准（这一层的"不能永远绿"）

`calibration/experience/` 的 v1/v2 **只差一个参数**（走道上加满尖刺；关卡数据看起来
没变，玩起来全变了），`calibrate.sh` 断言：

```
trace   v1      → 0   全标准通过（好版本被接受）
trace   v2      → 2   标准全败（坏版本被拦）
compare v1 v2   → 2   keep_a：退化被拒
compare v2 v1   → 0   accept_b：改进被接受
compare v1 v1   → 3   inconclusive：同版不可判为改进
```

### 已知边界（体验面）

- `explore` 是**分束采样**而非逐帧噪声（噪声轨迹读不出可解释行为）；它不保证通关，
  那是 `script` 策略的职责——两者互补，报告里逐策略列清；
- 覆盖度分母是"画布 64px 分块数 / 自由格数"，**不是可达格数**（可达性靠 progress + 多策略体现）；
- 视觉证据仍走 `verify --shot` / `shot`；本层不做像素判断（VLM 判官按 §3.5 属诊断分）；
- `compare` 目前只在 native CLI 面（wasm 面只导出 `web_trace`；
  跨版本比较需要两份完整世界，宿主自己管更合适）。

## 递归自改进面（`rsi run` / `rsi check`，v1.5）

**多轮自改进和单轮比较不是同一件事。** 一旦一轮一轮地跑，候选就获得两个"看起来像进步"的作弊面：

| 作弊面 | 形态 | 为什么单轮无妨、多轮致命 |
|---|---|---|
| **判据漂移（gate shopping）** | 候选自带更松的 `criteria.json`（`progress >= 100` → `>= 0`） | 单轮只是换个标准看一次；多轮等于候选**改写评判自己的尺子**，下一轮必然"进步" |
| **探针集膨胀** | 候选自带更多探索策略（覆盖率 = 策略并集） | 关卡**一个像素都没改**，覆盖率自己就上去了；外观还是"测得更严谨" |

本层在 run 开始时**冻结判据门与策略集**（都取自基线，候选无法影响），候选声明的门/策略集只作对照。

```
# 多轮驱动：基线 + 按序候选（0=接受过改进 2=一轮没接受 3=发现操弄判据 1=参数/装配错）
apphead.exe rsi run base.guide.md c1.guide.md c2.guide.md --budget 5 --stall 2 > ledger.json

# 按台账复算（审计链）：0=逐轮一致 2=有不一致 1=读不了
apphead.exe rsi check ledger.json
```

台账（stdout 单文档）逐轮记录：base/cand 路径与**体验指纹**、裁决与理由、冻结门通过数
（`frozen_passed` vs `self_passed` 并排）、`criteria_drift` / `gate_shopping` / `policy_drift` / `mode_drift`、
`stop_reason`、`rejection_memory`（被拒轮次按**决定项**归类，agent 据此避免重复无效改动）、
`problems`（血统自检）与 `unsupported_claims`（本台账**没**证明什么）。

**冻结策略集为什么必需**：`calibration/rsi/c4_morepolicies.guide.md` 的关卡与基线**完全相同**，
只是多带 4 条探索策略——它独立跑 `trace` 时覆盖率 26 > 基线 25。若用候选自带的策略集判定，
"多带探针"就会被当成进步（实测：会被接受，理由写着 `coverage: 25 → 26`）。

### 自校准（这一层的"不能永远绿"）

```
rsi run base c1_better       → 0   接受真改进（覆盖 25→31；标准与终局不变，由偏好序的 coverage 裁定）
rsi run base c2_worse        → 2   拒绝退化（走道加尖刺，数据只多一个字段）
rsi run base c3_selfserving  → 3   与 c2 同关卡 + 自带"只有它自己过"的门（基线 0/2、它 2/2）→ 仍拒 + 标操弄
rsi run base c4_morepolicies → 2   与基线同关卡 + 多带 4 条策略 → inconclusive（冻结探针下度量逐字段相等）
rsi run base c2_worse --budget 1 → 2   轮预算即停
rsi run platformer boxpush    → 2   跨族（physics vs grid）度量同名不同义 → inconclusive，不产生裁决
rsi check <台账>              → 0   逐轮复算一致
rsi check <篡改过的台账>      → 2   必红
```

### 已知边界（自改进面）

- 候选的**产生**不是引擎的活（Designer/Builder 是 agent）——引擎只做选择 + 记账 + 可核验，
  绝不自己改关卡去"提升"度量（blueprint §11）；
- "接受"只意味着按**冻结门 + 偏好序**更优，不意味着绝对质量更高；
- 被拒候选的**内容**不归档（只记指纹与决定项），需要留档时由 agent 自己保留文件；
- `rsi` 只在 CLI 面（多文件 + 多轮驱动 + 台账落盘是 shell/CI 的活），wasm 面不导出。

## 第二轮增量（继续推进）

| 增量 | 状态 |
|---|---|
| **P0 收尾：验证器三件套自校准** | ✅ `calibration/calibrate.sh`——oracle 接受 / starter 拒伪 / nop 拒空，改探针或内核后必跑 |
| **grid_logic 第二族骨架**（blueprint §5.1 物理优先分类） | ✅ kernel/grid + `mode grid` + ASCII `level` 地图 + `examples/boxpush/`（8/8 PASS） |
| **P3 起点：程序化视觉** | ✅ 金币双层旋转 / 玩家眼睛随朝向 / 平台 bevel / 尖刺三角 / 终点飘旗——参数即资产，零图片 |
| **P3 起点：chiptune 音效** | ✅ 方波扫频合成 jump/coin/win/dead，零音频文件；无硬件静默降级 |
| **P3：hero rig 程序化角色** | ✅ 参数化小人（头/身/双腿/双臂/脸）——走路摆腿摆臂、起跳伸展、坠落张臂、落地压扁+扬尘、眨眼、赢/死表情；grid 族移动补间小跳 + 推箱前倾；箱子就位眯眼笑。双端（native + web）同步实现，零图片 |
| **P3：种子化角色（skin 包）** | ✅ `seed → 特征集 → SVG`：配色（HSL 派生）/头型圆度/头饰（猫耳·角·天线·呆毛）/眼型/嘴型/纹样/腮红/比例，全部确定性派生。种子进 `level.json` 的 `player.seed`；CLI `skin <seed>` 吐 SVG 工件（文本，可 diff）；web 端真 SVG 渲染 + 部件 transform 动画；native 端同种子配色+头饰。seed 0 = 经典蓝 |
| **v1.3：指引文件降格** | ✅ `game.guide.md` 只声明「有哪些东西、怎么解析、怎么渲染组装」；关卡数据与探针外移到 `level.json` / `probes.json`。零依赖 JSON 解析器（`scene/json.mbt`）+ 指引解析（`guide.mbt`）+ 装配层（`assemble.mbt`）。测试 34 → 84 |
| **v1.3：多源组合** | ✅ 多个 `json_level` 源叠加进同一世界（平台/金币/墙数相加，标量由首个源定基线）；`empty` / `runtime` 源；`optional` 缺失跳过 |
| **v1.3：wasm 指引面** | ✅ `web_put_source` + `web_load_guide`；wasm 无 IO，reader 换成内存注册表，装配逻辑与 native 同一份 |
| **v1.3：回归与校准加固** | ✅ `tests/regression.sh` 断言双入口逐探针结果一致（改造没改玩法语义）；`calibrate.sh` 扩到两条入口 + 缺源必拒（`broken.guide.md`） |
| **v1.4：体验裁决面** | ✅ `kernel/trace.mbt`（`Policy` → `Trace`，逐帧整型化、终态早停、**不扰动传入世界**）+ `kernel/metrics.mbt`（度量 + 策略集聚合 + `adjudicate`）+ `scene/experience.mbt`（唯一编排）+ 内容源 `policies.json` / `criteria.json`（三个示例都有）+ 消费面 `trace` / `compare`（CLI）与 `web_trace`（wasm）+ `calibration/experience/` 自校准 + `tests/faces_parity.sh`。测试 172 → **217** |
| **v1.5：递归自改进面（本次）** | ✅ `kernel/rsi.mbt`（冻结门 `Gate` + 冻结策略集指纹 + 轮预算/连续被拒即停 + 体验指纹血统 + `rejection_memory` + 台账自检）+ CLI `rsi run` / `rsi check`（按台账复算，篡改即红）+ `calibration/rsi/` 四例（真改进/退化/自私尺子/探针膨胀）+ 台账篡改必红；`scene/experience.mbt` 增 `run_experience_with`（冻结探针集评估）；`scene/json.mbt` 补标准 `\u` 转义（工具转手的台账要能读回）。测试 217 → **240** |
| **v1.4：脚本解析器去重** | ✅ 渲染回放原本自带第三份脚本解析器——现 `kernel.script_plan` / `grid_plan` 是**唯一**展开逻辑，探针 / 轨迹 / 渲染三路共用 |

两族管线完全共享：解析 → 内核 → 探针 → 报告 → 截图，仅 `mode` 一个词切换原型族。

## 与 blueprint 的对应（MVP 已达）

| blueprint 条目 | MVP 状态 |
|---|---|
| §3.1 帧步进纯函数 | ✅ `kernel.step`（CI 双跑断言）；轨迹逐帧整型化，跨架构确定 |
| §3.2 语义输入注入 | ✅ `right/jump/wait` 脚本（唯一解析器 `script_plan`） |
| §3.3 可观察性 | ✅ `runtime_value`（state/coins/x/y/frame）+ `Trace` 逐帧采样 |
| §3.4 探针协议 | ✅ JSON 报告（stdout） |
| §3.5 binary 主分 + 自审计 | ✅ reward + evidence_basis + unsupported_claims + fingerprint；体验度量**不进**主分 |
| §3.6 "帧在动不算证据" | ✅ 输入响应探针要 x diff |
| §3.7 验证器自校准 | ✅ 三件套 CI 化（两条入口）+ 体验裁决面自校准（拒绝退化/接受改进/同版不可判） |
| **§3.9 体验裁决面** | ✅ 策略 → 轨迹 → 度量 → 标准 → 版本裁决；CLI 与 wasm 同源（`faces_parity.sh`） |
| **§3.10 递归自改进面** | ✅ 冻结门 + 冻结探针集 + 预算/停滞停止 + 血统台账 + `rsi check` 复算；四例自校准 + 篡改必红（仅 CLI 面） |
| §6.0 程序化优先 | ✅ MVP 全部视觉为色块/圆（参数即资产）；音频未接 |
| §10 P2 骨架 | 🔶 gravity_side + grid_logic 两族（探针可验） |
| §8 CLI 面 | ✅ run / verify / trace / compare / shot / inspect；MCP 面未实现 |

## 已知边界（MVP）

- `jump:N` 是"按住 N 帧"而非"变量跳跃高度"（无 jump-cut）；
- 探针脚本无 move+jump 组合原语（用 `jump:1, right:N` 表达）；
- verify 的截图回放固定取首个声明脚本末帧；
- 体验面的边界（探索策略不保证通关、覆盖分母不是可达格、`compare` 仅 CLI 面）见上一节；
- 自改进面的边界（引擎不生成候选、接受≠绝对更好、被拒内容不归档、仅 CLI 面）见上一节；
- 音频、热重载（run 模式已有 R 键）、MCP 面未实现。
