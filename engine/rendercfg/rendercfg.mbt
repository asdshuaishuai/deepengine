// rendercfg —— 渲染配置契约：把指引的 render/assembly 声明变成可消费的值。
//
// v1.3 的缺口：指引解析出了 render 层与 hud 字段，但渲染层仍在读硬编码常量
//（bevel 28 / spin 0.18 / teeth 3 / flag 26）。那意味着"指引说了不算"——
// agent 改了 render 块却看不到任何变化。本文件把声明落成值，render.mbt 只读这里。
//
// 纪律：
//   ① 每一项都有**默认值**，缺省即当前视觉（老项目换到新入口画面不变）；
//   ② 参数名与指引 render 块里的 key 一一对应，未知 key → 警告不报错；
//   ③ 本包零渲染依赖（只在数据层），可被 moon test 直接测。

///|
pub(all) struct RenderConfig {
  // 角色（hero）
  mut hero_mode : String // "procedural"（程序化生成；其他值目前无实现 → 警告）
  mut hero_seed : Int // 角色种子（-1 = 未指定，沿用世界里的值）
  // 层参数
  mut platform_bevel : Int // 平台顶亮边的**亮度增量**（+0..+255，钳到 255）
  mut platform_edge : Double // 平台顶亮边的**高度**（px，0 = 关闭亮边）
  mut coin_spin : Double // 金币自转频率（rad/帧）
  mut spike_teeth : Int // 尖刺齿数（每 w 宽度的齿）
  mut goal_flag : Double // 终点旗杆高度（px）
  mut grid_grip : Int // grid 墙顶亮边高度（px）
  // 视图级特效开关
  mut dust : Bool // 落地扬尘
  mut hero_rig : Bool // 程序化小人 rig（关闭则画朴素方块）
  errors : Array[String]
  warnings : Array[String]
}

///|
fn rc_default() -> RenderConfig {
  {
    hero_mode: "procedural",
    hero_seed: -1,
    // 历史视觉：顶边亮度 +28，高度 3px
    platform_bevel: 28,
    platform_edge: 3.0,
    coin_spin: 0.18,
    spike_teeth: 3,
    goal_flag: 26.0,
    grid_grip: 3,
    dust: true,
    hero_rig: true,
    errors: [],
    warnings: [],
  }
}

///|
/// 已知 render 参数名（自省：写了不认识的 key 要警告，不是静默忽略）
fn known_key(k : String) -> Bool {
  k == "bevel" ||
  k == "edge" ||
  k == "spin" ||
  k == "teeth" ||
  k == "flag" ||
  k == "grip" ||
  k == "dust" ||
  k == "rig" ||
  k == "cell" ||
  k == "on_goal" ||
  k == "show" ||
  k == "style" ||
  k == "seed"
}

///|
/// 默认配置（供渲染层初始化；缺省即历史视觉）
pub fn default_config() -> RenderConfig {
  rc_default()
}

///|
/// 判定一个 token 是否是合法数值（含负号与小数点）
///
/// 门禁必须看**原始字符串**而不是解析后的值——`parse_int_or("-5")` 会因
/// 不支持负号而回退默认值，于是"负数"和"写了乱码"变成同一件事，门禁失效。
/// 这里单独判定，把两者区分开。
fn is_numeric(tok : String) -> Bool {
  let t = tok.trim().to_owned()
  if t.length() == 0 {
    return false
  }
  let mut i = 0
  if t.substring(start=0, end=1) == "-" {
    i = 1
  }
  let mut seen = false
  let mut dot = false
  while i < t.length() {
    let c = t.substring(start=i, end=i + 1)
    if c == "." && !dot {
      dot = true
    } else {
      match "0123456789".find(c) {
        Some(_) => seen = true
        None => return false
      }
    }
    i = i + 1
  }
  seen
}

///|
/// 负值检查：合法数值但 < 0 → 报错（画错就必须拦，不是静默回退默认）
fn check_nonneg(v : Double, key : String, cfg : RenderConfig) -> Unit {
  if v < 0.0 {
    cfg.errors.push("render: \{key} 不可为负（收到 \{v}）")
  }
}

///|
/// 带符号整数解析（调用方须先用 is_numeric 确认是数值）
fn parse_int_signed(tok : String) -> Int {
  let t = tok.trim().to_owned()
  let neg = t.length() > 0 && t.substring(start=0, end=1) == "-"
  let start = if neg { 1 } else { 0 }
  let mut v = 0
  let mut i = start
  while i < t.length() {
    match "0123456789".find(t.substring(start=i, end=i + 1)) {
      Some(d) => v = v * 10 + d
      None => break
    }
    i = i + 1
  }
  if neg {
    -v
  } else {
    v
  }
}

