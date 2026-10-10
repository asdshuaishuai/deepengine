// grid —— grid_logic 原型族内核（blueprint §5.1：离散网格，无物理循环）。
//
// 物理优先分类学的第二族：与 gravity_side（重力+刚体）不同，本族是
// 离散回合移动 + 推箱语义。独立的 Game 类型是架构正确性的体现——
// "物理形状决定骨架"。

///|
pub(all) struct GridGame {
  cols : Int
  rows : Int
  seed : Int // 种子化角色（视觉层）
  mut px : Int
  mut py : Int
  mut walls : Array[(Int, Int)]
  mut boxes : Array[(Int, Int)]
  mut goals : Array[(Int, Int)]
  mut moves : Int // 成功移动计数
  mut state : String // "playing" | "won"
}

///|
pub fn GridGame::new(
  cols : Int,
  rows : Int,
  seed : Int,
  px : Int,
  py : Int,
  walls : Array[(Int, Int)],
  boxes : Array[(Int, Int)],
  goals : Array[(Int, Int)]
) -> GridGame {
  {
    cols: cols,
    rows: rows,
    seed: seed,
    px: px,
    py: py,
    walls: walls,
    boxes: boxes,
    goals: goals,
    moves: 0,
    state: "playing",
  }
}

///|
pub fn GridGame::clone(self : GridGame) -> GridGame {
  let walls2 : Array[(Int, Int)] = []
  for w in self.walls {
    walls2.push(w)
  }
  let boxes2 : Array[(Int, Int)] = []
  for b in self.boxes {
    boxes2.push(b)
  }
  let goals2 : Array[(Int, Int)] = []
  for g in self.goals {
    goals2.push(g)
  }
  {
    cols: self.cols,
    rows: self.rows,
    seed: self.seed,
    px: self.px,
    py: self.py,
    walls: walls2,
    boxes: boxes2,
    goals: goals2,
    moves: self.moves,
    state: self.state,
  }
}

///|
fn cell_in(list : Array[(Int, Int)], x : Int, y : Int) -> Bool {
  for c in list {
    let (cx, cy) = c
    if cx == x && cy == y {
      return true
    }
  }
  false
}

