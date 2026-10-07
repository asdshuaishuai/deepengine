// kernel —— 确定性玩法内核（blueprint L2）。
//
// 纪律：本包零渲染依赖、零 IO——可被探针在无窗口环境直接驱动（Mechanic 契约）。
// 帧步进是纯函数语义：step(state, input) → state，同输入必同输出。

///|
/// AABB 矩形（world px）
pub(all) struct Rect {
  x : Double
  y : Double
  w : Double
  h : Double
}

///|
pub fn Rect::overlap(a : Rect, b : Rect) -> Bool {
  a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h
}

///|
pub(all) struct Player {
  mut x : Double
  mut y : Double
  mut vx : Double
  mut vy : Double
  w : Double
  h : Double
  mut grounded : Bool
  mut coyote : Int // 离地宽限帧数（coyote time）
  mut jump_held : Bool
}

///|
pub(all) struct Solid {
  rect : Rect
  color : (Int, Int, Int)
}

///|
pub(all) struct Coin {
  id : Int
  rect : Rect
  color : (Int, Int, Int)
  mut taken : Bool
}

///|
pub(all) struct Game {
  w : Int
  h : Int
  bg : (Int, Int, Int)
  gravity : Double
  jump_v : Double
  speed : Double
  player : Player
  player_color : (Int, Int, Int)
  player_seed : Int // 种子化角色（视觉层）
  spawn : (Double, Double)
  mut solids : Array[Solid]
  mut coins : Array[Coin]
  mut spikes : Array[Rect]
  mut goal : Rect?
  mut frame : Int
  mut state : String // "playing" | "won" | "dead"
  mut coins_taken : Int
}

///|
pub fn Game::new(
  w : Int,
  h : Int,
  bg : (Int, Int, Int),
  gravity : Double,
  jump_v : Double,
  speed : Double,
  player_rect : Rect,
  player_color : (Int, Int, Int),
  player_seed : Int,
  solids : Array[Solid],
  coins : Array[Coin],
  spikes : Array[Rect],
  goal : Rect?
) -> Game {
  {
    w: w,
    h: h,
    bg: bg,
    gravity: gravity,
    jump_v: jump_v,
    speed: speed,
    player: {
      x: player_rect.x,
      y: player_rect.y,
      vx: 0.0,
      vy: 0.0,
      w: player_rect.w,
      h: player_rect.h,
      grounded: false,
      coyote: 0,
      jump_held: false,
    },
    player_color: player_color,
    player_seed: player_seed,
    spawn: (player_rect.x, player_rect.y),
    solids: solids,
    coins: coins,
    spikes: spikes,
    goal: goal,
    frame: 0,
    state: "playing",
    coins_taken: 0,
  }
}

///|
/// 深拷贝——探针在副本上跑，原始状态不被污染
pub fn Game::clone(self : Game) -> Game {
  let solids2 : Array[Solid] = []
  for s in self.solids {
    solids2.push({ rect: s.rect, color: s.color })
  }
  let coins2 : Array[Coin] = []
  for c in self.coins {
    coins2.push({ id: c.id, rect: c.rect, color: c.color, taken: c.taken })
  }
  let spikes2 : Array[Rect] = []
  for s in self.spikes {
    spikes2.push(s)
  }
  let goal2 : Rect? = match self.goal {
    Some(g) => Some(g)
    None => None
  }
  {
    w: self.w,
    h: self.h,
    bg: self.bg,
    gravity: self.gravity,
    jump_v: self.jump_v,
    speed: self.speed,
    player: {
      x: self.player.x,
      y: self.player.y,
      vx: self.player.vx,
      vy: self.player.vy,
      w: self.player.w,
      h: self.player.h,
      grounded: self.player.grounded,
      coyote: self.player.coyote,
      jump_held: self.player.jump_held,
    },
    player_color: self.player_color,
    player_seed: self.player_seed,
    spawn: self.spawn,
    solids: solids2,
    coins: coins2,
    spikes: spikes2,
    goal: goal2,
    frame: self.frame,
    state: self.state,
    coins_taken: self.coins_taken,
  }
}

///|
/// 语义输入——注入点在内核边界（blueprint §3.2）
pub(all) struct Input {
  left : Bool
  right : Bool
  jump : Bool
}

///|
pub fn Input::none() -> Input {
  { left: false, right: false, jump: false }
}

///|
/// 确定性时钟：一帧固定 1/60，无 wall-clock 路径
pub fn dt() -> Double {
  1.0 / 60.0
}

///|
/// 离地宽限帧数（coyote time）
pub const COYOTE_FRAMES : Int = 6

