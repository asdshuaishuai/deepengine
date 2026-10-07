// scene 白盒测试：解析 → 构建 → 内核步进 全链

///|
fn sample_source() -> String {
  let lines = [
    "# Mini platformer",
    "",
    "Prose here is ignored - only ops inside the mbg fence run.",
    "",
    "```mbg",
    "canvas 960 540 bg:#0b0d13",
    "physics gravity:2000 jump:-700 speed:260",
    "",
    "player x:80 y:460 color:#4a9eff",
    "",
    "platform x:0 y:500 w:960 h:40",
    "platform x:300 y:400 w:160 h:24",
    "",
    "coin x:340 y:368",
    "spike x:520 y:484 w:40",
    "",
    "goal x:800 y:140 w:60 h:60",
    "",
    "probe reach_goal script:\"right:60, jump, right:200\" expect:\"x>=600\"",
    "```",
    "",
  ]
  let mut s = ""
  for l in lines {
    s = s + l + "\n"
  }
  s
}

///|
test "scene：解析主链（canvas/physics/player/platform/coin/spike/goal/probe）" {
  let r = parse(sample_source())
  assert_true(r.errors.length() == 0)
  match r.spec {
    Some(spec) => {
      assert_true(spec.w == 960)
      assert_true(spec.h == 540)
      assert_true(spec.bg == (11, 13, 19))
      assert_true(spec.gravity == 2000.0)
      assert_true(spec.jump_v == -700.0)
      assert_true(spec.player.x == 80.0)
      assert_true(spec.player.y == 460.0)
      assert_true(spec.solids.length() == 2)
      assert_true(spec.coins.length() == 1)
      assert_true(spec.spikes.length() == 1)
      match spec.goal {
        Some(g) => assert_true(g.x == 800.0)
        None => fail("goal 未解析")
      }
      assert_true(spec.probes.length() == 1)
      assert_true(spec.probes[0].name == "reach_goal")
      assert_true(spec.probes[0].expect == "x>=600")
    }
    None => fail("解析失败")
  }
}

///|
test "scene：fence 外的 ops 不执行（文档性优先）" {
  let src = "canvas 640 480\n\n```mbg\ncanvas 960 540\nplatform x:0 y:500 w:960 h:40\n```\n"
  let r = parse(src)
  match r.spec {
    Some(spec) => {
      assert_true(spec.w == 960) // fence 内生效
      assert_true(spec.solids.length() == 1)
    }
    None => fail("应解析成功")
  }
}

///|
test "scene：坏输入收集错误而非崩溃（不崩谓词 P0）" {
  let src = "```mbg\ncanvas abc def\nplatform x:no y:2 w:3 h:4\nplayer x:1\n```\n"
  let r = parse(src)
  assert_true(r.errors.length() >= 3) // canvas + platform + player + 无平台
  match r.spec {
    Some(_) => fail("有错时应返回 None")
    None => ()
  }
}

///|
test "scene：颜色解析（含大写十六进制）" {
  let src = "```mbg\ncanvas 960 540 bg:#0B0D13\nplatform x:0 y:500 w:960 h:40 color:#FF3366\n```\n"
  let r = parse(src)
  match r.spec {
    Some(spec) => {
      assert_true(spec.bg == (11, 13, 19))
      assert_true(spec.solids[0].color == (255, 51, 102))
    }
    None => fail("应解析成功")
  }
}

///|
test "scene：spec → kernel 构建并可步进（全链）" {
  let r = parse(sample_source())
  match r.spec {
    Some(spec) => {
      let g = spec.build()
      assert_true(g.w == 960)
      let g2 = @kernel.run_script(g, "right:30")
      assert_true(g2.player.x > g.player.x)
      // 通用探针应全过（关卡设计合法）
      let rep = @kernel.verify(g, spec.probes)
      let mut u_all = true
      for res in rep.results {
        if res.name.length() > 2 && res.name.substring(start=0, end=2) == "u_" && !res.pass {
          u_all = false
        }
      }
      assert_true(u_all)
    }
    None => fail("解析失败")
  }
}

///|
test "scene：确定性——同一源文本两次构建两次跑，序列化一致" {
  let r1 = parse(sample_source())
  let r2 = parse(sample_source())
  match (r1.spec, r2.spec) {
    (Some(s1), Some(s2)) => {
      let a = @kernel.serialize(@kernel.run_script(s1.build(), "right:60, jump, right:30"))
      let b = @kernel.serialize(@kernel.run_script(s2.build(), "right:60, jump, right:30"))
      assert_true(a == b)
    }
    _ => fail("解析失败")
  }
}
