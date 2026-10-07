// render —— kernel Game → raylib 绘制（状态投影 + 视图态动画）。
//
// 程序化角色（hero rig，blueprint §6.0 参数即资产）：
// 部件全部为参数化矩形——头/身/双腿/双臂/眼睛，姿态由状态驱动
// （走路摆腿 / 起跳伸展 / 坠落张臂 / 落地压扁扬尘 / 眨眼 / 赢输表情）。
// 视图态（朝向记忆、落地检测、尘粒、grid 移动补间）只在渲染层，不进内核。
//
// **参数来自指引**：本文件不读硬编码视觉常量——bevel / spin / teeth / flag /
// grip / dust / rig 全部取自 @rendercfg.RenderConfig（由指引 render 块生成）。
// 缺省值即历史视觉，所以没写 render 块的项目画面不变。

///|
/// 当前渲染配置（由指引 render/assembly 块生成，载入时设置一次）
/// 用 ref 而非参数传递：draw/draw_grid 的签名被 cli/web 共用，
/// 逐层加参数会把视图配置泄漏到调用方。
let rcfg : @ref.Ref[@rendercfg.RenderConfig] = @ref.new(@rendercfg.default_config())

///|
/// 当前 HUD 字段（指引 assembly 块声明）
let hud_fields : @ref.Ref[@rendercfg.HudConfig] = @ref.new(@rendercfg.default_hud())

///|
/// 装载指引时设置渲染配置（run / verify / web 各面共用）
pub fn set_render_config(cfg : @rendercfg.RenderConfig) -> Unit {
  rcfg.val = cfg
}

///|
pub fn set_hud_config(h : @rendercfg.HudConfig) -> Unit {
  hud_fields.val = h
}

///|
/// 视图态：朝向记忆（vx=0 时保持上次朝向）
let hero_facing : @ref.Ref[Double] = @ref.new(1.0)

///|
/// 视图态：上一帧是否着地（落地检测 → 扬尘 + 压扁）
let hero_prev_grounded : @ref.Ref[Bool] = @ref.new(true)

///|
/// 视图态：上一帧竖直速度（落地冲量大小）
let hero_prev_vy : @ref.Ref[Double] = @ref.new(0.0)

///|
///|
fn absf(v : Double) -> Double {
  if v < 0.0 {
    -v
  } else {
    v
  }
}

///|
priv struct Dust {
  mut x : Double
  mut y : Double
  vx : Double
  mut vy : Double
  mut life : Int
}

///|
let dusts : @ref.Ref[Array[Dust]] = @ref.new([])

///|
fn spawn_dust(x : Double, y : Double, n : Int) -> Unit {
  let mut i = 0
  while i < n {
    let a = (i.to_double() / n.to_double()) * 3.14159 // 半圆向上
    let sp = 40.0 + (i % 3).to_double() * 25.0
    dusts.val.push({
      x: x,
      y: y,
      vx: @math.cos(a) * sp,
      vy: -absf(@math.sin(a)) * sp - 30.0,
      life: 18 + i % 8,
    })
    i = i + 1
  }
}

///|
fn step_dusts() -> Unit {
  let alive : Array[Dust] = []
  for d in dusts.val {
    d.life = d.life - 1
    if d.life > 0 {
      d.x = d.x + d.vx * (1.0 / 60.0)
      d.y = d.y + d.vy * (1.0 / 60.0)
      d.vy = d.vy + 300.0 * (1.0 / 60.0) // 尘粒重力（视图级）
      alive.push(d)
    }
  }
  dusts.val = alive
}

///|
fn draw_dusts() -> Unit {
  for d in dusts.val {
    // 无 alpha 通道：亮度衰减近似淡出
    let shade = 40 + d.life * 6
    let s = if d.life > 10 {
      4.0
    } else {
      3.0
    }
    @bridge.mbg_rect(d.x, d.y, s, s, shade, shade + 6, shade + 14)
  }
}

///|
/// 本地 sin 近似（确定性纯函数；误差集中在 ±π 折叠缝，动画用途可接受）
fn fsin(x : Double) -> Double {
  let tau = 6.283185307179586
  let mut t = x % tau
  if t < 0.0 {
    t = t + tau
  }
  if t > 3.141592653589793 {
    t = t - tau
  }
  t - (t * t * t) / 6.0 + (t * t * t * t * t) / 120.0
}

