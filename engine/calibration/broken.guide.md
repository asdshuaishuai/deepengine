# 校准件 broken（指引路径）：源声明存在但文件缺失——必须拒绝（exit 1）
#
# 这条校准的是装配层的失败语义：指引说"这里有个 levels 源"，
# 但文件不在。必须报错退出，绝不能静默用空世界跑出 PASS。
# 若它返回 0，说明装配层把"缺失"当成了"没有内容"——验证器会说谎。

```mbg-guide
game "broken" mode: physics

source levels
  path "does_not_exist.json"
  parser json_level
```