// guide 白盒测试：生命指引文件解析器
//
// 指引文件是「生命指引」——它只声明有哪些东西、怎么解析、怎么渲染组装。
// 它的解析质量直接决定装配层能否拿到正确输入，故这里覆盖：
// 块结构、缩进、引号剥离、mode 提取（易错点：标题里的冒号）、
// 缺声明的错误、以及不崩谓词（未知指令 → 警告而非中断）。

///|
fn join_lines(xs : Array[String]) -> String {
  let mut s = ""
  for x in xs {
    s = s + x + "\n"
  }
  s
}

///|
fn sample_guide() -> String {
  join_lines([
    "# 标题散文会被忽略",
    "",
    "game \"My Game\" mode: physics",
    "",
    "source levels",
    "  path \"level.json\"",
    "  parser json_level",
    "",
    "source probes",
    "  path \"probes.json\"",
    "  parser json_probes",
    "",
    "render",
    "  hero: procedural seed: player.seed",
    "  layer platforms bevel: 28",
    "  layer coins spin: 0.18",
    "",
    "assembly",
    "  hud \"state coins frame\"",
  ])
}

///|
test "guide：解析 source 声明（name/path/parser）" {
  let g = parse_guide(sample_guide())
  assert_true(g.errors.length() == 0)
  assert_true(g.title == "My Game")
  assert_true(g.sources.length() == 2)
  assert_true(g.sources[0].name == "levels")
  assert_true(g.sources[0].path == "level.json")
  assert_true(g.sources[0].parser == "json_level")
  assert_true(g.sources[1].name == "probes")
  assert_true(g.sources[1].path == "probes.json")
  assert_true(g.sources[1].parser == "json_probes")
}

///|
test "guide：mode 从 game 行提取（标题含冒号也不误切）" {
  let g = parse_guide(sample_guide())
  assert_true(g.mode == "physics")
}

///|
test "guide：mode 提取——标题含冒号边界" {
  // 回归防护：旧实现用整行 find(":")，标题内冒号会吃掉 mode
  let g = parse_guide(join_lines([
    "game \"A: B\" mode: grid",
  ]))
  assert_true(g.title == "A: B")
  assert_true(g.mode == "grid")
}

///|
test "guide：渲染层解析（layer 名与参数）" {
  let g = parse_guide(sample_guide())
  // hero 行带 rig/dust 时会额外产出 "hero" 层（参数必须挂到某层，
  // 否则写了不生效——静默失效比报错更坏）
  assert_true(g.render.length() >= 2)
  assert_true(g.render[0].name == "platforms")
  assert_true(g.render[1].name == "coins")
  // hero seed 路径
  assert_true(g.hero_seed_path == "player.seed")
}

///|
test "guide：hero 行的非 seed 参数挂到 hero 层（不静默丢弃）" {
  let g = parse_guide(join_lines([
    "game \"T\" mode: physics",
    "render",
    "  hero: procedural rig: off dust: off",
  ]))
  assert_true(g.render.length() == 1)
  assert_true(g.render[0].name == "hero")
  assert_true(g.render[0].params.length() == 2)
  assert_true(g.hero_seed_path == "")
}

///|
test "guide：hero 行只写 seed 时不产出空层" {
  let g = parse_guide(join_lines([
    "game \"T\" mode: physics",
    "render",
    "  hero: procedural seed: player.seed",
  ]))
  assert_true(g.hero_seed_path == "player.seed")
  assert_true(g.render.length() == 0) // 无额外参数 → 无空层
}

///|
test "guide：hud 解析" {
  let g = parse_guide(sample_guide())
  assert_true(g.hud == "state coins frame")
}

///|
test "guide：引号剥离（path/parser/标题）" {
  // 回归防护：旧实现用固定偏移切词，path 会残留引号
  let g = parse_guide(sample_guide())
  assert_true(g.sources[0].path == "level.json") // 非 "\"level.json\""
}

///|
test "guide：optional 标记" {
  let g = parse_guide(join_lines([
    "game \"T\" mode: physics",
    "source audio",
    "  path \"audio.json\"",
    "  parser json_level",
    "  optional",
  ]))
  assert_true(g.errors.length() == 0)
  assert_true(g.sources[0].optional)
}

///|
test "guide：source 缺 parser 报错" {
  let g = parse_guide(join_lines([
    "game \"T\" mode: physics",
    "source levels",
    "  path \"level.json\"",
  ]))
  assert_true(g.errors.length() > 0)
}

///|
test "guide：source 缺 path（非 optional）报错" {
  let g = parse_guide(join_lines([
    "game \"T\" mode: physics",
    "source levels",
    "  parser json_level",
  ]))
  assert_true(g.errors.length() > 0)
}

///|
test "guide：非法 mode 报错" {
  let g = parse_guide(join_lines([
    "game \"T\" mode: nonsense",
  ]))
  assert_true(g.errors.length() > 0)
}

///|
test "guide：game 缺标题报错" {
  let g = parse_guide(join_lines([
    "game mode: physics",
  ]))
  assert_true(g.errors.length() > 0)
}

///|
test "guide：未知指令 → 警告不中断（不崩谓词）" {
  let g = parse_guide(join_lines([
    "game \"T\" mode: physics",
    "frobnicate 1 2 3",
    "render",
    "  bogus_layer foo: bar",
    "source levels",
    "  path \"level.json\"",
    "  parser json_level",
    "  weird_directive",
  ]))
  // 未知指令不产生 error，只产生 warning
  assert_true(g.errors.length() == 0)
  assert_true(g.warnings.length() > 0)
}

///|
test "guide：注释剥离（# 之后为注释）" {
  let g = parse_guide(join_lines([
    "game \"T\" mode: physics # 这行尾部是注释",
    "source levels # 注释",
    "  path \"level.json\" # 注释",
    "  parser json_level",
  ]))
  assert_true(g.errors.length() == 0)
  assert_true(g.mode == "physics")
  assert_true(g.sources[0].path == "level.json")
}

///|
test "guide：散文行（非指令、非缩进）→ 警告不中断" {
  let g = parse_guide(join_lines([
    "game \"T\" mode: physics",
    "这是一段中文散文，引擎应忽略并记录警告。",
    "source levels",
    "  path \"level.json\"",
    "  parser json_level",
  ]))
  assert_true(g.errors.length() == 0)
}

///|
test "guide：空文件 → 无源警告、不崩" {
  let g = parse_guide("")
  assert_true(g.errors.length() == 0)
  assert_true(g.sources.length() == 0)
  assert_true(g.warnings.length() > 0)
}

///|
test "guide：多个 source 累积（不崩）" {
  let g = parse_guide(join_lines([
    "game \"T\" mode: physics",
    "source a",
    "  path \"a.json\"",
    "  parser json_level",
    "source b",
    "  path \"b.json\"",
    "  parser json_probes",
    "source c",
    "  path \"c.json\"",
    "  parser json_level",
  ]))
  assert_true(g.errors.length() == 0)
  assert_true(g.sources.length() == 3)
  assert_true(g.sources[0].name == "a")
  assert_true(g.sources[1].name == "b")
  assert_true(g.sources[2].name == "c")
}