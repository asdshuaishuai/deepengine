# RSI 候选 c2：退化（走道上铺满尖刺）

数据看起来只多了一个字段，但可达性被破坏：标准 0/3，终局 dead。必须被拒。

## 指引

```mbg-guide
game "RSI c2 worse" mode: physics

source levels
  path "level_worse.json"
  parser json_level

source policies
  path "policies.json"
  parser json_policies
```
