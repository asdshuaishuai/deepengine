// 体验裁决面白盒测试（blueprint §3.9）：轨迹确定性 / 度量语义 / 聚合上下限 / 裁决次序。
//
// 纪律：本文件的每个断言都必须是**机械可核对**的——没有"看起来更好"。

// ---------------- 测试世界构造（零 IO，内核自足）----------------

///|
/// 平地 + 终点（终点坐在地面上，直走可达）
fn mk_floor_goal(goal_x : Double) -> Game {
  let solids : Array[Solid] = []
  solids.push({ rect: { x: 0.0, y: 500.0, w: 960.0, h: 40.0 }, color: (35, 42, 61) })
  Game::new(
    960, 540, (11, 13, 19), 2000.0, -700.0, 260.0,
    { x: 80.0, y: 460.0, w: 28.0, h: 40.0 }, (74, 158, 255), 0,
    solids, [], [], Some({ x: goal_x, y: 440.0, w: 60.0, h: 60.0 }),
  )
}

///|
/// 平地 + 一枚金币（金币落在玩家身体高度上）+ 远处终点
fn mk_floor_coin(coin_x : Double) -> Game {
  let solids : Array[Solid] = []
  solids.push({ rect: { x: 0.0, y: 500.0, w: 960.0, h: 40.0 }, color: (35, 42, 61) })
  let coins : Array[Coin] = []
  coins.push({
    id: 0,
    rect: { x: coin_x, y: 470.0, w: 20.0, h: 20.0 },
    color: (245, 165, 36),
    taken: false,
  })
  Game::new(
    960, 540, (11, 13, 19), 2000.0, -700.0, 260.0,
    { x: 80.0, y: 460.0, w: 28.0, h: 40.0 }, (74, 158, 255), 0,
    solids, coins, [], Some({ x: 900.0, y: 440.0, w: 60.0, h: 60.0 }),
  )
}

///|
/// 平地 + 一堵墙（右行会撞墙并卡住）
fn mk_floor_wall(wall_x : Double) -> Game {
  let solids : Array[Solid] = []
  solids.push({ rect: { x: 0.0, y: 500.0, w: 960.0, h: 40.0 }, color: (35, 42, 61) })
  solids.push({ rect: { x: wall_x, y: 300.0, w: 30.0, h: 200.0 }, color: (35, 42, 61) })
  Game::new(
    960, 540, (11, 13, 19), 2000.0, -700.0, 260.0,
    { x: 80.0, y: 460.0, w: 28.0, h: 40.0 }, (74, 158, 255), 0,
    solids, [], [], None,
  )
}

///|
/// 平地 + 一片尖刺（右行必死）
fn mk_floor_spike(spike_x : Double) -> Game {
  let solids : Array[Solid] = []
  solids.push({ rect: { x: 0.0, y: 500.0, w: 960.0, h: 40.0 }, color: (35, 42, 61) })
  let spikes : Array[Rect] = []
  spikes.push({ x: spike_x, y: 484.0, w: 200.0, h: 16.0 })
  Game::new(
    960, 540, (11, 13, 19), 2000.0, -700.0, 260.0,
    { x: 80.0, y: 460.0, w: 28.0, h: 40.0 }, (74, 158, 255), 0,
    solids, [], spikes, Some({ x: 900.0, y: 440.0, w: 60.0, h: 60.0 }),
  )
}

///|
/// 空旷平地，玩家在正中（用于"两条策略覆盖并集"）
fn mk_open_field() -> Game {
  let solids : Array[Solid] = []
  solids.push({ rect: { x: 0.0, y: 500.0, w: 960.0, h: 40.0 }, color: (35, 42, 61) })
  Game::new(
    960, 540, (11, 13, 19), 2000.0, -700.0, 260.0,
    { x: 460.0, y: 460.0, w: 28.0, h: 40.0 }, (74, 158, 255), 0,
    solids, [], [], None,
  )
}

///|
/// 一格推箱：玩家(1,1) 箱(2,1) 目标(3,1)
fn mk_grid_puzzle() -> GridGame {
  let walls : Array[(Int, Int)] = []
  let boxes : Array[(Int, Int)] = []
  boxes.push((2, 1))
  let goals : Array[(Int, Int)] = []
  goals.push((3, 1))
  GridGame::new(5, 3, 0, 1, 1, walls, boxes, goals)
}

///|
/// 跑一条脚本策略（physics）
fn trace_script(g : Game, script : String, targets : Int, arena : Int) -> Trace {
  run_policy(g, Script("t", script), targets, arena)
}

