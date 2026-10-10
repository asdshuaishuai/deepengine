# RSI 夹具：基线（冻结门的来源）

一次自改进 run 的**判据在基线里冻结**：后面所有候选都用这道门判，
候选自己声明的标准只作对照（改了尺子会被标成 gate_shopping）。

## 指引

```mbg-guide
game "RSI base" mode: physics

source levels
  path "level_base.json"
  parser json_level

source policies
  path "policies.json"
  parser json_policies

source criteria
  path "criteria.json"
  parser json_criteria
```
