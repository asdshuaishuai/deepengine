// rendercfg 白盒测试：渲染配置契约
//
// 这一层回答的是"指引说了到底算不算数"。三类测试：
//   ① 声明 → 值：指引的 render 参数真的落到 RenderConfig
//   ② 门禁：值域非法要报错，未知 key 要警告（不是静默失效）
//   ③ 缺省：没声明就用历史视觉（老项目换新入口画面不变）

///|
fn layers_of(lines : Array[String]) -> Array[@scene.RenderLayer] {
  @scene.parse_guide(gl_join(lines)).render
}

///|
fn gl_join(xs : Array[String]) -> String {
  let mut s = ""
  for x in xs {
    s = s + x + "\n"
  }
  s
}

///|
/// 造一份配置：与 CLI 实际调用同路径（hero_seed_path 从指引解析后传入，
/// 而不是写死——写死会让 seed 相关的测试测到另一条分支）。
fn cfg_of(lines : Array[String], world_seed : Int) -> RenderConfig {
  let g = @scene.parse_guide(gl_join(lines))
  from_guide(g.render, "procedural", g.hero_seed_path, world_seed)
}

// ---------------- 声明 → 值 ----------------

///|
test "rendercfg：默认配置即历史视觉" {
  let c = default_config()
  assert_true(c.platform_bevel == 28) // 亮度增量
  assert_true(c.platform_edge == 3.0) // 高度
  assert_true(c.coin_spin == 0.18)
  assert_true(c.spike_teeth == 3)
  assert_true(c.goal_flag == 26.0)
  assert_true(c.grid_grip == 3)
  assert_true(c.dust)
  assert_true(c.hero_rig)
  assert_true(c.errors.length() == 0)
}

///|
test "rendercfg：指引参数落到配置（bevel/edge/spin/teeth/flag/grip）" {
  let c = cfg_of([
    "game \"T\" mode: physics",
    "render",
    "  layer platforms  bevel: 60 edge: 8",
    "  layer coins      spin: 0.5",
    "  layer spikes     teeth: 7",
    "  layer goal       flag: 44",
    "  layer grid       grip: 5",
  ], 0)
  assert_true(c.platform_bevel == 60)
  assert_true(c.platform_edge == 8.0)
  assert_true(c.coin_spin == 0.5)
  assert_true(c.spike_teeth == 7)
  assert_true(c.goal_flag == 44.0)
  assert_true(c.grid_grip == 5)
  assert_true(c.errors.length() == 0)
}

///|
test "rendercfg：hero 层参数（rig/dust）被消费" {
  // 回归防护：曾出现"指引写了 rig: off 但静默不生效"——
  // hero 行只读 seed，其余参数被丢弃。
  let c = cfg_of([
    "game \"T\" mode: physics",
    "render",
    "  hero: procedural rig: off dust: off",
  ], 0)
  assert_true(!c.hero_rig)
  assert_true(!c.dust)
}

///|
test "rendercfg：rig/dust 单独开关" {
  let rig_off = cfg_of([
    "game \"T\" mode: physics",
    "render",
    "  hero: procedural rig: off",
  ], 0)
  assert_true(!rig_off.hero_rig)
  assert_true(rig_off.dust) // 未声明 → 默认开

  let dust_off = cfg_of([
    "game \"T\" mode: physics",
    "render",
    "  hero: procedural dust: off",
  ], 0)
  assert_true(dust_off.dust == false)
  assert_true(dust_off.hero_rig)
}

///|
test "rendercfg：seed 路径声明时取世界的 player_seed" {
  let c = cfg_of([
    "game \"T\" mode: physics",
    "render",
    "  hero: procedural seed: player.seed",
  ], 42)
  assert_true(c.hero_seed == 42) // 值来自关卡数据，不是字面量
}

///|
test "rendercfg：未声明 seed 时 hero_seed 保持 -1（沿用世界）" {
  let c = cfg_of([
    "game \"T\" mode: physics",
    "render",
    "  layer platforms bevel: 10",
  ], 7)
  assert_true(c.hero_seed == -1)
}

///|
test "rendercfg：bool 参数接受 on/off/1/0，未知词落回默认" {
  let off = cfg_of([
    "game \"T\" mode: physics",
    "render",
    "  hero: procedural rig: 0 dust: off",
  ], 0)
  assert_true(!off.hero_rig)
  assert_true(!off.dust)

  let on = cfg_of([
    "game \"T\" mode: physics",
    "render",
    "  hero: procedural rig: on dust: true",
  ], 0)
  assert_true(on.hero_rig)
  assert_true(on.dust)

  // 未知词不是"假"，是"没写"——落回默认而不是猜
  let junk = cfg_of([
    "game \"T\" mode: physics",
    "render",
    "  hero: procedural rig: maybe",
  ], 0)
  assert_true(junk.hero_rig) // 默认开
}

