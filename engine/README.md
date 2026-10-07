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
├── scene/     L1 入口与装配：guide.mbt（指引解析）+ json.mbt（零依赖 JSON）
│              + assemble.mbt（装配层）+ parse.mbt（inline 兼容）→ GameSpec
├── bridge/    B  FFI 声明（stub.c 在 app 包编译，C 符号最终链接解析）
├── runtime/   渲染映射 + CLI 分发（run / verify / shot / inspect）
├── app/       GPU 二进制 deepengine（交互，链 lib/gpu）
├── apphead/   SW 二进制（headless 验证，链 lib/sw——软件光栅，逐像素确定）
├── calibration/ 验证器自校准三件套（两条入口各自校准）
├── tests/     regression.sh（双入口等价比对）
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
`web_verify` / `web_reset` / `web_spawn_*` / `version_info`——
与 native 共享同一 kernel/scene，玩法语义单一来源（blueprint §8 四面同源）。

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

# 单元测试（172 个：kernel 22 + scene 56 + skin 6 + rendercfg 19 + retro 67）
moon test --target native

# 验证器自校准（两条入口各自过三件套 + 缺源拒绝）
./calibration/calibrate.sh

# 双入口等价比对（改造没改玩法语义的机械证据）
./tests/regression.sh
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

## 第二轮增量（继续推进）

| 增量 | 状态 |
|---|---|
| **P0 收尾：验证器三件套自校准** | ✅ `calibration/calibrate.sh`——oracle 接受 / starter 拒伪 / nop 拒空，改探针或内核后必跑 |
| **grid_logic 第二族骨架**（blueprint §5.1 物理优先分类） | ✅ kernel/grid + `mode grid` + ASCII `level` 地图 + `examples/boxpush/`（8/8 PASS） |
| **P3 起点：程序化视觉** | ✅ 金币双层旋转 / 玩家眼睛随朝向 / 平台 bevel / 尖刺三角 / 终点飘旗——参数即资产，零图片 |
| **P3 起点：chiptune 音效** | ✅ 方波扫频合成 jump/coin/win/dead，零音频文件；无硬件静默降级 |
| **P3：hero rig 程序化角色** | ✅ 参数化小人（头/身/双腿/双臂/脸）——走路摆腿摆臂、起跳伸展、坠落张臂、落地压扁+扬尘、眨眼、赢/死表情；grid 族移动补间小跳 + 推箱前倾；箱子就位眯眼笑。双端（native + web）同步实现，零图片 |
| **P3：种子化角色（skin 包）** | ✅ `seed → 特征集 → SVG`：配色（HSL 派生）/头型圆度/头饰（猫耳·角·天线·呆毛）/眼型/嘴型/纹样/腮红/比例，全部确定性派生。种子进 `level.json` 的 `player.seed`；CLI `skin <seed>` 吐 SVG 工件（文本，可 diff）；web 端真 SVG 渲染 + 部件 transform 动画；native 端同种子配色+头饰。seed 0 = 经典蓝 |
| **v1.3：指引文件降格（本次）** | ✅ `game.guide.md` 只声明「有哪些东西、怎么解析、怎么渲染组装」；关卡数据与探针外移到 `level.json` / `probes.json`。零依赖 JSON 解析器（`scene/json.mbt`）+ 指引解析（`guide.mbt`）+ 装配层（`assemble.mbt`）。测试 34 → 84 |
| **v1.3：多源组合** | ✅ 多个 `json_level` 源叠加进同一世界（平台/金币/墙数相加，标量由首个源定基线）；`empty` / `runtime` 源；`optional` 缺失跳过 |
| **v1.3：wasm 指引面** | ✅ `web_put_source` + `web_load_guide`；wasm 无 IO，reader 换成内存注册表，装配逻辑与 native 同一份 |
| **v1.3：回归与校准加固** | ✅ `tests/regression.sh` 断言双入口逐探针结果一致（改造没改玩法语义）；`calibrate.sh` 扩到两条入口 + 缺源必拒（`broken.guide.md`） |

两族管线完全共享：解析 → 内核 → 探针 → 报告 → 截图，仅 `mode` 一个词切换原型族。

## 与 blueprint 的对应（MVP 已达）

| blueprint 条目 | MVP 状态 |
|---|---|
| §3.1 帧步进纯函数 | ✅ `kernel.step`（CI 双跑断言） |
| §3.2 语义输入注入 | ✅ `right/jump/wait` 脚本 |
| §3.3 可观察性 | ✅ `runtime_value`（state/coins/x/y/frame） |
| §3.4 探针协议 | ✅ JSON 报告（stdout） |
| §3.5 binary 主分 + 自审计 | ✅ reward + evidence_basis + unsupported_claims + fingerprint |
| §3.6 "帧在动不算证据" | ✅ 输入响应探针要 x diff |
| §3.7 验证器自校准 | 🔶 通用探针 + 负样本测试通过；starter/oracle/NOP CI 化待 P0 补完 |
| §6.0 程序化优先 | ✅ MVP 全部视觉为色块/圆（参数即资产）；音频未接 |
| §10 P2 骨架 | 🔶 gravity_side 一族（探针可验） |
| §8 CLI 面 | ✅ run/verify/shot |

## 已知边界（MVP）

- `jump:N` 是"按住 N 帧"而非"变量跳跃高度"（无 jump-cut）；
- 探针脚本无 move+jump 组合原语（用 `jump:1, right:N` 表达）；
- verify 的截图回放固定取首个声明脚本末帧；
- 音频、热重载（run 模式已有 R 键）、MCP 面未实现。
