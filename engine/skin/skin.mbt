// skin —— 种子化角色生成器（blueprint §6.0 程序化优先的正式条目）。
//
// 种子 → 特征集 → SVG。同一种子必得同一角色（确定性）；
// SVG 是文本工件：可保存、可 diff、可被 agent 直接消费。
//
// 特征维度：配色（HSL 派生）/ 头型圆度 / 头饰（耳/角/天线/呆毛）/
// 眼型 / 嘴型 / 身体纹样 / 腮红 / 比例。seed 0 = 经典蓝主角。

///|
/// 31 位 xorshift（移位不溢出，mask 保持非负——确定性核心）
priv struct Rng {
  mut s : Int
}

///|
fn Rng::new(seed : Int) -> Rng {
  // 0 会退化，混入固定盐
  let s0 = if seed == 0 {
    0x4a9eff
  } else {
    seed
  }
  { s: s0 & 0x7fffffff }
}

///|
fn Rng::next(self : Rng) -> Int {
  let mut x = self.s
  x = (x ^ (x << 13)) & 0x7fffffff
  x = x ^ (x >> 17)
  x = (x ^ (x << 5)) & 0x7fffffff
  self.s = x
  x
}

///|
/// [0, n) 均匀取整
fn Rng::range(self : Rng, n : Int) -> Int {
  self.next() % n
}

///|
/// 角色特征集（全部由种子派生）
pub(all) struct Skin {
  // 配色
  body_rgb : (Int, Int, Int)
  head_rgb : (Int, Int, Int)
  limb_rgb : (Int, Int, Int)
  accent_rgb : (Int, Int, Int) // 纹样/头饰点缀
  // 头部
  head_round : Double // 0=方 1=圆（SVG rx）
  ear_style : Int // 0 无 1 猫耳 2 角 3 天线 4 呆毛
  eye_style : Int // 0 方瞳 1 圆瞳 2 大圆 3 横条
  mouth : Int // 0 无 1 微笑 2 小嘴 3 猫嘴
  blush : Bool
  // 身体
  pattern : Int // 0 无 1 条纹 2 肚皮 3 腰带
  // 比例
  head_ratio : Double // 头高占比
  arm_len : Double
  leg_len : Double
}

///|
/// HSL → RGB（h∈[0,360) s,l∈[0,1]）
fn hsl_to_rgb(h : Double, s : Double, l : Double) -> (Int, Int, Int) {
  let c = (1.0 - (2.0 * l - 1.0).abs()) * s
  let hp = h / 60.0
  let x = c * (1.0 - (hp % 2.0 - 1.0).abs())
  let (r1, g1, b1) : (Double, Double, Double) = if hp < 1.0 {
    (c, x, 0.0)
  } else if hp < 2.0 {
    (x, c, 0.0)
  } else if hp < 3.0 {
    (0.0, c, x)
  } else if hp < 4.0 {
    (0.0, x, c)
  } else if hp < 5.0 {
    (x, 0.0, c)
  } else {
    (c, 0.0, x)
  }
  let m = l - c / 2.0
  (
    ((r1 + m) * 255.0).to_int(),
    ((g1 + m) * 255.0).to_int(),
    ((b1 + m) * 255.0).to_int(),
  )
}

///|
fn hex(rgb : (Int, Int, Int)) -> String {
  let (r, g, b) = rgb
  let digits = "0123456789abcdef"
  let mut s = "#"
  let mut i = 0
  while i < 3 {
    let v = if i == 0 {
      r
    } else if i == 1 {
      g
    } else {
      b
    }
    let hi = v / 16
    let lo = v % 16
    s = s + digits.substring(start=hi, end=hi + 1)
    s = s + digits.substring(start=lo, end=lo + 1)
    i = i + 1
  }
  s
}

///|
/// 种子 → 特征集。seed 0 走固定经典蓝（不随机）。
pub fn skin_of(seed : Int) -> Skin {
  if seed == 0 {
    return {
      body_rgb: (74, 158, 255),
      head_rgb: (114, 186, 255),
      limb_rgb: (42, 98, 170),
      accent_rgb: (255, 205, 120),
      head_round: 0.45,
      ear_style: 0,
      eye_style: 0,
      mouth: 1,
      blush: false,
      pattern: 0,
      head_ratio: 0.36,
      arm_len: 0.85,
      leg_len: 1.0,
    }
  }
  let rng = Rng::new(seed)
  // 主色相：全谱但避开浑浊区；饱和中高、亮度中（游戏可读性）
  let hue = rng.range(360).to_double()
  let body = hsl_to_rgb(hue, 0.62 + rng.range(20).to_double() / 100.0, 0.52 + rng.range(12).to_double() / 100.0)
  let head = hsl_to_rgb(hue, 0.60, 0.66)
  let limb = hsl_to_rgb(hue, 0.62, 0.34)
  let accent = hsl_to_rgb((hue + 150.0 + rng.range(60).to_double()) % 360.0, 0.75, 0.68)
  {
    body_rgb: body,
    head_rgb: head,
    limb_rgb: limb,
    accent_rgb: accent,
    head_round: rng.range(100).to_double() / 100.0,
    ear_style: rng.range(5),
    eye_style: rng.range(4),
    mouth: rng.range(4),
    blush: rng.range(3) == 0,
    pattern: rng.range(4),
    head_ratio: 0.32 + rng.range(10).to_double() / 100.0,
    arm_len: 0.75 + rng.range(25).to_double() / 100.0,
    leg_len: 0.9 + rng.range(20).to_double() / 100.0,
  }
}