// ---------------- 门禁 ----------------

///|
test "rendercfg：负值报错（画错就必须拦）" {
  let c = cfg_of([
    "game \"T\" mode: physics",
    "render",
    "  layer platforms bevel: -5",
  ], 0)
  assert_true(c.errors.length() > 0)
}

///|
test "rendercfg：负 spin 报错并钳零" {
  let c = cfg_of([
    "game \"T\" mode: physics",
    "render",
    "  layer coins spin: -1",
  ], 0)
  assert_true(c.errors.length() > 0)
  assert_true(c.coin_spin == 0.0)
}

///|
test "rendercfg：teeth < 1 被钳到 1 并警告（不崩）" {
  let c = cfg_of([
    "game \"T\" mode: physics",
    "render",
    "  layer spikes teeth: 0",
  ], 0)
  assert_true(c.spike_teeth == 1)
  assert_true(c.warnings.length() > 0)
  assert_true(c.errors.length() == 0)
}

///|
test "rendercfg：未知参数 → 警告不报错（不是静默失效）" {
  let c = cfg_of([
    "game \"T\" mode: physics",
    "render",
    "  layer platforms bogus_param: 12",
  ], 0)
  assert_true(c.errors.length() == 0)
  assert_true(c.warnings.length() > 0)
}

///|
test "rendercfg：未实现的 hero mode → 警告" {
  let c = from_guide([], "sprite", "", 0)
  assert_true(c.warnings.length() > 0)
  assert_true(c.errors.length() == 0)
}

///|
test "rendercfg：非数值参数落回默认（不崩）" {
  let c = cfg_of([
    "game \"T\" mode: physics",
    "render",
    "  layer platforms bevel: abc",
  ], 0)
  assert_true(c.platform_bevel == 28) // 回退默认
  assert_true(c.errors.length() == 0)
}

// ---------------- HUD 契约 ----------------

///|
test "rendercfg：HUD 字段切分（physics）" {
  let h = hud_from("state coins frame x y", false)
  assert_true(h.fields.length() == 5)
  assert_true(h.warnings.length() == 0)
}

///|
test "rendercfg：HUD 字段按族过滤（grid 独有 moves/boxes）" {
  let grid = hud_from("state moves boxes_on pos", true)
  assert_true(grid.fields.length() == 4)
  assert_true(grid.warnings.length() == 0)

  // physics 族没有 moves —— 应警告而不是画个空字段
  let phys = hud_from("state moves", false)
  assert_true(phys.fields.length() == 1) // 只有 state
  assert_true(phys.warnings.length() > 0)
}

///|
test "rendercfg：HUD 未知字段 → 警告" {
  let h = hud_from("state bogus", false)
  assert_true(h.fields.length() == 1)
  assert_true(h.warnings.length() > 0)
}

///|
test "rendercfg：HUD 文本（physics）按声明字段渲染" {
  let g = @kernel.Game::new(
    960, 540, (0, 0, 0), 2000.0, -700.0, 260.0,
    { x: 80.0, y: 460.0, w: 28.0, h: 40.0 },
    (74, 158, 255), 0,
    [], [], [], None,
  )
  let t = hud_text_physics(["state", "x", "y"], g)
  assert_true(t == "state:playing  x:80  y:460")
}

///|
test "rendercfg：HUD 文本（grid）按声明字段渲染" {
  let walls : Array[(Int, Int)] = []
  let boxes : Array[(Int, Int)] = []
  let goals : Array[(Int, Int)] = []
  let g = @kernel.GridGame::new(4, 4, 0, 1, 1, walls, boxes, goals)
  let t = hud_text_grid(["state", "moves", "pos"], g)
  assert_true(t == "state:playing  moves:0  pos:(1,1)")
}

///|
test "rendercfg：空 HUD 声明 → 空文本（不是默认字段）" {
  // 显式声明空 = 用户要清空 HUD；未声明才走 default_hud
  let h = hud_from("", false)
  assert_true(h.fields.length() == 0)
  assert_true(hud_text_physics(h.fields, { w: 1, h: 1, bg: (0,0,0), gravity: 0.0, jump_v: 0.0, speed: 0.0, player: { x: 0.0, y: 0.0, vx: 0.0, vy: 0.0, w: 1.0, h: 1.0, grounded: false, coyote: 0, jump_held: false }, player_color: (0,0,0), player_seed: 0, spawn: (0.0, 0.0), solids: [], coins: [], spikes: [], goal: None, frame: 0, state: "playing", coins_taken: 0 }) == "")
}