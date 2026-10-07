# 校准件 starter：目标悬空不可达，探针却声称获胜——验证器必须拒绝（exit 2）
# 与 oracle 唯一差异：goal y:20（无平台可达，跳高 122px 不够）

```mbg
canvas 480 320
physics gravity:2000 jump:-700 speed:260
player x:40 y:240
platform x:0 y:280 w:480 h:40
goal x:380 y:20 w:50 h:40
probe win script:"right:90" expect:"state==won"
```