///|
/// 帧步进：分离轴移动 + 静态 AABB 解算
pub fn step(g : Game, input : Input) -> Unit {
  if g.state != "playing" {
    return // 终态保持
  }
  g.frame = g.frame + 1
  let p = g.player

  // 水平速度（语义输入 → 方向）
  let dir : Double = if input.right && !input.left {
    1.0
  } else if input.left && !input.right {
    -1.0
  } else {
    0.0
  }
  p.vx = dir * g.speed
  // 重力
  p.vy = p.vy + g.gravity * dt()
  // 跳跃：按下沿 + coyote 宽限（jump_held 挡重复触发——幂等设置器）
  if input.jump && !p.jump_held && p.coyote > 0 {
    p.vy = g.jump_v
    p.coyote = 0
  }
  p.jump_held = input.jump

  // X 轴移动 + 解算
  p.x = p.x + p.vx * dt()
  for s in g.solids {
    if Rect::overlap({ x: p.x, y: p.y, w: p.w, h: p.h }, s.rect) {
      if p.vx > 0.0 {
        p.x = s.rect.x - p.w
      } else if p.vx < 0.0 {
        p.x = s.rect.x + s.rect.w
      }
      p.vx = 0.0
    }
  }
  // 画布左右边界
  if p.x < 0.0 {
    p.x = 0.0
  }
  if p.x + p.w > g.w.to_double() {
    p.x = g.w.to_double() - p.w
  }

  // Y 轴移动 + 解算
  p.y = p.y + p.vy * dt()
  p.grounded = false
  for s in g.solids {
    if Rect::overlap({ x: p.x, y: p.y, w: p.w, h: p.h }, s.rect) {
      if p.vy > 0.0 {
        // 下落：站上表面
        p.y = s.rect.y - p.h
        p.vy = 0.0
        p.grounded = true
      } else if p.vy < 0.0 {
        // 上升：撞头
        p.y = s.rect.y + s.rect.h
        p.vy = 0.0
      }
    }
  }
  // coyote：在地面重置，离地倒数
  if p.grounded {
    p.coyote = COYOTE_FRAMES
  } else {
    p.coyote = if p.coyote > 0 {
      p.coyote - 1
    } else {
      0
    }
  }

  // 掉出世界 = 死
  if p.y > g.h.to_double() + 400.0 {
    g.state = "dead"
    return
  }

  let body : Rect = { x: p.x, y: p.y, w: p.w, h: p.h }
  // 金币
  for c in g.coins {
    if !c.taken && Rect::overlap(body, c.rect) {
      c.taken = true
      g.coins_taken = g.coins_taken + 1
    }
  }
  // 尖刺
  for s in g.spikes {
    if Rect::overlap(body, s) {
      g.state = "dead"
      return
    }
  }
  // 终点
  match g.goal {
    Some(gl) =>
      if Rect::overlap(body, gl) {
        g.state = "won"
      }
    None => ()
  }
}

///|
/// 状态序列化（确定性比较用）：整型化坐标，规避浮点字符串抖动
pub fn serialize(g : Game) -> String {
  let g_int : Int = if g.player.grounded {
    1
  } else {
    0
  }
  let mut s = "f\{g.frame}|\{g.state}|c\{g.coins_taken}"
  s = s + "|p\{g.player.x.to_int()},\{g.player.y.to_int()},\{g.player.vx.to_int()},\{g.player.vy.to_int()},g\{g_int}"
  for c in g.coins {
    if c.taken {
      s = s + "+t\{c.id}"
    }
  }
  s
}

///|
/// runtimeState 等价物：暴露给探针/报告的可观测值（blueprint §3.3）
pub fn runtime_value(g : Game, key : String) -> String? {
  match key {
    "state" => Some(g.state)
    "coins" => Some(g.coins_taken.to_string())
    "x" => Some(g.player.x.to_int().to_string())
    "y" => Some(g.player.y.to_int().to_string())
    "frame" => Some(g.frame.to_string())
    _ => None
  }
}

// ---------------- 运行时衍生 API（v1.2：内核一等接口）----------------
// 引擎原生路径是衍生：内容不必来自文本文件，运行时直接生成/修改实体。
// 这些函数只改内核世界，与序列化/探针兼容（clone 会带上衍生实体）。

///|
/// 运行时生成金币（返回新 id；-1 = 越界拒绝）
pub fn spawn_coin(g : Game, x : Double, y : Double, w : Double) -> Int {
  if x < 0.0 || y < 0.0 || x + w > g.w.to_double() || y + w > g.h.to_double() {
    return -1
  }
  let id = g.coins.length()
  g.coins.push({
    id: id,
    rect: { x: x, y: y, w: w, h: w },
    color: (245, 165, 36),
    taken: false,
  })
  id
}

///|
/// 运行时生成平台
pub fn spawn_platform(g : Game, x : Double, y : Double, w : Double, h : Double) -> Bool {
  if x < 0.0 || y < 0.0 || x + w > g.w.to_double() || y + h > g.h.to_double() {
    return false
  }
  g.solids.push({ rect: { x: x, y: y, w: w, h: h }, color: (43, 52, 72) })
  true
}

///|
/// 运行时生成尖刺
pub fn spawn_spike(g : Game, x : Double, y : Double, w : Double) -> Bool {
  if x < 0.0 || w <= 0.0 || x + w > g.w.to_double() {
    return false
  }
  g.spikes.push({ x: x, y: y, w: w, h: 16.0 })
  true
}

///|
/// 运行时设置/移动终点（无则设置，有则移动）
pub fn spawn_goal(g : Game, x : Double, y : Double, w : Double, h : Double) -> Bool {
  if x < 0.0 || y < 0.0 || x + w > g.w.to_double() || y + h > g.h.to_double() {
    return false
  }
  g.goal = Some({ x: x, y: y, w: w, h: h })
  true
}

///|
/// 运行时移除金币（按 id）
pub fn despawn_coin(g : Game, id : Int) -> Bool {
  let kept : Array[Coin] = []
  let mut found = false
  for c in g.coins {
    if c.id == id && !found {
      found = true
      // 跳过（不移入 kept）
    } else {
      kept.push(c)
    }
  }
  if found {
    g.coins = kept
    true
  } else {
    false
  }
}
