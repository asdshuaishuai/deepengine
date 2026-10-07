# 校准件 oracle：真实可通关的小关——验证器必须接受（exit 0）

```mbg
canvas 480 320
physics gravity:2000 jump:-700 speed:260
player x:40 y:240
platform x:0 y:280 w:480 h:40
goal x:380 y:220 w:50 h:60
probe win script:"right:90" expect:"state==won"
```