// ---------------- 轨迹：采样、早停、确定性 ----------------

///|
test "trace：逐帧采样，首帧为 f0" {
  let t = trace_script(mk_floor_goal(900.0), "right:30", 0, 135)
  assert_true(t.samples.length() == 31)
  assert_true(t.samples[0].frame == 0)
  assert_true(t.samples[30].frame == 30)
}

///|
test "trace：到达终态即早停（不把终态后的空转帧算进度）" {
  let t = trace_script(mk_floor_goal(300.0), "right:400", 0, 135)
  assert_true(t.final_state == "won")
  // 300px 处 → 260px/s 约 55 帧，远小于 400
  assert_true(t.samples.length() < 200)
  assert_true(t.samples.length() > 1)
}

///|
test "trace：同策略同世界双跑逐帧一致" {
  let g = mk_floor_coin(200.0)
  let a = trace_script(g, "right:60, jump:4, right:20", 1, 135)
  let b = trace_script(g, "right:60, jump:4, right:20", 1, 135)
  assert_true(trace_serialize(a) == trace_serialize(b))
  assert_true(trace_digest(a) == trace_digest(b))
}

///|
test "trace：探索策略同 seed 必同轨迹，异 seed 必不同轨迹" {
  let g = mk_open_field()
  let a1 = run_policy(g, Explore("a", 7, 300), 0, 135)
  let a2 = run_policy(g, Explore("a", 7, 300), 0, 135)
  let b = run_policy(g, Explore("b", 21, 300), 0, 135)
  assert_true(trace_serialize(a1) == trace_serialize(a2))
  assert_true(trace_serialize(a1) != trace_serialize(b))
}

///|
test "trace：轨迹确认玩家真的动了（不是只长了帧数）" {
  let t = trace_script(mk_open_field(), "right:30", 0, 135)
  assert_true(t.end_x > t.start_x)
  assert_true(t.path_len > 0)
}

// ---------------- 不扰动传入的世界 ----------------
//
// 这条不是洁癖：web demo 的「体验度量」按钮在**对局进行中**按下，
// 若 run_policy 就地改了传入的世界，测量完玩家的进度就被重置了。

///|
test "trace：跑策略不扰动传入的世界（physics）" {
  let g = mk_floor_goal(900.0)
  let x0 = g.player.x
  let f0 = g.frame
  let s0 = g.state
  let c0 = g.coins_taken
  let _ = trace_script(g, "right:200", 0, 135)
  let _ = run_policy(g, Explore("e", 7, 240), 0, 135)
  assert_true(g.player.x == x0)
  assert_true(g.frame == f0)
  assert_true(g.state == s0)
  assert_true(g.coins_taken == c0)
}

///|
test "trace(grid)：跑策略不扰动传入的推箱世界" {
  let g = mk_grid_puzzle()
  let px0 = g.px
  let py0 = g.py
  let m0 = g.moves
  let s0 = g.state
  let _ = run_policy_grid(g, Script("t", "right:2"), 1, 15)
  let _ = run_policy_grid(g, Explore("e", 7, 120), 1, 15)
  assert_true(g.px == px0)
  assert_true(g.py == py0)
  assert_true(g.moves == m0)
  assert_true(g.state == s0)
}

// ---------------- 度量语义 ----------------

///|
test "metrics：无目标的通关游戏进展为 100" {
  let t = trace_script(mk_floor_goal(300.0), "right:200", 0, 135)
  let m = metrics_of(t)
  assert_true(m.outcome == "won")
  assert_true(m.outcome_rank == 2)
  assert_true(m.progress_pct == 100)
}

///|
test "metrics：拿到全部金币进展为 100，未拿到为 0" {
  let g = mk_floor_coin(200.0)
  let hit = metrics_of(trace_script(g, "right:60", 1, 135))
  let miss = metrics_of(trace_script(g, "left:60", 1, 135))
  assert_true(hit.progress_pct == 100)
  assert_true(miss.progress_pct == 0)
}

///|
test "metrics：覆盖度在分母内且直走覆盖很小" {
  let m = metrics_of(trace_script(mk_open_field(), "right:30", 0, 135))
  assert_true(m.coverage_pct >= 0)
  assert_true(m.coverage_pct <= 100)
  assert_true(m.coverage_pct < 20)
}

///|
test "metrics：撞墙会累积停滞，且达标直走几乎不停滞" {
  let jam = metrics_of(trace_script(mk_floor_wall(300.0), "right:100", 0, 135))
  let ok = metrics_of(trace_script(mk_floor_goal(900.0), "right:100", 0, 135))
  assert_true(jam.stall_max >= 30)
  assert_true(ok.stall_max <= 1)
}

