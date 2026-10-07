// assemble 白盒测试：指引 + 内容源 → GameSpec
//
// 这层是 v1.3 的中枢：指引只说"有什么、怎么解析"，数据由源提供。
// 覆盖重点：
//   ① level.json 解码（physics / grid 两族）
//   ② probes.json 解码
//   ③ 多源叠加（多个 json_level 合并到同一世界）
//   ④ 失败语义（缺源必须报错，绝不静默用空世界通过——否则验证器会说谎）

///|
fn gl(lines : Array[String]) -> String {
  let mut s = ""
  for l in lines {
    s = s + l + "\n"
  }
  s
}

///|
/// 内存 reader：map 由调用方给（模拟文件系统，不碰真 IO）
fn mem_reader(files : Array[(String, String)]) -> (String) -> String? {
  let f = fn(rel : String) -> String? {
    for pair in files {
      if pair.0 == rel {
        return Some(pair.1)
      }
    }
    None
  }
  f
}

///|
fn physics_level_json() -> String {
  "{\"canvas\":{\"w\":480,\"h\":320,\"bg\":\"#101010\"},\"physics\":{\"gravity\":2000,\"jump\":-700,\"speed\":260},\"player\":{\"x\":40,\"y\":240,\"seed\":5},\"platforms\":[{\"x\":0,\"y\":280,\"w\":480,\"h\":40},{\"x\":200,\"y\":200,\"w\":100,\"h\":20,\"color\":\"#2b3448\"}],\"coins\":[{\"x\":220,\"y\":170}],\"spikes\":[{\"x\":300,\"y\":264,\"w\":40}],\"goal\":{\"x\":380,\"y\":220,\"w\":50,\"h\":60}}"
}

///|
fn grid_level_json() -> String {
  "{\"level\":{\"cols\":4,\"rows\":4,\"cell\":40,\"rows_map\":[\"####\",\"#p.#\",\"#..#\",\"####\"]}}"
}

///|
fn probes_json() -> String {
  "{\"probes\":[{\"name\":\"a\",\"script\":\"right:30\",\"expect\":\"state==won\"},{\"name\":\"b\",\"script\":\"wait:5\",\"expect\":\"state==playing\"}]}"
}

///|
fn guide_with(level_path : String, parser : String, with_probes : Bool) -> GuideSpec {
  let lines = [
    "game \"T\" mode: physics",
    "source levels",
    "  path \"" + level_path + "\"",
    "  parser " + parser,
  ]
  if with_probes {
    lines.push("source probes")
    lines.push("  path \"probes.json\"")
    lines.push("  parser json_probes")
  }
  parse_guide(gl(lines))
}

// ---------------- level.json 解码 ----------------

///|
test "assemble：level.json physics 解码（画布/物理/玩家/实体）" {
  let g = parse_guide(gl([
    "game \"P\" mode: physics",
    "source levels",
    "  path \"level.json\"",
    "  parser json_level",
  ]))
  let asm = assemble(g, mem_reader([("level.json", physics_level_json())]))
  assert_true(asm.errors.length() == 0)
  match asm.spec {
    Some(spec) => {
      assert_true(spec.w == 480)
      assert_true(spec.h == 320)
      assert_true(spec.gravity == 2000.0)
      assert_true(spec.jump_v == -700.0)
      assert_true(spec.player.x == 40.0)
      assert_true(spec.player_seed == 5)
      assert_true(spec.solids.length() == 2)
      assert_true(spec.coins.length() == 1)
      assert_true(spec.spikes.length() == 1)
      assert_true(spec.goal is Some(_))
    }
    None => assert_true(false)
  }
}

///|
test "assemble：level.json grid 解码（ASCII 地图 → 墙/箱/目标/出生点）" {
  let g = parse_guide(gl([
    "game \"G\" mode: grid",
    "source levels",
    "  path \"level.json\"",
    "  parser json_level",
  ]))
  let asm = assemble(g, mem_reader([("level.json", grid_level_json())]))
  assert_true(asm.errors.length() == 0)
  match asm.spec {
    Some(spec) => {
      assert_true(spec.g_cols == 4)
      assert_true(spec.g_rows == 4)
      assert_true(spec.g_cell == 40)
      assert_true(spec.g_px == 1)
      assert_true(spec.g_py == 1)
      // 16 格中首尾行 8 格 + 左右边墙 4 格 = 12 墙
      assert_true(spec.g_walls.length() == 12)
    }
    None => assert_true(false)
  }
}