///|
/// 通用小人脸部（hero rig 的头部绘制，物理/grid 共用）
fn draw_face(
  hx : Double,
  hy : Double,
  hw : Double,
  hh : Double,
  view_frame : Int,
  f : Double,
  state : String
) -> Unit {
  let eye_y = hy + hh * 0.34
  let blink = view_frame % 160 < 6
  let e1 = hx + hw * 0.20
  let e2 = hx + hw * 0.56
  if state == "dead" {
    // X 眼（错位小块近似）
    @bridge.mbg_rect(e1, eye_y, 2.0, 2.0, 235, 241, 247)
    @bridge.mbg_rect(e1 + 2.0, eye_y + 2.0, 2.0, 2.0, 235, 241, 247)
    @bridge.mbg_rect(e2, eye_y + 2.0, 2.0, 2.0, 235, 241, 247)
    @bridge.mbg_rect(e2 + 2.0, eye_y, 2.0, 2.0, 235, 241, 247)
    return
  }
  let happy = state == "won"
  let eye_h = if blink || happy {
    2.0
  } else {
    4.0
  }
  @bridge.mbg_rect(e1, eye_y, 4.0, eye_h, 235, 241, 247)
  @bridge.mbg_rect(e2, eye_y, 4.0, eye_h, 235, 241, 247)
  if !blink && !happy {
    let look = f * 1.2
    @bridge.mbg_rect(e1 + 1.0 + look, eye_y + 1.0, 2.0, 2.0, 20, 24, 34)
    @bridge.mbg_rect(e2 + 1.0 + look, eye_y + 1.0, 2.0, 2.0, 20, 24, 34)
  }
  if happy {
    // 微笑
    @bridge.mbg_rect(hx + hw * 0.28, eye_y + hh * 0.34, hw * 0.44, 2.0, 20, 24, 34)
  }
}

///|
/// 颜色梯度工具
fn lighter(c : (Int, Int, Int), n : Int) -> (Int, Int, Int) {
  let (r, g, b) = c
  (if r + n > 255 { 255 } else { r + n }, if g + n > 255 { 255 } else { g + n }, if b + n > 255 { 255 } else { b + n })
}

///|
fn darker(c : (Int, Int, Int), n : Int) -> (Int, Int, Int) {
  let (r, g, b) = c
  (if r - n < 0 { 0 } else { r - n }, if g - n < 0 { 0 } else { g - n }, if b - n < 0 { 0 } else { b - n })
}