///|
test "metrics：往返乱走直达率低，直奔终点直达率高" {
  let wander = metrics_of(trace_script(mk_open_field(), "right:20, left:20, right:20, left:20", 0, 135))
  let direct = metrics_of(trace_script(mk_floor_goal(900.0), "right:100", 0, 135))
  assert_true(wander.directness_pct <= 20)
  assert_true(direct.directness_pct >= 80)
}

///|
test "metrics：跳过动作被计数，静止不动闲置占比高" {
  let jumpy = metrics_of(trace_script(mk_open_field(), "jump:2, right:10, jump:2", 0, 135))
  let still = metrics_of(trace_script(mk_open_field(), "wait:30", 0, 135))
  assert_true(jumpy.jumps >= 2)
  assert_true(still.idle_ratio_pct == 100)
}

///|
test "metrics：撞尖刺终局为 dead（序 0）" {
  let m = metrics_of(trace_script(mk_floor_spike(300.0), "right:200", 0, 135))
  assert_true(m.outcome == "dead")
  assert_true(m.outcome_rank == 0)
}

// ---------------- 策略集聚合：并集与上下限 ----------------

///|
test "experience：多策略覆盖并集严格大于任一单策略" {
  let g = mk_open_field()
  let left = run_policy(g, Script("l", "left:120"), 0, 135)
  let right = run_policy(g, Script("r", "right:120"), 0, 135)
  let solo_l = experience_of([("l", left)])
  let solo_r = experience_of([("r", right)])
  let both = experience_of([("l", left), ("r", right)])
  // 并集：分头走的两个策略合起来覆盖更多
  assert_true(both.cells_union > solo_l.cells_union)
  assert_true(both.cells_union > solo_r.cells_union)
  assert_true(both.metrics.coverage_pct > solo_l.metrics.coverage_pct)
}

///|
test "experience：能力取上限，风险取下限（两条策略一好一卡）" {
  let good = run_policy(mk_floor_goal(300.0), Script("good", "right:200"), 0, 135)
  let bad = run_policy(mk_floor_wall(300.0), Script("bad", "right:200"), 0, 135)
  let e = experience_of([("good", good), ("bad", bad)])
  assert_true(e.metrics.outcome == "won") // 上限：有人通关
  assert_true(e.metrics.stall_max >= 30) // 下限：有人卡死
  assert_true(e.stuck_policies == 1)
  assert_true(e.stuck_ratio_pct == 50)
}

///|
test "experience：空策略集不崩（不崩谓词）" {
  let e = experience_of([])
  assert_true(e.n_policies == 0)
  assert_true(e.stuck_ratio_pct == 0)
  assert_true(e.metrics.frames == 0)
}

///|
test "experience：没有可收集目标时以通关计进展" {
  let g = mk_floor_goal(300.0)
  let e = experience_of([("won", run_policy(g, Script("s", "right:200"), 0, 135))])
  assert_true(e.metrics.progress_pct == 100)
}

// ---------------- 标准求值 ----------------

///|
test "criteria：标准按度量求值，逐条给 detail" {
  let e = experience_of([(
    "won",
    run_policy(mk_floor_goal(300.0), Script("s", "right:200"), 0, 135),
  )])
  let cs : Array[Criterion] = [
    { name: "solvable", metric: "progress", op: ">=", value: 100 },
    { name: "impossible", metric: "progress", op: ">=", value: 101 },
    { name: "not_dead", metric: "outcome_rank", op: "!=", value: 0 },
  ]
  let rs = eval_criteria(e, cs)
  assert_true(rs.length() == 3)
  assert_true(rs[0].pass)
  assert_true(!rs[1].pass)
  assert_true(rs[2].pass)
  assert_true(count_passed(rs) == 2)
}

///|
test "criteria：未知度量判失败（宁可假阴不假阳）" {
  let e = experience_of([(
    "won",
    run_policy(mk_floor_goal(300.0), Script("s", "right:200"), 0, 135),
  )])
  let cs : Array[Criterion] = [
    { name: "typo", metric: "progrss", op: ">=", value: 0 },
  ]
  let rs = eval_criteria(e, cs)
  assert_true(!rs[0].pass)
}

///|
test "criteria：非法运算符判失败" {
  let e = experience_of([(
    "won",
    run_policy(mk_floor_goal(300.0), Script("s", "right:200"), 0, 135),
  )])
  let cs : Array[Criterion] = [
    { name: "weird", metric: "progress", op: "~=", value: 100 },
  ]
  assert_true(!eval_criteria(e, cs)[0].pass)
}

