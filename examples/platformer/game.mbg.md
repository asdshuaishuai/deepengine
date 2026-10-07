# Sky Stairs —— deepEngine 第一个游戏

> **本文件是 inline 入口的回归基线，不再是推荐用法。**
> 推荐入口是同目录的 `game.guide.md`（生命指引）+ `level.json` + `probes.json`。
>
> 保留本文件的价值：它是"旧单文件入口"的对照物。
> `engine/tests/regression.sh` 断言两条入口在同一个内核上产出**逐字节相同的
> 探针结果**——这是 v1.3 改造没有改变玩法语义的可机械核对证据。
> 若你想改这个游戏，请改 `level.json` / `probes.json`，不要改本文件。

gravity_side 原型族的平台跳跃。三级台阶直上云端，拿到路上的金币，抵达绿色终点。
红色尖刺守着地板路线——想走捷径会死。

操作（run 模式）：←/→ 移动，空格跳，R 热重载，ESC 退出。

```mbg
canvas 960 540 bg:#0b0d13

physics gravity:2000 jump:-700 speed:260

player x:80 y:460 seed:0

# 地板（含尖刺陷阱）
platform x:0 y:500 w:960 h:40
spike x:520 y:484 w:40

# 三级台阶（每级抬升 ~90px，跳高 122px 可达）
platform x:260 y:420 w:140 h:20 color:#2b3448
platform x:470 y:330 w:140 h:20 color:#2b3448
platform x:680 y:240 w:140 h:20 color:#2b3448

# 金币（每级台阶上方，落台即收）
coin x:290 y:382
coin x:500 y:292
coin x:710 y:202

# 终点在顶层台阶上
goal x:715 y:180 w:56 h:60

# ---- 行为探针（agent 可写、引擎可执行、binary 判定）----

# 走上第一级台阶并吃到金币
probe reach_step1 script:"right:16, jump:1, right:33, wait:5" expect:"coins>=1"

# 地板捷径被尖刺守死
probe spike_guards_floor script:"right:110" expect:"state==dead"

# 全程登顶：三级跳抵达终点
probe beat_the_game script:"right:16, jump:1, right:33, right:12, jump:1, right:31, right:14, jump:1, right:32, right:6" expect:"state==won"
```