///|
fn parse_int_or(tok : String, fallback : Int) -> Int {
  let t = tok.trim().to_owned()
  let mut v = 0
  let mut ok = t.length() > 0
  for ch in t {
    let d = "0123456789".find(ch.to_string())
    match d {
      Some(x) => v = v * 10 + x
      None => {
        ok = false
        break
      }
    }
  }
  if ok {
    v
  } else {
    fallback
  }
}

///|
fn parse_double_or(tok : String, fallback : Double) -> Double {
  let t = tok.trim().to_owned()
  if t.length() == 0 {
    return fallback
  }
  let mut i = 0
  let neg = t.substring(start=0, end=1) == "-"
  if neg {
    i = 1
  }
  let mut int_part = 0.0
  let mut frac = 0.0
  let mut div = 1.0
  let mut dot = false
  let mut seen = false
  while i < t.length() {
    let c = t.substring(start=i, end=i + 1)
    if c == "." && !dot {
      dot = true
    } else {
      match "0123456789".find(c) {
        Some(v) => {
          seen = true
          if dot {
            div = div * 10.0
            frac = frac + v.to_double() / div
          } else {
            int_part = int_part * 10.0 + v.to_double()
          }
        }
        None => return fallback
      }
    }
    i = i + 1
  }
  if !seen {
    return fallback
  }
  let v = if neg { -(int_part + frac) } else { int_part + frac }
  v
}

///|
fn parse_bool_or(tok : String, fallback : Bool) -> Bool {
  let t = tok.trim().to_owned()
  if t == "on" || t == "true" || t == "1" || t == "yes" {
    true
  } else if t == "off" || t == "false" || t == "0" || t == "no" {
    false
  } else {
    fallback
  }
}

///|
/// 层名 → 该层会消费哪些 key（用于未知 key 定位到层）
fn layer_of(k : String) -> String {
  if k == "bevel" || k == "style" || k == "edge" {
    "platforms"
  } else if k == "spin" {
    "coins"
  } else if k == "teeth" {
    "spikes"
  } else if k == "flag" {
    "goal"
  } else if k == "grip" || k == "cell" {
    "grid"
  } else if k == "dust" || k == "rig" || k == "seed" {
    "hero"
  } else {
    "?"
  }
}

///|
/// 指引的 render 层 → RenderConfig
///
/// `world_seed` 是世界里的 player_seed：指引写 `seed: player.seed` 时
/// 表示"种子来自关卡数据"，此时不覆盖（由调用方把 world_seed 填进来）。
pub fn from_guide(layers : Array[@scene.RenderLayer], hero_mode : String, hero_seed_path : String, world_seed : Int) -> RenderConfig {
  let cfg = rc_default()
  cfg.hero_mode = hero_mode
  // 种子：路径声明（`seed: player.seed`）表示"值来自关卡数据"。
  // 这里在层循环**之外**处理——它依赖 hero 层存在才走到会让
  // "只写 seed 不写 rig/dust" 的常见写法静默失效。
  if hero_seed_path.length() > 0 {
    cfg.hero_seed = world_seed
  }
  for l in layers {
    for p in l.params {
      let k = p.0
      let v = p.1
      if !known_key(k) {
        cfg.warnings.push("render 层 '\{l.name}' 的参数 '\{k}' 未被渲染层消费（已忽略）")
        continue
      }
      match k {
        "bevel" =>
          if is_numeric(v) {
            cfg.platform_bevel = parse_int_signed(v)
            check_nonneg(cfg.platform_bevel.to_double(), "platform bevel", cfg)
          } else {
            cfg.warnings.push("render: platform bevel '\{v}' 不是数值（沿用默认 \{cfg.platform_bevel}）")
          }
        "edge" =>
          if is_numeric(v) {
            cfg.platform_edge = parse_double_or(v, cfg.platform_edge)
            check_nonneg(cfg.platform_edge, "platform edge", cfg)
          } else {
            cfg.warnings.push("render: platform edge '\{v}' 不是数值（沿用默认）")
          }
        "spin" =>
          if is_numeric(v) {
            cfg.coin_spin = parse_double_or(v, cfg.coin_spin)
            check_nonneg(cfg.coin_spin, "coin spin", cfg)
            if cfg.coin_spin < 0.0 {
              cfg.coin_spin = 0.0 // 钳零：报错了也要给出可渲染的值
            }
          } else {
            cfg.warnings.push("render: coin spin '\{v}' 不是数值（沿用默认）")
          }
        "teeth" => {
          let n = parse_int_or(v, cfg.spike_teeth)
          // 齿数为 0 会让绘制循环退化为无齿——钳到合法区间
          cfg.spike_teeth = if n < 1 {
            cfg.warnings.push("render: spikes teeth=\{n} < 1，已钳到 1")
            1
          } else {
            n
          }
        }
        "flag" =>
          if is_numeric(v) {
            cfg.goal_flag = parse_double_or(v, cfg.goal_flag)
            check_nonneg(cfg.goal_flag, "goal flag", cfg)
          } else {
            cfg.warnings.push("render: goal flag '\{v}' 不是数值（沿用默认）")
          }
        "grip" =>
          if is_numeric(v) {
            cfg.grid_grip = parse_int_signed(v)
            check_nonneg(cfg.grid_grip.to_double(), "grid grip", cfg)
          } else {
            cfg.warnings.push("render: grid grip '\{v}' 不是数值（沿用默认）")
          }
        "dust" => cfg.dust = parse_bool_or(v, cfg.dust)
        "rig" => cfg.hero_rig = parse_bool_or(v, cfg.hero_rig)
        "seed" =>
          // `seed: player.seed` 是路径声明，值由 world_seed 提供
          if hero_seed_path.length() > 0 {
            cfg.hero_seed = world_seed
          } else {
            cfg.hero_seed = parse_int_or(v, world_seed)
          }
        _ => ()
      }
    }
  }
  // 渲染契约门禁：值域非法已在各参数解析处就地报错（基于原始字符串判定，
// 见 is_numeric 的理由）；这里只补跨参数的一致性检查。
  if cfg.goal_flag < 0.0 {
    cfg.goal_flag = 0.0
  }
  if cfg.hero_mode != "procedural" {
    cfg.warnings.push("render: hero mode '\{cfg.hero_mode}' 未实现（当前仅 procedural），按 procedural 渲染")
  }
  cfg
}

