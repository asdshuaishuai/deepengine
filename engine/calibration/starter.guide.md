# 校准件 starter（指引路径）：目标悬空不可达，探针却声称获胜——必须拒绝（exit 2）
# 与 oracle 唯一差异：goal y=20（无平台可达，跳高 122px 不够）

```mbg-guide
game "starter" mode: physics

source levels
  path "level_starter.json"
  parser json_level

source probes
  path "probes.json"
  parser json_probes
```