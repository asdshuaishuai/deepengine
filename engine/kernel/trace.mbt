// trace —— 程序化玩家与轨迹（blueprint §3.9「体验裁决面」）。
//
// 参考落点：Recursive Game Creator（arXiv 2610.08621）的 **coding-native Player**
// ——"creates and executes reusable policies through programmatic interfaces to
// efficiently collect diverse gameplay trajectories, mitigating evaluation bias
// caused by slow GUI-based collection"；RSIGame 的**递归自改进**（接受更好的版本）。
//
// 引擎侧的翻译：玩家不是人、也不是一条手写路径，而是**可复用的确定性策略**；
// 策略跑出的**轨迹**是体验度量的唯一事实输入——不是声明，不是截图，不是 VLM。
//
// 纪律：
//   1. 零渲染依赖、零 IO（blueprint L2 Mechanic 契约）——轨迹与度量可 moon test 直接驱动；
//   2. 逐帧采样**整型化**（跨架构逐字节确定，blueprint §12 风险表：浮点跨架构不确定）；
//   3. 到达终态即**早停**——否则终态后的空转帧会污染停滞/闲置度量；
//   4. 策略是数据（枚举），不是代码分支——同 seed 必同轨迹（有测试）。

///|
/// 轨迹采样点（整型化）
pub(all) struct Sample {
  frame : Int
  x : Int
  y : Int
  state : String
  progress : Int // 已完成的目标数（physics: coins_taken / grid: boxes_on）
  action : String // 该帧语义动作标签："R"/"L"/"J"/"-"（grid: 方向名）
}

///|
/// 一条轨迹（一个策略在一个世界上跑一遍的全部可观察物）
pub(all) struct Trace {
  mode : String
  targets : Int // 目标总数（进展分母）
  arena_cells : Int // 覆盖度分母（physics=画布分块数 / grid=自由格数）
  samples : Array[Sample]
  cells : Array[(Int, Int)] // 访问过的格（首次访问序，去重）
  revisits : Int // 重复踏入已访问格的次数
  idle_frames : Int // 无输入帧数
  jumps : Int // 起跳沿次数
  action_switches : Int // 动作切换次数
  actions : Array[String] // 出现过的动作标签（首次出现序）
  stall_max : Int // 最长连续"位置不变且仍在游玩"帧数
  stalled_frames : Int
  path_len : Int // 路径长度（曼哈顿，整型像素）
  start_x : Int
  start_y : Int
  end_x : Int
  end_y : Int
  final_state : String
  truncated : Bool // 是否因帧数上限被截断（诚实报告边界）
}

///|
/// 策略的帧数上限（防 agent 声明 10^9 帧把 CI 拖死；截断会如实报告）
pub const MAX_POLICY_FRAMES : Int = 3600

///|
/// 程序化玩家策略。两种形态都是**可复用**的：手写路线（可解释）
/// 与种子化探索（覆盖优先，替代"人/手写唯一路径"的评估偏差）。
pub(all) enum Policy {
  Script(String, String) // (name, script)
  Explore(String, Int, Int) // (name, seed, frames)
}

///|
/// 构造：脚本策略（跨包构造走函数，避免依赖枚举构造子的跨包写法）
pub fn policy_script(name : String, script : String) -> Policy {
  Script(name, script)
}

///|
/// 构造：种子化探索策略
pub fn policy_explore(name : String, seed : Int, frames : Int) -> Policy {
  Explore(name, seed, frames)
}

///|
pub fn policy_name(p : Policy) -> String {
  match p {
    Script(n, _) => n
    Explore(n, _, _) => n
  }
}

///|
/// 策略声明的规范性描述（写进报告，agent 可核对"用什么策略测的"）
pub fn policy_spec(p : Policy) -> String {
  match p {
    Script(n, s) => "script:\{n}[\{s}]"
    Explore(n, seed, frames) => "explore:\{n}[seed=\{seed},frames=\{frames}]"
  }
}

// ---------------- 轨迹装配（逐帧累积，避免第二遍扫描）----------------

///|
/// 确定性伪随机：16 位 LCG（Zx81 式）。
///
/// 为什么不用 32 位 LCG：wasm-gc 的 Int 是 32 位、native 是 64 位，
/// 乘积溢出行为不同 → 同一 seed 在两个消费面上跑出不同轨迹。
/// 本式取值域 < 2^23，两个目标都安全（blueprint §12 跨架构确定）。
fn lcg_next(state : Int) -> Int {
  (state * 75 + 74) % 65537
}

///|
priv struct TraceBuilder {
  mode : String
  block : Int
  targets : Int
  arena_cells : Int
  samples : Array[Sample]
  cells : Array[(Int, Int)]
  mut revisits : Int
  mut idle_frames : Int
  mut jumps : Int
  mut switches : Int
  actions : Array[String]
  mut stall_max : Int
  mut stalled_frames : Int
  mut cur_stall : Int
  mut path_len : Int
  mut prev_x : Int
  mut prev_y : Int
  mut prev_action : String
  mut seeded : Bool
  mut start_x : Int
  mut start_y : Int
  mut end_x : Int
  mut end_y : Int
  mut final_state : String
}