///|
/// Hero rig（物理族）：姿态由运动状态驱动。
///   grounded + |vx|>0 → 走路循环（摆腿摆臂 + 偶发尘粒）
///   vy < -80          → 起跳伸展（收腿举臂）
///   vy > 250          → 坠落张臂
///   落地瞬间          → 压扁 + 扬尘
///   won / dead        → 庆祝 / 压扁 X 眼
fn draw_hero(
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  _color : (Int, Int, Int),
  frame : Int,
  vx : Double,
  vy : Double,
  grounded : Bool,
  state : String
) -> Unit {
  if vx > 0.0 {
    hero_facing.val = 1.0
  }
  if vx < 0.0 {
    hero_facing.val = -1.0
  }
  let f = hero_facing.val

  let just_landed = grounded && !hero_prev_grounded.val && hero_prev_vy.val > 300.0
  if just_landed {
    spawn_dust(x + w / 2.0, y + h, 7)
  }
  if grounded && vx != 0.0 && frame % 12 == 0 {
    spawn_dust(x + w / 2.0 - f * 6.0, y + h - 2.0, 1)
  }
  hero_prev_grounded.val = grounded
  hero_prev_vy.val = vy

  // squash & stretch（脚底锚定；dead 优先）
  let (sw, sh) : (Double, Double) = if state == "dead" {
    (1.25, 0.62)
  } else if !grounded {
    if vy < -80.0 {
      (0.90, 1.10) // 起跳拉长
    } else if vy > 250.0 {
      (0.94, 1.06) // 下落微拉长
    } else {
      (1.0, 1.0)
    }
  } else if just_landed {
    (1.18, 0.80) // 落地压扁
  } else {
    (1.0, 1.0)
  }
  let w2 = w * sw
  let h2 = h * sh
  let cx = x + w / 2.0
  let bottom = y + h
  let lx = cx - w2 / 2.0
  let ly = bottom - h2

  // 配色由角色种子派生（skin 包——同 seed 双端同色）
  let sk = @skin.skin_of(hero_seed_ref.val)
  let body_c = sk.body_rgb
  let (hr, hg, hb) = sk.head_rgb
  let (dr, dg, db) = sk.limb_rgb
  let (acr, acg, acb) = sk.accent_rgb

  // 部件比例
  let head_h = h2 * 0.36
  let body_h = h2 * 0.46
  let leg_h = h2 - head_h - body_h
  let head_w = w2 * 0.78
  let walking = grounded && vx != 0.0 && state == "playing"
  let phase = frame.to_double() * 0.35

  // 腿
  let leg_w = w2 * 0.26
  let (la, lb) : (Double, Double) = if walking {
    (fsin(phase) * w2 * 0.16, fsin(phase + 3.14159) * w2 * 0.16)
  } else if !grounded {
    (f * w2 * 0.10, -f * w2 * 0.06)
  } else {
    (0.0, 0.0)
  }
  let leg_y = ly + head_h + body_h
  let leg_cut = if !grounded {
    leg_h * 0.4
  } else {
    0.0
  }
  @bridge.mbg_rect(lx + w2 * 0.10 + la, leg_y, leg_w, leg_h - leg_cut, dr, dg, db)
  @bridge.mbg_rect(lx + w2 * 0.64 + lb, leg_y, leg_w, leg_h - leg_cut, dr, dg, db)

  // 臂
  let arm_w = w2 * 0.18
  let arm_h = body_h * 0.85
  let (aa, ab) : (Double, Double) = if state == "won" {
    (-head_h * 0.9, -head_h * 0.9)
  } else if !grounded {
    if vy < -80.0 {
      (-head_h * 0.7, -head_h * 0.7)
    } else {
      (-head_h * 0.3, -head_h * 0.5)
    }
  } else if walking {
    (fsin(phase + 3.14159) * body_h * 0.18, fsin(phase) * body_h * 0.18)
  } else {
    (0.0, 0.0)
  }
  let arm_y = ly + head_h * 0.9
  @bridge.mbg_rect(lx - arm_w * 0.4, arm_y + aa, arm_w, arm_h, dr, dg, db)
  @bridge.mbg_rect(lx + w2 - arm_w * 0.6, arm_y + ab, arm_w, arm_h, dr, dg, db)

  // 身体 + 头（种子配色）
  @bridge.mbg_rect(lx, ly + head_h, w2, body_h, body_c.0, body_c.1, body_c.2)
  let head_bob = if walking {
    fsin(phase * 2.0) * 1.0
  } else {
    fsin(frame.to_double() * 0.05) * 0.8 // idle 呼吸
  }
  let hx = lx + (w2 - head_w) / 2.0
  draw_head_gear(hx, ly + head_bob, head_w, sk, f)
  @bridge.mbg_rect(hx, ly + head_bob, head_w, head_h, hr, hg, hb)
  draw_face(hx, ly + head_bob, head_w, head_h, frame, f, state)
  if sk.blush {
    // 腮红
    @bridge.mbg_rect(hx - 2.0, ly + head_bob + head_h * 0.55, 4.0, 2.5, acr, acg, acb)
    @bridge.mbg_rect(hx + head_w - 2.0, ly + head_bob + head_h * 0.55, 4.0, 2.5, acr, acg, acb)
  }
}

///|
/// 视图态：当前角色种子（draw_hero 每帧从参数拿不到——用 ref 转发）
let hero_seed_ref : @ref.Ref[Int] = @ref.new(0)

///|
/// 头饰（native 近似：耳/角/天线/呆毛——SVG 为权威形态）
fn draw_head_gear(hx : Double, hy : Double, hw : Double, sk : @skin.Skin, f : Double) -> Unit {
  let (acr, acg, acb) = sk.accent_rgb
  let (lr, lg, lb) = sk.limb_rgb
  match sk.ear_style {
    1 => {
      // 猫耳（三角近似：两块梯级矩形）
      @bridge.mbg_rect(hx + hw * 0.04, hy - 6.0, 5.0, 6.0, acr, acg, acb)
      @bridge.mbg_rect(hx + hw * 0.10, hy - 9.0, 3.0, 4.0, acr, acg, acb)
      @bridge.mbg_rect(hx + hw * 0.82, hy - 6.0, 5.0, 6.0, acr, acg, acb)
      @bridge.mbg_rect(hx + hw * 0.78, hy - 9.0, 3.0, 4.0, acr, acg, acb)
    }
    2 => {
      // 角
      @bridge.mbg_rect(hx + hw * 0.06, hy - 8.0, 3.5, 8.0, lr, lg, lb)
      @bridge.mbg_rect(hx + hw * 0.88, hy - 8.0, 3.5, 8.0, lr, lg, lb)
    }
    3 => {
      // 天线
      @bridge.mbg_rect(hx + hw / 2.0 - 1.0, hy - 9.0, 2.0, 9.0, lr, lg, lb)
      @bridge.mbg_circle(hx + hw / 2.0, hy - 10.0, 3.0, acr, acg, acb)
    }
    4 => {
      // 呆毛
      @bridge.mbg_rect(hx + hw / 2.0 - 1.5, hy - 6.0, 3.0, 6.0, acr, acg, acb)
      @bridge.mbg_rect(hx + hw / 2.0 + 1.5, hy - 4.0, 3.0, 4.0, acr, acg, acb)
    }
    _ => ()
  }
  ignore(f)
}