// ---------------- 版本裁决 ----------------

///|
/// 构造"通关版"与"无目标版"两种体验
fn exp_won() -> Experience {
  experience_of([(
    "s",
    run_policy(mk_floor_goal(300.0), Script("s", "right:200"), 0, 135),
  )])
}

///|
fn exp_dead() -> Experience {
  experience_of([(
    "s",
    run_policy(mk_floor_spike(300.0), Script("s", "right:200"), 0, 135),
  )])
}

///|
test "adjudicate：终局是硬门——覆盖度高但打不通的版本被拒" {
  let a = exp_won()
  let b = exp_dead()
  let d = adjudicate(a, b, [], [])
  assert_true(verdict_name(d.verdict) == "keep_a")
  assert_true(d.deciding == "outcome")
}

///|
test "adjudicate：终局硬门是可逆的（对称性）" {
  let d1 = adjudicate(exp_won(), exp_dead(), [], [])
  let d2 = adjudicate(exp_dead(), exp_won(), [], [])
  assert_true(verdict_name(d1.verdict) == "keep_a")
  assert_true(verdict_name(d2.verdict) == "accept_b")
}

///|
test "adjudicate：标准通过数优先于偏好序" {
  let a = exp_dead()
  let b = exp_won()
  let cs : Array[Criterion] = [
    { name: "solvable", metric: "progress", op: ">=", value: 100 },
  ]
  let d = adjudicate(a, b, cs, [])
  assert_true(verdict_name(d.verdict) == "accept_b")
  assert_true(d.deciding == "criteria")
  assert_true(d.a_passed == 0)
  assert_true(d.b_passed == 1)
}

///|
test "adjudicate：终局相同则按偏好序，首个差异即决定" {
  // 两版都通关（终局相同、进展同为 100），但 B 先绕后到、走过更多格 →
  // 偏好序里 progress 相同，由 coverage 决定
  let a = experience_of([(
    "s",
    run_policy(mk_floor_goal(300.0), Script("s", "right:200"), 0, 135),
  )])
  let b = experience_of([(
    "s",
    run_policy(mk_floor_goal(300.0), Script("s", "left:60, right:200"), 0, 135),
  )])
  assert_true(b.metrics.coverage_pct > a.metrics.coverage_pct)
  let d = adjudicate(a, b, [], ["progress", "coverage"])
  assert_true(verdict_name(d.verdict) == "accept_b")
  assert_true(d.deciding == "coverage")
}

///|
test "adjudicate：完全相同 → inconclusive（不接受'改动即进步'）" {
  let d = adjudicate(exp_won(), exp_won(), [], [])
  assert_true(verdict_name(d.verdict) == "inconclusive")
  assert_true(d.deciding == "none")
}

///|
test "adjudicate：delta 全量报告（不只手报决定项）" {
  let d = adjudicate(exp_won(), exp_dead(), [], [])
  assert_true(d.deltas.length() > 3)
}

// ---------------- grid 族 ----------------

///|
test "trace(grid)：推箱通关，进展 100，早停" {
  let t = run_policy_grid(mk_grid_puzzle(), Script("s", "right:2"), 1, 15)
  let m = metrics_of(t)
  assert_true(m.outcome == "won")
  assert_true(m.progress_pct == 100)
  // f0 + 一步即推箱就位（第二步不该发生——早停的意义就在这）
  assert_true(t.samples.length() == 2)
  assert_true(t.samples[1].progress == 1)
}

///|
test "trace(grid)：探索策略同 seed 必同轨迹" {
  let g = mk_grid_puzzle()
  let a = run_policy_grid(g, Explore("a", 11, 200), 1, 15)
  let b = run_policy_grid(g, Explore("a", 11, 200), 1, 15)
  assert_true(trace_serialize(a) == trace_serialize(b))
}

///|
test "trace(grid)：覆盖度以自由格为分母" {
  let t = run_policy_grid(mk_grid_puzzle(), Script("s", "left:1, up:1, down:1"), 1, 15)
  let m = metrics_of(t)
  assert_true(m.coverage_pct > 0)
  assert_true(m.coverage_pct <= 100)
}

///|
test "trace(grid)：撞墙不动会累积停滞" {
  let t = run_policy_grid(mk_grid_puzzle(), Script("s", "left:5"), 1, 15)
  // 玩家在 (1,1)，连续左推只会撞边界（出界视为墙）
  assert_true(metrics_of(t).stall_max >= 3)
}