///|
test "assemble：probes.json 解码" {
  let g = guide_with("level.json", "json_level", true)
  let asm = assemble(g, mem_reader([("level.json", physics_level_json()), ("probes.json", probes_json())]))
  assert_true(asm.errors.length() == 0)
  match asm.spec {
    Some(spec) => {
      assert_true(spec.probes.length() == 2)
      assert_true(spec.probes[0].name == "a")
      assert_true(spec.probes[0].script == "right:30")
      assert_true(spec.probes[1].expect == "state==playing")
    }
    None => assert_true(false)
  }
}

///|
test "assemble：省略即继承（level.json 只写部分字段，其余用默认值）" {
  let minimal = "{\"platforms\":[{\"x\":0,\"y\":280,\"w\":480,\"h\":40}]}"
  let g = parse_guide(gl([
    "game \"M\" mode: physics",
    "source levels",
    "  path \"level.json\"",
    "  parser json_level",
  ]))
  let asm = assemble(g, mem_reader([("level.json", minimal)]))
  assert_true(asm.errors.length() == 0)
  match asm.spec {
    Some(spec) => {
      assert_true(spec.gravity == default_spec().gravity) // 未声明 → 继承默认
      assert_true(spec.speed == default_spec().speed)
      assert_true(spec.solids.length() == 1)
    }
    None => assert_true(false)
  }
}

// ---------------- 多源叠加 ----------------

///|
test "assemble：多个 json_level 源叠加到同一世界（组合式内容源）" {
  let extra = "{\"coins\":[{\"x\":100,\"y\":100},{\"x\":150,\"y\":150}],\"platforms\":[{\"x\":0,\"y\":290,\"w\":50,\"h\":10}]}"
  let g = parse_guide(gl([
    "game \"M\" mode: physics",
    "source base",
    "  path \"base.json\"",
    "  parser json_level",
    "source extra",
    "  path \"extra.json\"",
    "  parser json_level",
  ]))
  let asm = assemble(g, mem_reader([("base.json", physics_level_json()), ("extra.json", extra)]))
  assert_true(asm.errors.length() == 0)
  match asm.spec {
    Some(spec) => {
      // 金币：1（base）+ 2（extra）= 3
      assert_true(spec.coins.length() == 3)
      // 平台：2（base）+ 1（extra）= 3
      assert_true(spec.solids.length() == 3)
      // 基线字段保留
      assert_true(spec.w == 480)
    }
    None => assert_true(false)
  }
}

///|
test "assemble：empty 源不贡献内容（无 platform 的空世界按门禁拒）" {
  // empty 源的语义是"此源不提供数据"，不是"此源豁免门禁"——
  // 若它产出的世界没有任何平台，physics 门禁照样拒。两者不矛盾。
  let g = parse_guide(gl([
    "game \"E\" mode: physics",
    "source nothing",
    "  path \"level.json\"",
    "  parser empty",
  ]))
  let asm = assemble(g, mem_reader([("level.json", physics_level_json())]))
  // 源被正常处理（计入 loaded），但世界无平台 → 门禁拦下
  assert_true(asm.loaded.length() == 1)
  assert_true(asm.errors.length() > 0)
  assert_true(asm.spec is None)
}

///|
test "assemble：empty 源与实体源并存时不影响装配" {
  let g = parse_guide(gl([
    "game \"E2\" mode: physics",
    "source levels",
    "  path \"level.json\"",
    "  parser json_level",
    "source nothing",
    "  path \"nothing.json\"",
    "  parser empty",
  ]))
  let asm = assemble(g, mem_reader([("level.json", physics_level_json()), ("nothing.json", "{}")]))
  assert_true(asm.errors.length() == 0)
  assert_true(asm.loaded.length() == 2)
  assert_true(asm.spec is Some(_))
}

///|
test "assemble：runtime 源占位 + 警告（内容由 spawn API 生成）" {
  let g = parse_guide(gl([
    "game \"R\" mode: physics",
    "source base",
    "  path \"level.json\"",
    "  parser json_level",
    "source live",
    "  path \"spawn.json\"",
    "  parser runtime",
  ]))
  let asm = assemble(g, mem_reader([("level.json", physics_level_json()), ("spawn.json", "{}")]))
  assert_true(asm.errors.length() == 0)
  assert_true(asm.warnings.length() > 0) // runtime 源应给警告
  assert_true(asm.loaded.length() == 2)
}

// ---------------- 失败语义（验证器不说谎的关键） ----------------