///|
pub fn draw(g : @kernel.Game) -> Unit {
  let (br, bg_, bb) = g.bg
  @bridge.mbg_clear(br, bg_, bb)
  let frame = g.frame
  let cfg = rcfg.val

  // 平台：主体 + 顶亮边（bevel=亮度增量, edge=高度，均来自指引）
  for s in g.solids {
    let (r, gg, b) = s.color
    @bridge.mbg_rect(s.rect.x, s.rect.y, s.rect.w, s.rect.h, r, gg, b)
    if cfg.platform_edge > 0.0 {
      let (hr, hg, hb) = lighter(s.color, cfg.platform_bevel)
      @bridge.mbg_rect(s.rect.x, s.rect.y, s.rect.w, cfg.platform_edge, hr, hg, hb)
    }
  }
  // 金币：旋转（频率来自指引）
  for c in g.coins {
    if !c.taken {
      let (r, gg, b) = c.color
      let spin = 0.72 + 0.28 * fsin(frame.to_double() * cfg.coin_spin + c.id.to_double())
      let rad = c.rect.w / 2.0 * spin
      let cx2 = c.rect.x + c.rect.w / 2.0
      let cy2 = c.rect.y + c.rect.h / 2.0
      @bridge.mbg_circle(cx2, cy2, rad, r, gg, b)
      let (ir, ig, ib) = darker(c.color, 50)
      @bridge.mbg_circle(cx2, cy2, rad * 0.55, ir, ig, ib)
    }
  }
  // 尖刺：三角形态（齿数来自指引）
  for s in g.spikes {
    let teeth = cfg.spike_teeth.to_double()
    let tw = s.w / teeth
    let mut i = 0
    while i.to_double() < teeth {
      let tx = s.x + i.to_double() * tw
      let seg = tw / 3.0
      let mut k = 0
      while k < 3 {
        let shrink = k.to_double() * seg * 0.5
        @bridge.mbg_rect(tx + shrink, s.y + k.to_double() * (s.h / 3.0), tw - shrink * 2.0, s.h / 3.0 + 1.0, 229 - k * 18, 72, 77 + k * 10)
        k = k + 1
      }
      i = i + 1
    }
  }
  // 终点：旗座 + 旗杆 + 飘旗（旗杆高度来自指引）
  match g.goal {
    Some(gl) => {
      @bridge.mbg_rect(gl.x, gl.y, gl.w, gl.h, 24, 82, 54)
      @bridge.mbg_rect(gl.x + gl.w / 2.0 - 1.5, gl.y - cfg.goal_flag, 3.0, cfg.goal_flag, 230, 234, 240)
      let wave = fsin(frame.to_double() * 0.22) * 3.0
      @bridge.mbg_rect(gl.x + gl.w / 2.0 + 1.5, gl.y - cfg.goal_flag + 2.0 + wave, 16.0, 10.0, 48, 164, 108)
    }
    None => ()
  }
  // Hero + 尘粒（rig 开关来自指引）
  if cfg.dust {
    draw_dusts()
  }
  hero_seed_ref.val = if cfg.hero_seed >= 0 { cfg.hero_seed } else { g.player_seed }
  if cfg.hero_rig {
    draw_hero(
      g.player.x,
      g.player.y,
      g.player.w,
      g.player.h,
      g.player_color,
      g.frame,
      g.player.vx,
      g.player.vy,
      g.player.grounded,
      g.state,
    )
  } else {
    draw_hero_simple(g.player.x, g.player.y, g.player.w, g.player.h, g.player_color, g.state)
  }
  if cfg.dust {
    step_dusts()
  }

  // HUD（字段由指引 assembly 块声明；未声明则用默认字段集）
  let hud = @rendercfg.hud_text_physics(hud_fields.val.fields, g)
  let _ = @bridge.mbg_text(hud, 12.0, 10.0, 18.0, 200, 208, 224)
  let hint = "arrows/space play   R reload   esc quit"
  let _ = @bridge.mbg_text(hint, 12.0, 32.0, 14.0, 90, 96, 122)
}

