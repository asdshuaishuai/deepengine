# Box Push —— grid_logic 原型族：真正的推箱谜题

> **本文件是 inline 入口的回归基线，不再是推荐用法。**
> 推荐入口是同目录的 `game.guide.md` + `level.json` + `probes.json`。
> 保留本文件供 `engine/tests/regression.sh` 做双入口等价比对。

双箱顺序谜题：中间的隔断墙把场地分成两半，底部通道是唯一捷径。
**必须先送右下角的箱子进左目标**——否则它会挡住上路箱子的落点。

规则：箱子只能推不能拉，抵墙/抵箱即阻；两箱全部就位即胜。

本文件由 AI agent 仅通过 .mbg.md 创作——引擎代码零改动。
解法路线由 agent 推演后写成行为探针，由引擎验证（约 25 步）。

操作（run 模式）：方向键移动，R 重开，ESC 退出。

图例：`#` 墙  `p` 玩家  `b` 箱子  `g` 目标格  `.` 地板

```mbg
mode grid

canvas 576 432
player seed:42
level 12 9 cell:48

############
#..........#
#.p..#..b..#
#....#.....#
#....#.....#
#....#..b..#
#....#.....#
#.....g.g..#
############

# ---- 行为探针 ----

# 顺序依赖：直接去推上路箱子，只能推两步就被下路箱子顶住（一无所获）
probe wrong_order_fails script:"up:1, right:6, down:4" expect:"boxes_on==0"

# 第一步：绕到下路箱子上方，连推两步直落右目标格
probe first_box_home script:"up:1, right:7, down:3, left:1, down:2" expect:"boxes_on==1"

# 墙被尊重
probe walls_hold script:"up:9" expect:"y==1"

# 完整解法：先下后上，两箱全就位（agent 推演的 32 步路线）
probe beat_the_puzzle script:"up:1, right:7, down:3, left:1, down:2, right:1, up:5, left:1, down:4, right:1, down:1, left:2, up:1, left:1, down:1" expect:"state==won"
```
