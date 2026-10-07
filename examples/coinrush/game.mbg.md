# Coin Rush —— agent 驱动创作的第二个游戏

> **本文件是 inline 入口的回归基线，不再是推荐用法。**
> 推荐入口是同目录的 `game.guide.md` + `level.json` + `probes.json`。
> 保留本文件供 `engine/tests/regression.sh` 做双入口等价比对。

与 Sky Stairs 相同的引擎与原型族（gravity_side），但物理手感完全不同：
低重力 + 慢速 = 漂浮跳。尖刺铺满谷底，三段浮台横渡，收齐两枚金币落进终点。

本文件由 AI agent 仅通过 .mbg.md 事实源创作——引擎代码零改动。

```mbg
canvas 960 540 bg:#0d1021

physics gravity:1400 jump:-620 speed:240

player x:60 y:460 seed:7

# 左岸
platform x:0 y:500 w:300 h:40 color:#2b3448

# 谷底尖刺（300-720，坠落即死）
spike x:300 y:484 w:420

# 三段浮台
platform x:380 y:430 w:110 h:20 color:#2b3448
platform x:560 y:350 w:110 h:20 color:#2b3448

# 对岸（含终点）
platform x:740 y:430 w:200 h:20 color:#2b3448
goal x:800 y:370 w:56 h:60

# 金币：第一段浮台上方 + 第二段浮台上方
coin x:410 y:392
coin x:590 y:312

# ---- 行为探针 ----

# 第一跳：横渡到浮台一，顺路收金币
probe hop_p1 script:"right:44, jump:1, right:44, wait:3" expect:"coins>=1"

# 贪心走谷底：坠落尖刺
probe floor_is_lava script:"right:120" expect:"state==dead"

# 全程：三跳过谷，落进对岸终点
probe cross_the_gap script:"right:44, jump:1, right:44, right:9, jump:1, right:44, right:17, jump:1, right:57, wait:3" expect:"state==won"
```
