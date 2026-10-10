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

source policies
  path "policies.json"
  parser json_policies

source criteria
  path "criteria.json"
  parser json_criteria

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

## 体验度量实测（v1.4，说明这个游戏有多"紧"）

```
apphead.exe trace examples/coinrush/game.guide.md

expert_route  won     进展=100% 覆盖=17% 停滞= 0 直达=64%   ← 唯一通关路径
explore_a     dead    进展=  0% 覆盖= 9% 停滞=36 直达=12%
explore_b     playing 进展=  0% 覆盖=11% 停滞=40 直达= 3%
explore_c     dead    进展=  0% 覆盖= 7% 停滞=30 直达=29%
聚合: 终局 won · 进展 100% · 覆盖 25%(并集 34/135) · 停滞 40 · stuck 3/4
```

**这是一条真实的难度结论，不是配置噪声**：三条探索策略全部死亡或零进展
（`floor_is_lava` 探针早已证实 `right:120` 必死），说明本关**只认精确路线**——
低重力漂浮跳的窗口很窄。`not_all_stuck <= 75` 恰好卡在"4 条里只剩 1 条动得起来"，
是**刻意留的绊线**：以后再加一条探索策略若也走不动，这条标准会翻红并如实指出容错在变差。
想让它更宽容，改这一个数字即可——质量门是文本，不是引擎代码。