///|
test "assemble：缺源报错——绝不静默用空世界通过" {
  let g = parse_guide(gl([
    "game \"B\" mode: physics",
    "source levels",
    "  path \"missing.json\"",
    "  parser json_level",
  ]))
  let asm = assemble(g, mem_reader([]))
  // 关键：必须 errors 非空且 spec 为 None
  assert_true(asm.errors.length() > 0)
  assert_true(asm.spec is None)
}

///|
test "assemble：optional 源缺失 → 跳过不报错" {
  let g = parse_guide(gl([
    "game \"O\" mode: physics",
    "source base",
    "  path \"level.json\"",
    "  parser json_level",
    "source maybe",
    "  path \"nope.json\"",
    "  parser json_level",
    "  optional",
  ]))
  let asm = assemble(g, mem_reader([("level.json", physics_level_json())]))
  assert_true(asm.errors.length() == 0)
  assert_true(asm.skipped.length() == 1)
  assert_true(asm.spec is Some(_))
}

///|
test "assemble：非法 JSON 报错" {
  let g = parse_guide(gl([
    "game \"J\" mode: physics",
    "source levels",
    "  path \"level.json\"",
    "  parser json_level",
  ]))
  let asm = assemble(g, mem_reader([("level.json", "{ this is not json")]))
  assert_true(asm.errors.length() > 0)
  assert_true(asm.spec is None)
}

///|
test "assemble：未注册 parser 报错（不静默忽略）" {
  let g = parse_guide(gl([
    "game \"U\" mode: physics",
    "source levels",
    "  path \"level.json\"",
    "  parser totally_unknown",
  ]))
  let asm = assemble(g, mem_reader([("level.json", "{}")]))
  assert_true(asm.errors.length() > 0)
}

///|
test "assemble：grid 模式缺地图报错" {
  let no_map = "{\"canvas\":{\"w\":400,\"h\":400}}"
  let g = parse_guide(gl([
    "game \"NM\" mode: grid",
    "source levels",
    "  path \"level.json\"",
    "  parser json_level",
  ]))
  let asm = assemble(g, mem_reader([("level.json", no_map)]))
  assert_true(asm.errors.length() > 0)
}

///|
test "assemble：physics 模式无 platform 报错" {
  let g = parse_guide(gl([
    "game \"NP\" mode: physics",
    "source levels",
    "  path \"level.json\"",
    "  parser json_level",
  ]))
  let asm = assemble(g, mem_reader([("level.json", "{\"canvas\":{\"w\":100,\"h\":100}}")]))
  assert_true(asm.errors.length() > 0)
}

// ---------------- 门禁与自审 ----------------

///|
test "assemble：known_parser 自省表" {
  assert_true(known_parser("json_level"))
  assert_true(known_parser("json_probes"))
  assert_true(known_parser("inline"))
  assert_true(known_parser("empty"))
  assert_true(known_parser("runtime"))
  assert_true(!known_parser("nope"))
}

///|
test "assemble：标题与 mode 来自指引（指引是生命指引，它说了算）" {
  let g = parse_guide(gl([
    "game \"From Guide\" mode: grid",
    "source levels",
    "  path \"level.json\"",
    "  parser json_level",
  ]))
  let asm = assemble(g, mem_reader([("level.json", grid_level_json())]))
  match asm.spec {
    Some(spec) => {
      assert_true(spec.title == "From Guide")
      assert_true(spec.mode == "grid")
    }
    None => assert_true(false)
  }
}

///|
test "assemble：loaded 记录实际载入的源（自审计：哪些被证明了）" {
  let g = guide_with("level.json", "json_level", true)
  let asm = assemble(g, mem_reader([("level.json", physics_level_json()), ("probes.json", probes_json())]))
  assert_true(asm.loaded.length() == 2)
  assert_true(asm.loaded[0] == "levels(json_level)")
  assert_true(asm.loaded[1] == "probes(json_probes)")
}

///|
test "assemble：装配结果可直接构建内核世界（端到端连通）" {
  let g = guide_with("level.json", "json_level", true)
  let asm = assemble(g, mem_reader([("level.json", physics_level_json()), ("probes.json", probes_json())]))
  match asm.spec {
    Some(spec) => {
      let game = spec.build()
      assert_true(game.solids.length() == 2)
      // 探针在装配出的世界上真的能跑
      let report = @kernel.verify(game, spec.probes)
      assert_true(report.total == 6) // 4 通用 + 2 声明
    }
    None => assert_true(false)
  }
}