///|
/// 在目标点上的箱子下标
fn box_at(g : GridGame, x : Int, y : Int) -> Int? {
  let mut i = 0
  for b in g.boxes {
    let (bx, by) = b
    if bx == x && by == y {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// 已就位的箱子数
pub fn grid_boxes_on(g : GridGame) -> Int {
  let mut n = 0
  for b in g.boxes {
    let (bx, by) = b
    if cell_in(g.goals, bx, by) {
      n = n + 1
    }
  }
  n
}

///|
/// 一次离散移动：dir ∈ left/right/up/down。撞墙不动；推箱受阻不动。
pub fn grid_step(g : GridGame, dir : String) -> Unit {
  if g.state != "playing" {
    return
  }
  let dx : Int = if dir == "right" {
    1
  } else if dir == "left" {
    -1
  } else {
    0
  }
  let dy : Int = if dir == "down" {
    1
  } else if dir == "up" {
    -1
  } else {
    0
  }
  let tx = g.px + dx
  let ty = g.py + dy
  if tx < 0 || tx >= g.cols || ty < 0 || ty >= g.rows {
    return // 出界视为墙
  }
  if cell_in(g.walls, tx, ty) {
    return
  }
  match box_at(g, tx, ty) {
    Some(idx) => {
      // 推箱：箱目标格必须为空（非墙、无箱）
      let bx = tx + dx
      let by = ty + dy
      if bx < 0 || bx >= g.cols || by < 0 || by >= g.rows {
        return
      }
      if cell_in(g.walls, bx, by) {
        return
      }
      if box_at(g, bx, by) is Some(_) {
        return
      }
      g.boxes[idx] = (bx, by)
      g.px = tx
      g.py = ty
      g.moves = g.moves + 1
    }
    None => {
      g.px = tx
      g.py = ty
      g.moves = g.moves + 1
    }
  }
  // 胜利判定：至少一个箱子且全部就位
  if g.boxes.length() > 0 && grid_boxes_on(g) == g.boxes.length() {
    g.state = "won"
  }
}

///|
/// 脚本 → [(方向, 回合数)]——**唯一** grid 脚本解析器。
///
/// grid_run_script 与轨迹采样共用这一份展开（与物理族 script_plan 同一纪律：
/// 脚本语法只有一份实现）。未识别指令容错跳过，由解析层 P0 门禁负责报错。
pub fn grid_plan(script : String) -> Array[(String, Int)] {
  let out : Array[(String, Int)] = []
  let toks : Array[StringView] = script.split(",").iter().collect()
  for tok in toks {
    let t = tok.trim().to_owned()
    if t.length() == 0 {
      continue
    }
    let parts : Array[StringView] = t.split(":").iter().collect()
    let head = parts[0].trim().to_owned()
    let n : Int = if parts.length() > 1 {
      match parse_int_view(parts[1]) {
        Some(v) => v
        None => 1
      }
    } else {
      1
    }
    match head {
      "left" | "right" | "up" | "down" => out.push((head, n))
      _ => ()
    }
  }
  out
}

///|
/// 脚本执行（与物理族同语法；wait = 原地一回合无操作）
pub fn grid_run_script(g0 : GridGame, script : String) -> GridGame {
  let g = GridGame::clone(g0)
  for cmd in grid_plan(script) {
    let (dir, n) = cmd
    let mut i = 0
    while i < n {
      grid_step(g, dir)
      i = i + 1
    }
  }
  g
}

///|
fn parse_int_view(v : StringView) -> Int? {
  let t = v.trim().to_owned()
  if t.length() == 0 {
    return None
  }
  let mut value = 0
  let mut ok = true
  for ch in t {
    let d = "0123456789".find(ch.to_string())
    match d {
      Some(x) => value = value * 10 + x
      None => {
        ok = false
        break
      }
    }
  }
  if ok {
    Some(value)
  } else {
    None
  }
}

///|
pub fn grid_serialize(g : GridGame) -> String {
  let mut s = "m\{g.moves}|\{g.state}|p\{g.px},\{g.py}"
  for b in g.boxes {
    let (bx, by) = b
    s = s + "+b\{bx},\{by}"
  }
  s
}

///|
pub fn grid_runtime_value(g : GridGame, key : String) -> String? {
  match key {
    "state" => Some(g.state)
    "moves" => Some(g.moves.to_string())
    "x" => Some(g.px.to_string())
    "y" => Some(g.py.to_string())
    "boxes_on" => Some(grid_boxes_on(g).to_string())
    _ => None
  }
}

// ---------------- verify（grid 版通用探针）----------------

///|
fn grid_eval_expect(g : GridGame, expect : String) -> Bool {
  let ops = ["==", ">=", "<=", "!="]
  for op in ops {
    let pos = expect.find(op)
    match pos {
      Some(i) => {
        let key = expect.substring(start=0, end=i).trim().to_owned()
        let val = expect.substring(start=i + op.length()).trim().to_owned()
        let actual = match grid_runtime_value(g, key) {
          Some(a) => a
          None => return false
        }
        if op == "==" {
          return actual == val
        }
        if op == "!=" {
          return actual != val
        }
        let a = match parse_int_view(actual) {
          Some(v) => v
          None => return false
        }
        let b = match parse_int_view(val) {
          Some(v) => v
          None => return false
        }
        if op == ">=" {
          return a >= b
        }
        return a <= b
      }
      None => ()
    }
  }
  false
}

///|
/// grid 通用探针与物理族同哲学但语义适配：无重力 → 稳定 = 无输入无变化；
/// 有限性 → 墙被尊重（狂推不出界）。
pub fn verify_grid(g0 : GridGame, probes : Array[Probe]) -> Report {
  let results : Array[ProbeResult] = []
  let evidence : Array[String] = []

  // U1 确定性
  let det_script : String = if probes.length() > 0 {
    probes[0].script
  } else {
    "right:5"
  }
  let a1 = grid_serialize(grid_run_script(g0, det_script))
  let a2 = grid_serialize(grid_run_script(g0, det_script))
  results.push({
    name: "u_determinism",
    pass: a1 == a2,
    detail: "double-run serialize equal=\{a1 == a2}",
  })
  evidence.push("grid double-run serialize compare")

  // U2 输入响应：四方向至少一个能动（出生点可能被围）
  let g_r = grid_run_script(g0, "right:1")
  let g_l = grid_run_script(g0, "left:1")
  let g_u = grid_run_script(g0, "up:1")
  let g_d = grid_run_script(g0, "down:1")
  let moved = g_r.px != g0.px || g_l.px != g0.px || g_u.py != g0.py || g_d.py != g0.py
  results.push({
    name: "u_input_response",
    pass: moved,
    detail: "some direction moves=\{moved}",
  })
  evidence.push("4-direction single-step response")

  // U3 静止稳定：无输入序列化不变
  let g_w = grid_run_script(g0, "wait:10")
  results.push({
    name: "u_idle_stability",
    pass: grid_serialize(g_w) == grid_serialize(GridGame::clone(g0)) && g_w.state == "playing",
    detail: "idle 10 turns unchanged",
  })
  evidence.push("idle stability serialize equal")

  // U4 墙被尊重：四方向狂推不出界
  let g_b = grid_run_script(g0, "right:99, left:99, up:99, down:99")
  let in_bounds = g_b.px >= 0 && g_b.px < g_b.cols && g_b.py >= 0 && g_b.py < g_b.rows
  results.push({
    name: "u_walls_respected",
    pass: in_bounds,
    detail: "after 4x99 pushes at (\{g_b.px},\{g_b.py})",
  })
  evidence.push("bounds after saturation moves")

  // 声明探针
  for p in probes {
    let g_end = grid_run_script(g0, p.script)
    let ok = grid_eval_expect(g_end, p.expect)
    let key = key_of_grid(p.expect)
    let got = match grid_runtime_value(g_end, key) {
      Some(v) => v
      None => "?"
    }
    results.push({
      name: p.name,
      pass: ok,
      detail: "expect[\{p.expect}] got[\{key}=\{got}] state=\{g_end.state} m\{g_end.moves}",
    })
    evidence.push("script replay serialize=\{grid_serialize(g_end)}")
  }

  let total = results.length()
  let mut passed = 0
  for r in results {
    if r.pass {
      passed = passed + 1
    }
  }
  {
    reward: if passed == total {
      1
    } else {
      0
    },
    total: total,
    passed: passed,
    results: results,
    evidence: evidence,
    unsupported: [
      "未覆盖非脚本路径（自由输入/撤销）",
      "截图未做逐字节回归（仅采样证据）",
      "未证明死锁关卡（无解局面）的可检测性",
    ],
  }
}

///|
fn key_of_grid(expect : String) -> String {
  let ops = ["==", ">=", "<=", "!="]
  for op in ops {
    let pos = expect.find(op)
    match pos {
      Some(i) => return expect.substring(start=0, end=i).trim().to_owned()
      None => ()
    }
  }
  expect
}

// ---------------- 运行时衍生 API（grid 族）----------------

///|
/// 生成箱子（目标格必须为空：非墙/非箱/非玩家）——生成后可能立即触发胜利判定
pub fn grid_spawn_box(g : GridGame, x : Int, y : Int) -> Bool {
  if x < 0 || x >= g.cols || y < 0 || y >= g.rows {
    return false
  }
  if cell_in(g.walls, x, y) || box_at(g, x, y) is Some(_) {
    return false
  }
  if g.px == x && g.py == y {
    return false
  }
  g.boxes.push((x, y))
  // 生成即就位的场合直接判胜（衍生内容同样受规则约束）
  if grid_boxes_on(g) == g.boxes.length() {
    g.state = "won"
  }
  true
}

///|
/// 生成墙（不能压玩家/箱/已有目标）
pub fn grid_spawn_wall(g : GridGame, x : Int, y : Int) -> Bool {
  if x < 0 || x >= g.cols || y < 0 || y >= g.rows {
    return false
  }
  if g.px == x && g.py == y {
    return false
  }
  if box_at(g, x, y) is Some(_) {
    return false
  }
  if cell_in(g.goals, x, y) {
    return false
  }
  if cell_in(g.walls, x, y) {
    return false
  }
  g.walls.push((x, y))
  true
}

///|
/// 生成目标格
pub fn grid_spawn_goal(g : GridGame, x : Int, y : Int) -> Bool {
  if x < 0 || x >= g.cols || y < 0 || y >= g.rows {
    return false
  }
  if cell_in(g.walls, x, y) || cell_in(g.goals, x, y) {
    return false
  }
  g.goals.push((x, y))
  if g.boxes.length() > 0 && grid_boxes_on(g) == g.boxes.length() {
    g.state = "won"
  }
  true
}