///|
/// rig: off 时的朴素角色（纯矩形 + 眼睛）——程序化资产的降级形态，非外部素材
fn draw_hero_simple(x : Double, y : Double, w : Double, h : Double, color : (Int, Int, Int), state : String) -> Unit {
  let (r, g, b) = color
  @bridge.mbg_rect(x, y, w, h, r, g, b)
  let ey = y + h * 0.3
  let ec : (Int, Int, Int) = if state == "dead" {
    (235, 241, 247)
  } else {
    (20, 24, 34)
  }
  @bridge.mbg_rect(x + w * 0.2, ey, 3.0, 3.0, ec.0, ec.1, ec.2)
  @bridge.mbg_rect(x + w * 0.6, ey, 3.0, 3.0, ec.0, ec.1, ec.2)
}

// ---------------- grid 族 ----------------

///|
/// 箱子是否在目标格上
fn on_goal_cell(g : @kernel.GridGame, x : Int, y : Int) -> Bool {
  for t in g.goals {
    let (gx, gy) = t
    if gx == x && gy == y {
      return true
    }
  }
  false
}

///|
/// grid 视图态：移动补间（上一格、动画帧、是否推箱、视图时钟）
let gv_frame : @ref.Ref[Int] = @ref.new(0)

///|
let gv_last_cell : @ref.Ref[(Int, Int)] = @ref.new((-1, -1))

///|
let gv_anim : @ref.Ref[Int] = @ref.new(999)

///|
let gv_dir : @ref.Ref[(Double, Double)] = @ref.new((0.0, 0.0))

///|
/// Hero rig（grid 族）：同套部件，离散移动补间出小人跳跃感
fn draw_grid_hero(
  g : @kernel.GridGame,
  cell : Double,
  frame : Int
) -> Unit {
  // 移动检测 → 启动 8 帧补间
  let cur : (Int, Int) = (g.px, g.py)
  if cur != gv_last_cell.val && gv_last_cell.val.0 >= 0 {
    let (ox, oy) = gv_last_cell.val
    gv_dir.val = ((g.px - ox).to_double(), (g.py - oy).to_double())
    gv_anim.val = 0
  }
  gv_last_cell.val = cur

  // 渲染坐标 = 单元格 + 补间偏移
  let t = if gv_anim.val < 8 {
    gv_anim.val.to_double() / 8.0
  } else {
    1.0
  }
  let (dx, dy) = gv_dir.val
  let hop = if gv_anim.val < 8 {
    fsin(3.14159 * t) * 10.0 // 抛物线小跳
  } else {
    0.0
  }
  let rx = (g.px.to_double() - dx * (1.0 - t)) * cell
  let ry = (g.py.to_double() - dy * (1.0 - t)) * cell - hop
  gv_anim.val = gv_anim.val + 1

  let w = cell - 10.0
  let h = cell - 10.0
  let lx = rx + 5.0
  let bottom = ry + cell - 5.0
  let ly = bottom - h

  // 起跳/落地压扁
  let (sw, sh) : (Double, Double) = if gv_anim.val < 3 {
    (1.15, 0.85)
  } else if gv_anim.val > 6 && gv_anim.val < 10 {
    (1.10, 0.90)
  } else {
    (1.0, 1.0)
  }
  let w2 = w * sw
  let h2 = h * sh
  let cx = lx + w / 2.0
  let lx2 = cx - w2 / 2.0
  let ly2 = bottom - h2

  let sk = @skin.skin_of(g.seed)
  let color = sk.body_rgb
  let (hr, hg, hb) = sk.head_rgb
  let (dr, dg, db) = sk.limb_rgb
  let head_h = h2 * 0.38
  let body_h = h2 - head_h
  let head_w = w2 * 0.78
  let f = if dx != 0.0 {
    dx
  } else {
    hero_facing.val
  }
  hero_facing.val = f
  let push_lean = if gv_anim.val < 8 {
    f * 2.0
  } else {
    0.0
  }
  let idle = fsin(frame.to_double() * 0.05) * 0.8

  // 腿（补间中抬起）
  let leg_w = w2 * 0.26
  let leg_h = body_h * 0.22
  let leg_y = ly2 + head_h + body_h - leg_h
  let leg_lift = if gv_anim.val < 8 {
    3.0
  } else {
    0.0
  }
  @bridge.mbg_rect(lx2 + w2 * 0.12, leg_y - leg_lift, leg_w, leg_h, dr, dg, db)
  @bridge.mbg_rect(lx2 + w2 * 0.62, leg_y, leg_w, leg_h, dr, dg, db)
  // 臂（推箱前伸）
  let arm_w = w2 * 0.18
  let arm_h = body_h * 0.5
  let arm_y = ly2 + head_h * 0.85
  @bridge.mbg_rect(lx2 - arm_w * 0.3, arm_y, arm_w, arm_h, dr, dg, db)
  @bridge.mbg_rect(lx2 + w2 - arm_w * 0.7 + push_lean, arm_y, arm_w, arm_h, dr, dg, db)
  // 身体 + 头（前倾：身体沿朝向偏移；种子配色）
  @bridge.mbg_rect(lx2 + push_lean * 0.5, ly2 + head_h, w2, body_h, color.0, color.1, color.2)
  let hx = lx2 + (w2 - head_w) / 2.0 + push_lean
  draw_head_gear(hx, ly2 + idle, head_w, sk, f)
  @bridge.mbg_rect(hx, ly2 + idle, head_w, head_h, hr, hg, hb)
  draw_face(hx, ly2 + idle, head_w, head_h, frame, f, g.state)
}