///|
fn TraceBuilder::new(
  mode : String,
  block : Int,
  targets : Int,
  arena_cells : Int
) -> TraceBuilder {
  {
    mode: mode,
    block: block,
    targets: targets,
    arena_cells: arena_cells,
    samples: [],
    cells: [],
    revisits: 0,
    idle_frames: 0,
    jumps: 0,
    switches: 0,
    actions: [],
    stall_max: 0,
    stalled_frames: 0,
    cur_stall: 0,
    path_len: 0,
    prev_x: 0,
    prev_y: 0,
    prev_action: "",
    seeded: false,
    start_x: 0,
    start_y: 0,
    end_x: 0,
    end_y: 0,
    final_state: "playing",
  }
}

///|
/// 格坐标（负值夹到 0——物理族 y 可能短暂为负）
fn cell_of(v : Int, block : Int) -> Int {
  if v < 0 {
    0
  } else if block <= 1 {
    v
  } else {
    v / block
  }
}

///|
fn in_cells(list : Array[(Int, Int)], x : Int, y : Int) -> Bool {
  for c in list {
    let (cx, cy) = c
    if cx == x && cy == y {
      return true
    }
  }
  false
}

///|
fn in_actions(list : Array[String], a : String) -> Bool {
  for x in list {
    if x == a {
      return true
    }
  }
  false
}

///|
/// 推入一个采样点，并顺带累积全部派生量（一次遍历，无第二遍）
fn TraceBuilder::push(
  self : TraceBuilder,
  frame : Int,
  x : Int,
  y : Int,
  state : String,
  progress : Int,
  action : String
) -> Unit {
  if !self.seeded {
    self.seeded = true
    self.start_x = x
    self.start_y = y
    self.prev_x = x
    self.prev_y = y
    self.prev_action = action
  } else {
    // 路径长度
    let dx = if x > self.prev_x {
      x - self.prev_x
    } else {
      self.prev_x - x
    }
    let dy = if y > self.prev_y {
      y - self.prev_y
    } else {
      self.prev_y - y
    }
    self.path_len = self.path_len + dx + dy
    // 停滞：位置不变且仍在游玩（终态之后不再算——早停已保证）
    if dx == 0 && dy == 0 {
      self.cur_stall = self.cur_stall + 1
      self.stalled_frames = self.stalled_frames + 1
      if self.cur_stall > self.stall_max {
        self.stall_max = self.cur_stall
      }
    } else {
      self.cur_stall = 0
    }
    // 动作切换 / 起跳沿
    if action != self.prev_action {
      self.switches = self.switches + 1
      if action == "J" {
        self.jumps = self.jumps + 1
      }
    }
    self.prev_x = x
    self.prev_y = y
    self.prev_action = action
  }
  if action == "-" {
    self.idle_frames = self.idle_frames + 1
  }
  if !in_actions(self.actions, action) {
    self.actions.push(action)
  }
  let cxx = cell_of(x, self.block)
  let cyy = cell_of(y, self.block)
  if in_cells(self.cells, cxx, cyy) {
    self.revisits = self.revisits + 1
  } else {
    self.cells.push((cxx, cyy))
  }
  self.samples.push({
    frame: frame,
    x: x,
    y: y,
    state: state,
    progress: progress,
    action: action,
  })
  self.end_x = x
  self.end_y = y
  self.final_state = state
}

///|
fn TraceBuilder::finish(self : TraceBuilder, truncated : Bool) -> Trace {
  // action_switches 只在第二个采样点起计数（首帧无"前一动作"），无需修正
  {
    mode: self.mode,
    targets: self.targets,
    arena_cells: self.arena_cells,
    samples: self.samples,
    cells: self.cells,
    revisits: self.revisits,
    idle_frames: self.idle_frames,
    jumps: self.jumps,
    action_switches: self.switches,
    actions: self.actions,
    stall_max: self.stall_max,
    stalled_frames: self.stalled_frames,
    path_len: self.path_len,
    start_x: self.start_x,
    start_y: self.start_y,
    end_x: self.end_x,
    end_y: self.end_y,
    final_state: self.final_state,
    truncated: truncated,
  }
}

// ---------------- 策略执行（两族各一个入口）----------------

