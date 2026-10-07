# Coin Rush —— gravity_side 原型族：漂浮跳横渡尖刺谷

与 platformer 同族同骨架，但物理手感完全不同：
低重力 + 慢速 = 漂浮跳。尖刺铺满谷底，三段浮台横渡，收齐两枚金币落进终点。

本文件是**生命指引**——它不携带关卡数据。有什么东西、怎么解析、怎么渲染，
都在这里声明；具体数据由同目录的内容源提供。

## 指引

```mbg-guide
game "Coin Rush" mode: physics

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

run 模式：方向键移动，空格跳跃，R 重开，ESC 退出。