// ---------------- HUD 字段契约 ----------------

///|
/// HUD 字段：指引 assembly 块声明"显示哪些可观测值"，这里把它切成有序字段表。
///
/// 字段名与 kernel 的 runtime_value key 同源（physics 族与 grid 族各有其集）。
/// 未列出的字段 → 警告而非报错（探针可扩展 runtimeValue，HUD 不该拦住内容）。
pub(all) struct HudConfig {
  fields : Array[String]
  warnings : Array[String]
}

///|
/// 默认 HUD（未声明时的历史字段集）
pub fn default_hud() -> HudConfig {
  { fields: ["state", "coins", "frame", "x", "y"], warnings: [] }
}

///|
fn known_hud_field(f : String, grid : Bool) -> Bool {
  if f == "state" || f == "x" || f == "y" {
    true
  } else if grid {
    f == "moves" || f == "boxes" || f == "boxes_on" || f == "pos"
  } else {
    f == "coins" || f == "frame" || f == "gx" || f == "gy"
  }
}

///|
pub fn hud_from(text : String, grid : Bool) -> HudConfig {
  let out : Array[String] = []
  let warns : Array[String] = []
  let toks : Array[StringView] = text.split(" ").iter().collect()
  for tok in toks {
    let f = tok.trim().to_owned()
    if f.length() == 0 {
      continue
    }
    if !known_hud_field(f, grid) {
      warns.push("assembly: HUD 字段 '\{f}' 未被渲染层消费（已忽略）")
      continue
    }
    out.push(f)
  }
  { fields: out, warnings: warns }
}

///|
/// HUD 字段 → 显示文本（physics 族）
pub fn hud_text_physics(fields : Array[String], g : @kernel.Game) -> String {
  let mut s = ""
  let mut i = 0
  for f in fields {
    if i > 0 {
      s = s + "  "
    }
    let v = match f {
      "state" => g.state
      "coins" => "\{g.coins_taken}/\{g.coins.length()}"
      "frame" => g.frame.to_string()
      "x" => g.player.x.to_int().to_string()
      "y" => g.player.y.to_int().to_string()
      "gx" => g.player.grounded.to_string()
      "gy" => g.player.coyote.to_string()
      _ => ""
    }
    s = s + f + ":" + v
    i = i + 1
  }
  s
}

///|
/// HUD 字段 → 显示文本（grid 族）
pub fn hud_text_grid(fields : Array[String], g : @kernel.GridGame) -> String {
  let mut s = ""
  let mut i = 0
  for f in fields {
    if i > 0 {
      s = s + "  "
    }
    let v = match f {
      "state" => g.state
      "moves" => g.moves.to_string()
      "boxes" => "\{g.boxes.length()}"
      "boxes_on" => @kernel.grid_boxes_on(g).to_string()
      "pos" => "(\{g.px},\{g.py})"
      "x" => g.px.to_string()
      "y" => g.py.to_string()
      _ => ""
    }
    s = s + f + ":" + v
    i = i + 1
  }
  s
}