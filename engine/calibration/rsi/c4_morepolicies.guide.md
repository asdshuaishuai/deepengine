# RSI 候选 c4：**关卡一个像素都没改**，只是多带 4 条探索策略

这是比"改判据"更隐蔽的一种作弊：覆盖率是"所有策略走到的格子并集"，
多声明几条探索策略就能让覆盖率天然上涨——外观还像"测得更全、更严谨"。

引擎的应对：**判定一律用基线冻结的策略集**（同一套探针测两版）。
c4 的世界与 base 完全相同，冻结探针下两者度量逐字段相等 →
裁决 inconclusive、不接受；同时 `policy_drift` 如实标记
（它独立跑 `trace` 时的数字会和台账不同，不报的话 agent 会以为引擎算错了）。

## 指引

```mbg-guide
game "RSI c4 more policies" mode: physics

source levels
  path "level_base.json"
  parser json_level

source policies
  path "policies_more.json"
  parser json_policies

source criteria
  path "criteria.json"
  parser json_criteria
```