///|
/// 特征摘要（JSON——探针/测试/调试用）
pub fn skin_summary(seed : Int) -> String {
  let s = skin_of(seed)
  "{\"seed\":\{seed},\"body\":\"\{hex(s.body_rgb)}\",\"head\":\"\{hex(s.head_rgb)}\",\"limb\":\"\{hex(s.limb_rgb)}\",\"accent\":\"\{hex(s.accent_rgb)}\",\"ear\":\{s.ear_style},\"eyes\":\{s.eye_style},\"mouth\":\{s.mouth},\"pattern\":\{s.pattern},\"blush\":\{s.blush}}"
}

///|
fn fi(v : Double) -> String {
  v.to_int().to_string()
}

///|
/// 完整独立 SVG（64×64 viewBox，部件带 id 供宿主做 transform 动画：
/// legL/legR/armL/armR/body/head——头部装饰随 head 组）。
pub fn skin_svg(seed : Int) -> String {
  let s = skin_of(seed)
  let body_c = hex(s.body_rgb)
  let head_c = hex(s.head_rgb)
  let limb_c = hex(s.limb_rgb)
  let accent_c = hex(s.accent_rgb)
  let head_h = 64.0 * s.head_ratio
  let body_y = head_h
  let body_h = 64.0 - head_h
  let leg_h = body_h * 0.30 * s.leg_len
  let torso_h = body_h - leg_h
  let rx = 3.0 + s.head_round * 9.0

  let mut svg = ""
  svg = svg + "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 64\" width=\"64\" height=\"64\">"
  svg = svg + "<g id=\"char\">"

  // —— 腿（可摆动组）——
  svg = svg + "<g id=\"legL\"><rect x=\"14\" y=\"" + fi(body_y + torso_h) + "\" width=\"10\" height=\"" + fi(leg_h) + "\" rx=\"3\" fill=\"" + limb_c + "\"/></g>"
  svg = svg + "<g id=\"legR\"><rect x=\"40\" y=\"" + fi(body_y + torso_h) + "\" width=\"10\" height=\"" + fi(leg_h) + "\" rx=\"3\" fill=\"" + limb_c + "\"/></g>"
  // —— 臂（可摆动组）——
  let arm_h = torso_h * s.arm_len
  svg = svg + "<g id=\"armL\"><rect x=\"2\" y=\"" + fi(body_y + 2.0) + "\" width=\"8\" height=\"" + fi(arm_h) + "\" rx=\"4\" fill=\"" + limb_c + "\"/></g>"
  svg = svg + "<g id=\"armR\"><rect x=\"54\" y=\"" + fi(body_y + 2.0) + "\" width=\"8\" height=\"" + fi(arm_h) + "\" rx=\"4\" fill=\"" + limb_c + "\"/></g>"
  // —— 身体（含纹样）——
  svg = svg + "<g id=\"body\">"
  svg = svg + "<rect x=\"8\" y=\"" + fi(body_y) + "\" width=\"48\" height=\"" + fi(torso_h) + "\" rx=\"6\" fill=\"" + body_c + "\"/>"
  if s.pattern == 1 {
    // 条纹
    let mut sy = body_y + 4.0
    while sy < body_y + torso_h - 3.0 {
      svg = svg + "<rect x=\"10\" y=\"" + fi(sy) + "\" width=\"44\" height=\"3\" rx=\"1.5\" fill=\"" + limb_c + "\" opacity=\"0.55\"/>"
      sy = sy + 8.0
    }
  }
  if s.pattern == 2 {
    svg = svg + "<ellipse cx=\"32\" cy=\"" + fi(body_y + torso_h * 0.62) + "\" rx=\"14\" ry=\"" + fi(torso_h * 0.30) + "\" fill=\"" + head_c + "\" opacity=\"0.9\"/>"
  }
  if s.pattern == 3 {
    svg = svg + "<rect x=\"8\" y=\"" + fi(body_y + torso_h * 0.55) + "\" width=\"48\" height=\"6\" fill=\"" + accent_c + "\"/>"
  }
  svg = svg + "</g>"
  // —— 头（含装饰/脸）——
  svg = svg + "<g id=\"head\">"
  // 头饰（画在头后面）
  match s.ear_style {
    1 => {
      // 猫耳
      svg = svg + "<path d=\"M14,10 L20,-2 L27,8 Z\" fill=\"" + accent_c + "\"/>"
      svg = svg + "<path d=\"M50,10 L44,-2 L37,8 Z\" fill=\"" + accent_c + "\"/>"
    }
    2 => {
      // 角
      svg = svg + "<path d=\"M16,8 L14,-4 L23,4 Z\" fill=\"" + limb_c + "\"/>"
      svg = svg + "<path d=\"M48,8 L50,-4 L41,4 Z\" fill=\"" + limb_c + "\"/>"
    }
    3 => {
      // 天线
      svg = svg + "<rect x=\"31\" y=\"-8\" width=\"2\" height=\"12\" fill=\"" + limb_c + "\"/>"
      svg = svg + "<circle cx=\"32\" cy=\"-9\" r=\"3.5\" fill=\"" + accent_c + "\"/>"
    }
    4 => {
      // 呆毛
      svg = svg + "<path d=\"M32,2 C28,-6 38,-8 36,0 Z\" fill=\"" + accent_c + "\"/>"
    }
    _ => ()
  }
  svg = svg + "<rect x=\"7\" y=\"0\" width=\"50\" height=\"" + fi(head_h) + "\" rx=\"" + fi(rx) + "\" fill=\"" + head_c + "\"/>"
  // 眼
  let eye_y = head_h * 0.42
  match s.eye_style {
    1 =>
      svg = svg + "<circle cx=\"23\" cy=\"" + fi(eye_y) + "\" r=\"4.5\" fill=\"#ebf1f7\"/><circle cx=\"41\" cy=\"" + fi(eye_y) + "\" r=\"4.5\" fill=\"#ebf1f7\"/><circle cx=\"24.5\" cy=\"" + fi(eye_y + 1.0) + "\" r=\"2.2\" fill=\"#141822\"/><circle cx=\"42.5\" cy=\"" + fi(eye_y + 1.0) + "\" r=\"2.2\" fill=\"#141822\"/>"
    2 =>
      svg = svg + "<ellipse cx=\"23\" cy=\"" + fi(eye_y) + "\" rx=\"5.5\" ry=\"6\" fill=\"#ebf1f7\"/><ellipse cx=\"41\" cy=\"" + fi(eye_y) + "\" rx=\"5.5\" ry=\"6\" fill=\"#ebf1f7\"/><circle cx=\"24.5\" cy=\"" + fi(eye_y + 1.5) + "\" r=\"2.6\" fill=\"#141822\"/><circle cx=\"42.5\" cy=\"" + fi(eye_y + 1.5) + "\" r=\"2.6\" fill=\"#141822\"/><circle cx=\"25.5\" cy=\"" + fi(eye_y - 1.0) + "\" r=\"0.9\" fill=\"#fff\"/><circle cx=\"43.5\" cy=\"" + fi(eye_y - 1.0) + "\" r=\"0.9\" fill=\"#fff\"/>"
    3 =>
      svg = svg + "<rect x=\"19\" y=\"" + fi(eye_y) + "\" width=\"9\" height=\"3\" rx=\"1.5\" fill=\"#141822\"/><rect x=\"37\" y=\"" + fi(eye_y) + "\" width=\"9\" height=\"3\" rx=\"1.5\" fill=\"#141822\"/>"
    _ =>
      svg = svg + "<rect x=\"19.5\" y=\"" + fi(eye_y - 2.5) + "\" width=\"7\" height=\"6\" rx=\"2\" fill=\"#ebf1f7\"/><rect x=\"37.5\" y=\"" + fi(eye_y - 2.5) + "\" width=\"7\" height=\"6\" rx=\"2\" fill=\"#ebf1f7\"/><rect x=\"21.5\" y=\"" + fi(eye_y - 1.0) + "\" width=\"3\" height=\"3.4\" rx=\"1\" fill=\"#141822\"/><rect x=\"39.5\" y=\"" + fi(eye_y - 1.0) + "\" width=\"3\" height=\"3.4\" rx=\"1\" fill=\"#141822\"/>"
  }
  // 腮红
  if s.blush {
    svg = svg + "<ellipse cx=\"16\" cy=\"" + fi(eye_y + 5.0) + "\" rx=\"3.4\" ry=\"2.2\" fill=\"" + accent_c + "\" opacity=\"0.55\"/><ellipse cx=\"48\" cy=\"" + fi(eye_y + 5.0) + "\" rx=\"3.4\" ry=\"2.2\" fill=\"" + accent_c + "\" opacity=\"0.55\"/>"
  }
  // 嘴
  match s.mouth {
    1 => svg = svg + "<rect x=\"27\" y=\"" + fi(eye_y + 7.0) + "\" width=\"10\" height=\"2\" rx=\"1\" fill=\"#141822\"/>"
    2 => svg = svg + "<rect x=\"30\" y=\"" + fi(eye_y + 7.0) + "\" width=\"4\" height=\"2.4\" rx=\"1.2\" fill=\"#141822\"/>"
    3 => svg = svg + "<path d=\"M26," + fi(eye_y + 6.0) + " q3,3 6,0 q3,3 6,0\" stroke=\"#141822\" stroke-width=\"1.6\" fill=\"none\" stroke-linecap=\"round\"/>"
    _ => ()
  }
  svg = svg + "</g>"
  svg = svg + "</g>"
  svg = svg + "</svg>"
  svg
}
