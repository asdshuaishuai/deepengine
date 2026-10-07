# Sky Stairs —— deepEngine 第一个游戏

gravity_side 原型族的平台跳跃。三级台阶直上云端，拿到路上的金币，抵达绿色终点。
红色尖刺守着地板路线——想走捷径会死。

本文件是**生命指引**——它不携带关卡数据。有什么东西、怎么解析、怎么渲染，
都在这里声明；具体数据由同目录的内容源提供。

## 指引

```mbg-guide
game "Sky Stairs" mode: physics

# 有哪些东西、怎么解析
source levels
  path "level.json"
  parser json_level

source probes
  path "probes.json"
  parser json_probes

# 渲染配置
render
  hero: procedural seed: player.seed
  layer platforms  bevel: 28
  layer coins      spin: 0.18
  layer spikes     teeth: 3
  layer goal       flag: 26

# 组装
assembly
  hud "state coins frame x y"
```

## 操作

run 模式：←/→ 移动，空格跳，R 热重载，ESC 退出。