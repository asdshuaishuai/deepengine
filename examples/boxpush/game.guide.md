# Box Push —— grid_logic 原型族：真正的推箱谜题

双箱顺序谜题：中间的隔断墙把场地分成两半，底部通道是唯一捷径。
**必须先送右下角的箱子进左目标**——否则它会挡住上路箱子的落点。

规则：箱子只能推不能拉，抵墙/抵箱即阻；两箱全部就位即胜。
解法路线由 agent 推演后写成行为探针，由引擎验证（约 25 步）。

本文件是**生命指引**——它不携带关卡数据。有什么东西、怎么解析、怎么渲染，
都在这里声明；具体数据由同目录的内容源提供。

## 指引

```mbg-guide
game "Box Push" mode: grid

# 有哪些东西、怎么解析：关卡几何来自 level.json（ASCII 地图在 rows_map 里）
source levels
  path "level.json"
  parser json_level

# 行为探针来自 probes.json
source probes
  path "probes.json"
  parser json_probes

# 渲染配置：角色程序化生成，种子取自 level.json 的 player.seed
render
  hero: procedural seed: player.seed
  layer grid   cell: from-level
  layer walls  bevel: 3
  layer boxes  on_goal: green
  layer hud    show: state moves boxes pos

# 组装：source 名隐式挂载到对应内核字段
assembly
  hud "state moves boxes pos"
```

## 操作

run 模式：方向键移动，R 重开，ESC 退出。

## 图例（level.json 的 rows_map 字符集）

`#` 墙  `p` 玩家  `b` 箱子  `g` 目标格  `.` 地板