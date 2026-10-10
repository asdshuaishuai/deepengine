# RSI 候选 c1：真改进（两块悬浮平台 → 探索策略能走到更多格子）

关卡数据只加了两个平台，玩法没变。标准通过数与终局都没变（3/3 vs 3/3、都 playing），
差异落在偏好序的 `coverage` 上——这正是"没有硬门变化时，改进由偏好序裁定"。

## 指引

```mbg-guide
game "RSI c1 better" mode: physics

source levels
  path "level_better.json"
  parser json_level

source policies
  path "policies.json"
  parser json_policies
```