///|
/// grid 族渲染
pub fn draw_grid(g : @kernel.GridGame, cell : Int) -> Unit {
  gv_frame.val = gv_frame.val + 1
  let frame = gv_frame.val
  let c = cell.to_double()
  let cfg = rcfg.val

  @bridge.mbg_clear(13, 16, 33)
  // 网格底色
  @bridge.mbg_rect(0.0, 0.0, g.cols.to_double() * c, g.rows.to_double() * c, 18, 22, 40)
  // 目标格
  for t in g.goals {
    let (gx, gy) = t
    @bridge.mbg_rect(gx.to_double() * c + 6.0, gy.to_double() * c + 6.0, c - 12.0, c - 12.0, 48, 164, 108)
  }
  // 墙 + 顶亮边（高度来自指引）
  for w in g.walls {
    let (wx, wy) = w
    let x = wx.to_double() * c
    let y = wy.to_double() * c
    @bridge.mbg_rect(x, y, c, c, 43, 52, 77)
    if cfg.grid_grip > 0 {
      @bridge.mbg_rect(x, y, c, cfg.grid_grip.to_double(), 64, 76, 110)
    }
  }
  // 箱子（就位变绿 + 表情：普通无脸，就位眯眼笑）
  for b in g.boxes {
    let (bx, by) = b
    let x = bx.to_double() * c + 4.0
    let y = by.to_double() * c + 4.0
    let w = c - 8.0
    let happy = on_goal_cell(g, bx, by)
    let fill : (Int, Int, Int) = if happy {
      (66, 190, 132)
    } else {
      (229, 165, 54)
    }
    @bridge.mbg_rect(x, y, w, w, fill.0, fill.1, fill.2)
    let (tr, tg, tb) = lighter(fill, 40)
    @bridge.mbg_rect(x, y, w, 3.0, tr, tg, tb)
    if happy {
      // 眯眼笑 + 嘴
      @bridge.mbg_rect(x + w * 0.22, y + w * 0.32, w * 0.16, 2.0, 30, 60, 40)
      @bridge.mbg_rect(x + w * 0.62, y + w * 0.32, w * 0.16, 2.0, 30, 60, 40)
      @bridge.mbg_rect(x + w * 0.32, y + w * 0.58, w * 0.36, 2.0, 30, 60, 40)
    }
  }
  // Hero（补间动画）
  draw_grid_hero(g, c, frame)

  // HUD（字段由指引 assembly 块声明）
  let hud = @rendercfg.hud_text_grid(hud_fields.val.fields, g)
  let _ = @bridge.mbg_text(hud, 12.0, 10.0, 18.0, 200, 208, 224)
  let hint = "arrows play   R reload   esc quit"
  let _ = @bridge.mbg_text(hint, 12.0, 32.0, 14.0, 90, 96, 122)
}