///|
/// physics 族：在副本上按策略步进，逐帧采样；终态即早停。
pub fn run_policy(
  g0 : Game,
  p : Policy,
  targets : Int,
  arena_cells : Int
) -> Trace {
  let b = TraceBuilder::new("physics", 64, targets, arena_cells)
  let g = Game::clone(g0)
  b.push(0, g.player.x.to_int(), g.player.y.to_int(), g.state, g.coins_taken, "-")
  let mut truncated = false
  match p {
    Script(_, script) => {
      let mut stop = false
      for cmd in script_plan(script) {
        let (input, n) = cmd
        let label = input_label(input)
        let mut i = 0
        while i < n && !stop {
          step(g, input)
          b.push(g.frame, g.player.x.to_int(), g.player.y.to_int(), g.state, g.coins_taken, label)
          if g.state != "playing" {
            stop = true
          }
          i = i + 1
        }
        if stop {
          break
        }
      }
    }
    Explore(_, seed0, frames0) => {
      let mut r = seed0 % 65537
      if r <= 0 {
        r = 1
      }
      let cap = if frames0 > MAX_POLICY_FRAMES {
        MAX_POLICY_FRAMES
      } else {
        frames0
      }
      if frames0 > MAX_POLICY_FRAMES {
        truncated = true
      }
      let mut remaining = cap
      let mut span_left = 0
      let mut cur : Input = Input::none()
      let mut label = "-"
      while remaining > 0 && g.state == "playing" {
        if span_left == 0 {
          // 分束重采样：动作由 LCG 定，持续 4..24 帧。
          // 为什么不是逐帧纯噪声：噪声轨迹读不出可解释的行为，
          // 分束才能产生"往右走一段、跳一下"这类真实玩家形状的轨迹。
          let a = lcg_next(r) % 4
          span_left = 4 + lcg_next(r) % 21
          if a == 0 {
            cur = { left: true, right: false, jump: false }
            label = "L"
          } else if a == 1 {
            cur = { left: false, right: true, jump: false }
            label = "R"
          } else if a == 2 {
            cur = { left: false, right: false, jump: true }
            label = "J"
          } else {
            cur = Input::none()
            label = "-"
          }
          r = lcg_next(r)
        }
        step(g, cur)
        b.push(g.frame, g.player.x.to_int(), g.player.y.to_int(), g.state, g.coins_taken, label)
        span_left = span_left - 1
        remaining = remaining - 1
      }
    }
  }
  b.finish(truncated)
}

///|
/// grid 族：按回合步进（一次移动 = 一个采样点）。
pub fn run_policy_grid(
  g0 : GridGame,
  p : Policy,
  targets : Int,
  arena_cells : Int
) -> Trace {
  let b = TraceBuilder::new("grid", 1, targets, arena_cells)
  let g = GridGame::clone(g0)
  b.push(0, g.px, g.py, g.state, grid_boxes_on(g), "-")
  let mut truncated = false
  match p {
    Script(_, script) => {
      let mut stop = false
      for cmd in grid_plan(script) {
        let (dir, n) = cmd
        let mut i = 0
        while i < n && !stop {
          grid_step(g, dir)
          b.push(g.moves, g.px, g.py, g.state, grid_boxes_on(g), dir)
          if g.state != "playing" {
            stop = true
          }
          i = i + 1
        }
        if stop {
          break
        }
      }
    }
    Explore(_, seed0, frames0) => {
      let mut r = seed0 % 65537
      if r <= 0 {
        r = 1
      }
      let cap = if frames0 > MAX_POLICY_FRAMES {
        MAX_POLICY_FRAMES
      } else {
        frames0
      }
      if frames0 > MAX_POLICY_FRAMES {
        truncated = true
      }
      let mut remaining = cap
      let mut span_left = 0
      let mut dir = "right"
      while remaining > 0 && g.state == "playing" {
        if span_left == 0 {
          // grid 的合法动作是四方向；束长 1..3（推箱需要连续同向才有效果）
          let a = lcg_next(r) % 4
          span_left = 1 + lcg_next(r) % 3
          dir = if a == 0 {
            "left"
          } else if a == 1 {
            "right"
          } else if a == 2 {
            "up"
          } else {
            "down"
          }
          r = lcg_next(r)
        }
        grid_step(g, dir)
        b.push(g.moves, g.px, g.py, g.state, grid_boxes_on(g), dir)
        span_left = span_left - 1
        remaining = remaining - 1
      }
    }
  }
  b.finish(truncated)
}

///|
/// 轨迹摘要（确定性比较用）——同策略同世界必同串
pub fn trace_serialize(t : Trace) -> String {
  let mut max_prog = 0
  for s in t.samples {
    if s.progress > max_prog {
      max_prog = s.progress
    }
  }
  let mut s = "n\{t.samples.length()}|\{t.final_state}|cells\{t.cells.length()}"
  s = s + "|prog\{max_prog}|end\{t.end_x},\{t.end_y}"
  s = s + "|stall\{t.stall_max}|\{t.stalled_frames}|path\{t.path_len}"
  s = s + "|sw\{t.action_switches}|j\{t.jumps}|rev\{t.revisits}"
  s
}

///|
/// 轨迹的逐帧指纹（多项式滚动哈希，仅作变更检测——与契约指纹同性质）
pub fn trace_digest(t : Trace) -> String {
  let mut h1 : Int = 7
  let mut h2 : Int = 31
  for s in t.samples {
    for c in "\{s.frame},\{s.x},\{s.y},\{s.state},\{s.progress},\{s.action};" {
      let cp = c.to_int()
      h1 = (h1 * 31 + cp) % 1000003
      h2 = (h2 * 131 + cp) % 999983
    }
  }
  "\{h1}-\{h2}-\{t.samples.length()}"
}
