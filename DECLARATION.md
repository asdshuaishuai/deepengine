# deepEngine 声明

> 本文件是 deepEngine 项目的**定位、边界与合规声明**，对项目所有参与者（人与此仓库中的 AI Agent）具有约束力。
> 生效日期：2026-09-30

---

## 一、一句话定位

**deepEngine 是基于 [raylib](https://github.com/raysan5/raylib) 的 MoonBit + AI-native 游戏引擎。**

我们**不重新发明引擎**——图形、平台、资源加载全部由 raylib 承担。我们在其之上做两件事：

1. 让 MoonBit 能原生、低摩擦地驱动 raylib；
2. 补齐 AI Agent 驱动所需的能力（声明式入口 + 运行时衍生、可验证性、不崩谓词）。

同时，raylib 中确有阻碍上述目标的**通用缺陷**，我们在**受管理的 fork** 中直接修复它们——而不是在适配层堆 workaround。

---

## 二、我们不做什么（负面清单）

| # | 禁止事项 | 理由 |
|---|---|---|
| 1 | **不重写 raylib 的任何模块** | 我们不是引擎作者，重写是浪费与分叉 |
| 2 | **不声称拥有 raylib 或其衍生作品** | 违反 zlib 许可第 1 条 |
| 3 | **不把改动版当作原版分发** | 违反 zlib 许可第 2 条 |
| 4 | **不删除或篡改 raylib 的 LICENSE 与署名** | 违反 zlib 许可第 3 条 |
| 5 | **不做无关改动** | 每一处 fork 改动都必须有明确理由（见 §四） |
| 6 | **不把引擎语义塞进 C 层** | 见 §六 分层边界 |
| 7 | **不在适配层重复实现 raylib 已提供的功能** | 那等于隐性分叉 |

---

## 三、与上游的关系：受管理的 fork

### 3.1 Fork 结构

| 项 | 值 |
|---|---|
| 上游 | `https://github.com/raysan5/raylib.git` |
| 远端名 | `upstream` |
| 基线提交 | `6ecf21f700642c797dd0f2f3d4b1f2c91b71711d` |
| 基线版本 | `6.1.0` |
| 我们的分支 | `deepengine` |
| 上游镜像分支 | `master`（纯上游，不提交） |
| **改动规模** | **3 个文件，+34 / −2 行** |

```
upstream/master ──► master（本地镜像，只 fetch，永不提交）
                        │
                        └──► deepengine（我们的改动全部在此）
```

### 3.2 为什么 fork

最初我们尝试零分叉（改动全部留在适配层），但实测发现两个问题：

1. **有些缺陷在适配层无法干净规避**。例如 macOS 上 `PLATFORM_MEMORY` 后端的计时器缺失会导致 `SetTargetFPS()` 死锁——适配层唯一能做的只是"永远不要调用这个 API"。这不是适配，是**功能残废**。
2. **把引擎内部实现细节泄漏给调用方**。例如 `TakeScreenshot()` 需要调用方记得先手动 flush 批次，这是把批处理边界问题外推给使用者。

因此我们改为 fork，但坚持**受管理**：改动最小化、逐条记录、可 rebase。

**当然，能修在源头的前提是"该修"**——新增任何改动须满足 §四 的准入标准。

### 3.3 同步机制

```bash
cd raylib
git fetch upstream
git checkout master && git merge --ff-only upstream/master   # 更新镜像
git checkout deepengine && git rebase master                 # 变基我们的改动
```

因改动面极小且集中（3 处，均带 `DEEPENGINE:` 标记），rebase 冲突风险很低。

### 3.4 与上游的互动方式：不回馈，只同步

**本项目不向上游提交 issue 或 PR。**

原因：本项目采用 AI 驱动开发，没有人工通读过 raylib 源码。在没有真实理解上游设计意图的情况下提 issue/PR，质量没有保障，也是对上游社区的不负责。因此：

1. **缺陷一律内部解决**——修在 `deepengine` 分支，逐条登记于 FORK.md；
2. **对上游只有一种互动**：`git fetch` 同步更新；
3. **若上游独立修复了同一问题**——rebase 时采用上游方案，丢弃我们的改动。

这不影响许可合规：zlib/libpng 只要求「修改版必须清楚标注」，不要求回馈上游。标注义务由 [FORK.md](FORK.md) 与 [NOTICE.md](NOTICE.md) 履行。

---

## 四、Fork 改动准入标准

向 fork 添加任何改动前，**必须同时满足**以下五条：

| # | 标准 | 说明 |
|---|---|---|
| 1 | **无法在适配层合理规避** | 若适配层能干净解决，就不该动上游 |
| 2 | **属于通用缺陷** | 对上游所有使用者都有益，而非 deepEngine 专属需求 |
| 3 | **改动最小** | 不做无关重构，不改变公开 API 语义 |
| 4 | **带 `DEEPENGINE:` 注释** | 指向 `FORK.md` 的对应条目 |
| 5 | **有可复现的验证** | `demo/` 下有对应验证脚本 |

不满足任一条件，一律拒绝。

**当前全部改动**（详见 [FORK.md](FORK.md)）：

| 编号 | 文件 | 问题 |
|---|---|---|
| D1 | `rcore_memory.c`, `rcore.c` | macOS 下 `PLATFORM_MEMORY` 计时器缺失 → `SetTargetFPS()` 死锁 |
| D2 | `rlgl.h` | 软件后端像素读回方向颠倒 + 通道互换 |
| D3 | `rcore.c` | `TakeScreenshot()` 不刷新渲染批次 → 截图为空帧 |

---

## 五、版权与授权

### 5.1 raylib（上游）

```
Copyright (c) 2013-2026 Ramon Santamaria (@raysan5)
License: zlib/libpng
```

zlib/libpng 授予任何人：商业使用、修改、再分发（含闭源）、无版税。**三项限制**：

1. 不得歪曲来源，不得声称原创 —— *我们不这么做* ✓
2. **修改版必须清楚标注，不得冒充原版** —— *我们如何满足见下* ✓
3. 不得移除或篡改许可声明 —— *LICENSE 原样保留* ✓

### 5.2 关于许可第 2 条（改动标注）

由于我们**确有修改**，必须履行"清楚标注"义务。我们的做法：

| 措施 | 位置 |
|---|---|
| 每处改动带 `DEEPENGINE:` 注释，说明根因与验证方式 | 源码内 |
| 完整的改动清单 | [FORK.md](FORK.md) |
| 分支命名明确区分（`deepengine` vs `master`） | Git |
| 版本标识追加 `-deepengine` 后缀 | 构建产物 |
| 对外文档明确说明"基于 raylib 的修改版" | [README.md](README.md) |

**我们绝不宣称 fork 后的版本等同于原始 raylib。**

### 5.3 适配层（我们）

Copyright (c) 2026 deepEngine contributors，**MIT** 许可，与同门项目 `deepStudio/moonviz`、`deepStudio/deepOffice` 一致。

### 5.4 署名义务的履行

| 位置 | 内容 |
|---|---|
| `README.md` | 首段说明基于 raylib（修改版），附仓库链接 |
| `NOTICE.md` | 完整第三方组件清单与许可全文 |
| `FORK.md` | 改动清单 |
| 产品关于页 / 启动信息 | "Based on raylib — © Ramon Santamaria and contributors" |
| 二进制分发 | 附 `NOTICE.md` 或等效声明 |

---

## 六、分层边界

```
┌────────────────────────────────────────────┐
│  L2  deepEngine 适配层（MoonBit）           │  ← 我们的大部分工作
│      场景图 / 时间轴 / 布局 / 谓词            │
│      .mbg.md 入口 + 运行时衍生 / Agent 工具面   │
├────────────────────────────────────────────┤
│  L1  FFI 桥（C stub）                       │  ← 我们的工作
│      UTF-16↔UTF-8 / 句柄 / 参数编解码         │
├────────────────────────────────────────────┤
│  L0  raylib fork（C）                       │  ← 我们的修复集中于此
│      平台后端 / 光栅化 / 资源加载 / 数学       │
└────────────────────────────────────────────┘
```

### 纪律

- **L0 修改必须逐条登记**：`FORK.md` 是唯一权威清单，代码中的 `DEEPENGINE:` 注释必须与之对应；
- **L1 无状态、无游戏语义**：只做类型/编码转换与调用转发。唯一例外是可持有**不透明句柄**；
- **L2 承载全部语义**：所有游戏/场景/动画概念只存在于 MoonBit 层。

### 允许的接缝

与 raylib 交互只通过：

1. raylib 公开头文件（`raylib.h` / `rlgl.h` / `raymath.h` / `rcamera.h`）
2. raylib 官方编译期配置宏（`CUSTOMIZE_BUILD` + `RAYLIB_CONFIG_FLAGS`）
3. 构建产物（`libraylib.a` / `.so` / `.dylib`）

超出这三者的交互，视为违规依赖。

---

## 七、AI-native 的适配内涵

「AI-native」在本项目中是可验证的**工程约束**，不是营销词。六项能力必须成立：

| # | 能力 | 为何必要 |
|---|---|---|
| 1 | **声明式入口 + 运行时衍生** | Agent 以文本（.mbg.md）表达初始意图，亦可在运行时经内核 API 即时生成/修改内容——引擎原生路径是衍生，不设唯一事实源（v1.2 起，区别于 moonviz/deepOffice） |
| 2 | **可确定性复现** | 相同输入必须产生相同输出，否则 Agent 的验证毫无意义 |
| 3 | **可无头渲染** | Agent 常运行于无显示器/无 GPU 环境 |
| 4 | **不崩谓词** | Agent 会产出错误输入，引擎必须拒绝而非崩溃 |
| 5 | **廉价迭代闭环** | 改一次看一次的成本必须极低，否则 Agent 迭代不收敛 |
| 6 | **可解释反馈** | 拒绝时须说明原因，Agent 才能自我修正 |

**这六项主要实现在 L2，但 L0 必须提供必要支撑**——例如第 3 项依赖软件光栅后端可用，这正是 D1/D2 修复的意义。

---

## 八、变更纪律

任何改动必须满足：

1. **L0 改动须先通过 §四 准入标准**，并在 `FORK.md` 登记；
2. **CI 校验**：`FORK.md` 登记的条目与代码中 `DEEPENGINE:` 标记数量一致；
3. **适配层不引入对 raylib 内部符号的依赖** —— 只用公开头文件；
4. **每次上游 rebase 后跑确定性像素回归**，基线不得漂移；
5. **保留全部署名** —— 任何分发形态必须携带 `NOTICE.md`。

---

## 九、溯源与可验证性

| 承诺 | 验证方法 |
|---|---|
| 改动清单完整 | 代码中每个 `DEEPENGINE:` 标记都指向 FORK.md 中存在的条目（注意 D1 跨两个文件，标记数会多于条目数） |
| 分支结构正确 | `git -C raylib branch -vv`，`master` 应指向 `upstream/master` |
| 镜像分支纯净 | `git -C raylib diff master upstream/master`（应无输出） |
| 署名完整 | `cat NOTICE.md` |
| 改动可追溯 | `git -C raylib log deepengine --oneline` |
| 确定性成立 | 同输入连续两次渲染，输出 PNG 逐字节一致 |
| 无头可用 | 无显示器环境跑软件后端渲染 + 截图，应成功 |

---

## 十、声明变更

本声明是项目的**治理文件**。修改需满足：

1. 不得放松 §二 负面清单与 §四 准入标准；
2. 放宽其他条款需说明理由并记录日期；
3. 所有变更在 `CHANGELOG` 中留痕。

---

## 附：声明摘要（用于 README / 对外沟通）

> deepEngine 基于 [raylib](https://github.com/raysan5/raylib)（© Ramon Santamaria and contributors，zlib/libpng 许可）构建。
>
> 这是一个**修改版**：我们修复了 3 处影响 AI-native 场景的通用缺陷（macOS 无头渲染计时器、软件渲染像素读回、截图批次刷新），每处改动都在源码中以 `DEEPENGINE:` 标记，完整清单见 [FORK.md](FORK.md)。除此之外 raylib 保持原样。
>
> 我们的工作是 raylib 之上的 MoonBit 语言绑定与 AI-native 适配层。raylib 与本项目是两份独立作品，分别适用 zlib/libpng 与 MIT 许可。我们感谢 raylib 作者与社区的工作。
