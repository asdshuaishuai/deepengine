// 体验裁决面白盒测试（scene 侧）：policies.json / criteria.json 解码与 P0 门禁。
//
// 这层的门禁比度量本身更重要：**标准写错名字却"通过了"比标准失败危险得多**——
// 那是假证据。所以未知度量 / 未知 kind / 非法运算符一律 ERROR。

///|
fn policies_json_ok() -> String {
  "{\"policies\":[{\"name\":\"expert\",\"kind\":\"script\",\"script\":\"right:30\"},{\"name\":\"explore_a\",\"kind\":\"explore\",\"seed\":9,\"frames\":120}]}"
}

///|
fn criteria_json_ok() -> String {
  "{\"criteria\":[{\"name\":\"solvable\",\"metric\":\"progress\",\"op\":\">=\",\"value\":100}],\"prefer\":[\"progress\",\"coverage\"]}"
}

///|
/// 指引：levels + policies + criteria（physics）
fn guide_with_quality() -> GuideSpec {
  parse_guide(gl([
    "game \"Q\" mode: physics",
    "source levels",
    "  path \"level.json\"",
    "  parser json_level",
    "source policies",
    "  path \"policies.json\"",
    "  parser json_policies",
    "source criteria",
    "  path \"criteria.json\"",
    "  parser json_criteria",
  ]))
}

// ---------------- policies.json ----------------

///|
test "quality：policies.json 解码（script + explore 两类）" {
  let (ps, es, _) = decode_policies(policies_json_ok())
  assert_true(es.length() == 0)
  assert_true(ps.length() == 2)
  assert_true(@kernel.policy_name(ps[0]) == "expert")
  assert_true(@kernel.policy_spec(ps[0]) == "script:expert[right:30]")
  assert_true(@kernel.policy_name(ps[1]) == "explore_a")
  assert_true(@kernel.policy_spec(ps[1]) == "explore:explore_a[seed=9,frames=120]")
}

///|
test "quality：未注册的 kind 报错且不静默跳过" {
  let (ps, es, _) = decode_policies(
    "{\"policies\":[{\"name\":\"x\",\"kind\":\"telepathy\"}]}",
  )
  assert_true(es.length() == 1)
  assert_true(ps.length() == 0)
}

///|
test "quality：kind=script 缺 script 报错" {
  let (ps, es, _) = decode_policies("{\"policies\":[{\"name\":\"x\",\"kind\":\"script\"}]}")
  assert_true(es.length() == 1)
  assert_true(ps.length() == 0)
}

///|
test "quality：frames 非正报错（拒绝无界/空策略）" {
  let (ps, es, _) = decode_policies(
    "{\"policies\":[{\"name\":\"x\",\"kind\":\"explore\",\"frames\":0}]}",
  )
  assert_true(es.length() == 1)
  assert_true(ps.length() == 0)
}

///|
test "quality：缺 policies 数组报错" {
  let (ps, es, _) = decode_policies("{}")
  assert_true(es.length() == 1)
  assert_true(ps.length() == 0)
}

// ---------------- criteria.json ----------------

///|
test "quality：criteria.json 解码（标准 + 显式偏好序）" {
  let (cs, pf, es, _) = decode_criteria(criteria_json_ok())
  assert_true(es.length() == 0)
  assert_true(cs.length() == 1)
  assert_true(cs[0].metric == "progress")
  assert_true(cs[0].op == ">=")
  assert_true(cs[0].value == 100)
  assert_true(pf.length() == 2)
  assert_true(pf[0] == "progress")
}

///|
test "quality：未知度量名报错（写错名字的通关是假证据）" {
  let (cs, _, es, _) = decode_criteria(
    "{\"criteria\":[{\"name\":\"typo\",\"metric\":\"progres\",\"op\":\">=\",\"value\":100}]}",
  )
  assert_true(es.length() == 1)
  assert_true(cs.length() == 0)
}

///|
test "quality：非法运算符报错" {
  let (cs, _, es, _) = decode_criteria(
    "{\"criteria\":[{\"name\":\"x\",\"metric\":\"progress\",\"op\":\"~=\",\"value\":1}]}",
  )
  assert_true(es.length() == 1)
  assert_true(cs.length() == 0)
}

///|
test "quality：prefer 里的未知度量报错" {
  let (_, pf, es, _) = decode_criteria(
    "{\"criteria\":[],\"prefer\":[\"progress\",\"vibes\"]}",
  )
  assert_true(es.length() == 1)
  // 合法的那个仍然保留（部分可用胜过全丢）
  assert_true(pf.length() == 1)
}

// ---------------- 装配集成 ----------------

///|
test "quality：指引声明 policies/criteria 源 → 进 GameSpec 且 loaded 如实报告" {
  let asm = assemble(guide_with_quality(), mem_reader([
    ("level.json", physics_level_json()),
    ("policies.json", policies_json_ok()),
    ("criteria.json", criteria_json_ok()),
  ]))
  assert_true(asm.errors.length() == 0)
  match asm.spec {
    Some(spec) => {
      assert_true(spec.policies.length() == 2)
      assert_true(spec.criteria.length() == 1)
      assert_true(spec.prefer.length() == 2)
    }
    None => assert_true(false)
  }
  assert_true(asm.loaded.length() == 3)
}

///|
test "quality：策略源缺失必须报错（不能静默变成空策略集）" {
  let asm = assemble(guide_with_quality(), mem_reader([
    ("level.json", physics_level_json()),
    ("criteria.json", criteria_json_ok()),
  ]))
  assert_true(asm.errors.length() > 0)
  assert_true(asm.spec is None)
}

///|
test "quality：新 parser 已注册，未知 parser 仍拒绝" {
  assert_true(known_parser("json_policies"))
  assert_true(known_parser("json_criteria"))
  assert_true(!known_parser("json_vibes"))
  let (_, es, _) = run_parser("json_vibes", Some("{}"), "physics")
  assert_true(es.length() == 1)
}

// ---------------- 世界信息（体验度量的分母）----------------

///|
test "quality：world_info physics——目标数=金币数，覆盖分母=画布分块数" {
  let asm = assemble(
    parse_guide(gl([
      "game \"P\" mode: physics",
      "source levels",
      "  path \"level.json\"",
      "  parser json_level",
    ])),
    mem_reader([("level.json", physics_level_json())]),
  )
  match asm.spec {
    Some(spec) => {
      let wi = spec.world_info()
      assert_true(wi.targets == 1)
      // 480x320 → ceil(480/64)=8, 320/64=5 → 40 块
      assert_true(wi.arena_cells == 40)
    }
    None => assert_true(false)
  }
}

///|
test "quality：world_info grid——目标数=箱子数，覆盖分母=自由格数" {
  let asm = assemble(
    parse_guide(gl([
      "game \"G\" mode: grid",
      "source levels",
      "  path \"level.json\"",
      "  parser json_level",
    ])),
    mem_reader([("level.json", grid_level_json())]),
  )
  match asm.spec {
    Some(spec) => {
      let wi = spec.world_info()
      assert_true(wi.targets == 0)
      // 4x4=16 格，12 面墙 → 4 自由格
      assert_true(wi.arena_cells == 4)
    }
    None => assert_true(false)
  }
}
