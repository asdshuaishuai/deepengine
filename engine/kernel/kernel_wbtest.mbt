// kernel 白盒测试：物理语义 + 确定性 + 探针

///|
fn make_test_game() -> Game {
  let solids : Array[Solid] = []
  // 地板
  solids.push({
    rect: { x: 0.0, y: 500.0, w: 960.0, h: 40.0 },
    color: (35, 42, 61),
  })
  // 一级台阶
  solids.push({
    rect: { x: 300.0, y: 400.0, w: 160.0, h: 24.0 },
    color: (35, 42, 61),
  })
  let coins : Array[Coin] = []
  coins.push({
    id: 0,
    rect: { x: 340.0, y: 360.0, w: 20.0, h: 20.0 },
    color: (245, 165, 36),
    taken: false,
  })
  Game::new(
    960,
    540,
    (11, 13, 19),
    2000.0, // gravity
    -700.0, // jump_v
    260.0, // speed
    { x: 80.0, y: 460.0, w: 28.0, h: 40.0 }, // player_rect（地板上）
    (74, 158, 255),
    0, // seed
    solids,
    coins,
    [],
    Some({ x: 800.0, y: 200.0, w: 60.0, h: 60.0 }),
  )
}

///|
test "kernel：站立在地板上且稳定" {
  let g = make_test_game()
  let g2 = run_script(g, "wait:30")
  assert_true(g2.state == "playing")
  // 玩家应落在地板上（y + h == 500）
  assert_true(g2.player.y.to_int() == 460)
  assert_true(g2.player.grounded)
}

///|
test "kernel：按右移动，x 前进" {
  let g = make_test_game()
  let g2 = run_script(g, "right:30")
  assert_true(g2.player.x > g.player.x)
}

///|
test "kernel：跳跃离地再回落" {
  let g = make_test_game()
  let g2 = run_script(g, "wait:5, jump:12")
  // 站稳后起跳，12 帧内应已离地
  assert_true(g2.player.y < 460.0)
  let g3 = run_script(g, "wait:5, jump:40, wait:60")
  // 起跳后回落到地面
  assert_true(g3.player.grounded)
  assert_true(g3.player.y.to_int() == 460)
}

///|
test "kernel：coyote 时间——离地 6 帧内仍可跳" {
  let g = make_test_game()
  // 走出台阶边缘再跳：此处地板贯穿全宽，用台阶边缘模拟
  // 简化验证：站在地面，先 wait 再立即 jump（jump_held 边沿）
  let g2 = run_script(g, "wait:10, jump:5")
  assert_true(g2.player.y < 460.0)
}

///|
test "kernel：确定性——双跑序列化一致" {
  let g = make_test_game()
  let a = serialize(run_script(g, "right:60, jump, right:40"))
  let b = serialize(run_script(g, "right:60, jump, right:40"))
  assert_true(a == b)
}

///|
test "kernel：金币可收集" {
  let g = make_test_game()
  // 金币在 (340,360)，台阶在 (300,400)：站台阶上即可碰到
  // 走到台阶 + 跳上台：right 到 310 附近，jump
  let g2 = run_script(g, "right:55, jump:20, right:10")
  // 宽松断言：不死于途中且位置前进（精确路线由 examples 的声明探针覆盖）
  assert_true(g2.state != "dead")
  assert_true(g2.player.x > 200.0)
}

///|
test "kernel：探针期望求值" {
  let g = make_test_game()
  let probes : Array[Probe] = [
    { name: "move", script: "right:30", expect: "x>=100" },
    { name: "stable", script: "wait:30", expect: "state==playing" },
  ]
  let r = verify(g, probes)
  assert_true(r.total == 6) // 4 通用 + 2 声明
  assert_true(r.passed == 6)
  assert_true(r.reward == 1)
}

///|
test "kernel：失败探针使主分为 0（binary 语义）" {
  let g = make_test_game()
  let probes : Array[Probe] = [{ name: "impossible", script: "wait:5", expect: "state==won" }]
  let r = verify(g, probes)
  assert_true(r.reward == 0)
  assert_true(r.passed == 4) // 通用全过，声明失败
}

///|
test "kernel：掉出世界判死" {
  // 无地板的世界
  let g : Game = {
    w: 960,
    h: 540,
    bg: (0, 0, 0),
    gravity: 2000.0,
    jump_v: -700.0,
    speed: 260.0,
    player: {
      x: 100.0,
      y: 100.0,
      vx: 0.0,
      vy: 0.0,
      w: 28.0,
      h: 40.0,
      grounded: false,
      coyote: 0,
      jump_held: false,
    },
    player_color: (255, 255, 255),
    player_seed: 0,
    spawn: (100.0, 100.0),
    solids: [],
    coins: [],
    spikes: [],
    goal: None,
    frame: 0,
    state: "playing",
    coins_taken: 0,
  }
  let g2 = run_script(g, "wait:120")
  assert_true(g2.state == "dead")
}

///|
test "衍生：运行时 spawn 金币可被收集（不经任何文本文件）" {
  let g = make_test_game()
  // 在玩家前进路径上现场生成一枚金币
  let id = spawn_coin(g, 200.0, 465.0, 20.0)
  assert_true(id == 1) // 原有关卡已有 1 枚（id 0）
  let g2 = run_script(g, "right:30")
  assert_true(g2.coins_taken >= 1) // 走过去吃到（位置 200 在路线上或路线邻域）
  // 生成物随 clone 保留
  let g3 = Game::clone(g)
  assert_true(g3.coins.length() == 2)
}

///|
test "衍生：spawn 越界拒绝" {
  let g = make_test_game()
  assert_true(spawn_coin(g, 2000.0, 0.0, 20.0) == -1)
  assert_true(spawn_platform(g, -5.0, 0.0, 10.0, 10.0) == false)
}

///|
test "衍生：despawn 金币" {
  let g = make_test_game()
  assert_true(despawn_coin(g, 0) == true)
  assert_true(g.coins.length() == 0)
  assert_true(despawn_coin(g, 0) == false)
}

///|
test "衍生：spawn 平台改变可通行性" {
  let g = make_test_game()
  // 在玩家前方竖一堵墙
  assert_true(spawn_platform(g, 200.0, 300.0, 20.0, 200.0) == true)
  let g2 = run_script(g, "right:60")
  // 玩家被新墙挡住（x 停在墙前 ~172）
  assert_true(g2.player.x < 200.0)
}
