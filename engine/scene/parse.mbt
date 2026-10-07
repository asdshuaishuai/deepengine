// scene —— .mbg.md 解析器：文本 → GameSpec（→ kernel Game）。
//
// 失败语义：解析错误收集为 errors 数组返回（不崩——不崩谓词 P0 的解析层形态），
// 调用方决定拒绝（verify/run 直接报错退出）。

///|
/// 解析产物：游戏规格 + 声明探针 + 错误清单
pub(all) struct GameSpec {
  mut title : String
  mut w : Int
  mut h : Int
  mut bg : (Int, Int, Int)
  mut gravity : Double
  mut jump_v : Double
  mut speed : Double
  mut player : @kernel.Rect
  mut player_color : (Int, Int, Int)
  mut player_seed : Int // 种子化角色（视觉层；不进 serialize——不影响玩法指纹）
  solids : Array[@kernel.Solid]
  coins : Array[@kernel.Coin]
  spikes : Array[@kernel.Rect]
  mut goal : @kernel.Rect?
  probes : Array[@kernel.Probe]
  // grid_logic 族（mode == "grid"）
  mut mode : String // "physics" | "grid"
  mut g_cols : Int
  mut g_rows : Int
  mut g_cell : Int
  mut g_px : Int
  mut g_py : Int
  g_walls : Array[(Int, Int)]
  g_boxes : Array[(Int, Int)]
  g_goals : Array[(Int, Int)]
}

///|
pub(all) struct ParseResult {
  spec : GameSpec? // None = 有致命错（无 canvas/player）
  errors : Array[String] // P0：行级错误，全部收集不中断
  warnings : Array[String]
}

///|
pub fn default_spec() -> GameSpec {
  {
    title: "untitled",
    w: 960,
    h: 540,
    bg: (11, 13, 19),
    gravity: 2000.0,
    jump_v: -700.0,
    speed: 260.0,
    player: { x: 80.0, y: 460.0, w: 28.0, h: 40.0 },
    player_color: (74, 158, 255),
    player_seed: 0,
    solids: [],
    coins: [],
    spikes: [],
    goal: None,
    probes: [],
    mode: "physics",
    g_cols: 10,
    g_rows: 8,
    g_cell: 48,
    g_px: 1,
    g_py: 1,
    g_walls: [],
    g_boxes: [],
    g_goals: [],
  }
}

///|
/// GameSpec → kernel Game（构建可步进的世界）。
///
// 纯构建：深拷贝实体数组——spec 是持久事实源，游戏会就地改数组
// （coins.taken / boxes[idx]），共享引用会让"玩过的状态"污染
// 后续 build/verify（wasm 持久 spec 面暴露的真实别名 bug）。
pub fn GameSpec::build(self : GameSpec) -> @kernel.Game {
  let solids : Array[@kernel.Solid] = []
  for s in self.solids {
    solids.push({ rect: s.rect, color: s.color })
  }
  let coins : Array[@kernel.Coin] = []
  for c in self.coins {
    coins.push({ id: c.id, rect: c.rect, color: c.color, taken: c.taken })
  }
  let spikes : Array[@kernel.Rect] = []
  for sp in self.spikes {
    spikes.push(sp)
  }
  @kernel.Game::new(
    self.w,
    self.h,
    self.bg,
    self.gravity,
    self.jump_v,
    self.speed,
    self.player,
    self.player_color,
    self.player_seed,
    solids,
    coins,
    spikes,
    self.goal,
  )
}

///|
/// grid 族构建（纯构建：同 build 的深拷贝纪律）
pub fn GameSpec::build_grid(self : GameSpec) -> @kernel.GridGame {
  let walls : Array[(Int, Int)] = []
  for w in self.g_walls {
    walls.push(w)
  }
  let boxes : Array[(Int, Int)] = []
  for b in self.g_boxes {
    boxes.push(b)
  }
  let goals : Array[(Int, Int)] = []
  for g in self.g_goals {
    goals.push(g)
  }
  @kernel.GridGame::new(self.g_cols, self.g_rows, self.player_seed, self.g_px, self.g_py, walls, boxes, goals)
}

// ---------------- 基础工具 ----------------

///|
fn parse_int(text : String) -> Int? {
  let t = text.trim().to_owned()
  if t.length() == 0 {
    return None
  }
  let mut value = 0
  let mut i = 0
  let neg = t.substring(start=0, end=1) == "-"
  if neg {
    i = 1
  }
  while i < t.length() {
    let c = t.substring(start=i, end=i + 1)
    let d = "0123456789".find(c)
    match d {
      None => return None
      Some(v) => value = value * 10 + v
    }
    i = i + 1
  }
  Some(if neg {
    -value
  } else {
    value
  })
}

///|
/// 浮点解析（支持负号与小数点）
fn parse_double(text : String) -> Double? {
  let t = text.trim().to_owned()
  if t.length() == 0 {
    return None
  }
  let mut i = 0
  let neg = t.substring(start=0, end=1) == "-"
  if neg {
    i = 1
  }
  let mut int_part = 0.0
  let mut frac = 0.0
  let mut frac_div = 1.0
  let mut seen_dot = false
  let mut seen_digit = false
  while i < t.length() {
    let c = t.substring(start=i, end=i + 1)
    if c == "." {
      if seen_dot {
        return None
      }
      seen_dot = true
    } else {
      let d = "0123456789".find(c)
      match d {
        None => return None
        Some(v) => {
          seen_digit = true
          if seen_dot {
            frac_div = frac_div * 10.0
            frac = frac + v.to_double() / frac_div
          } else {
            int_part = int_part * 10.0 + v.to_double()
          }
        }
      }
    }
    i = i + 1
  }
  if not(seen_digit) {
    return None
  }
  let v = int_part + frac
  Some(if neg {
    -v
  } else {
    v
  })
}

///|
/// #rrggbb / #rgb → (r,g,b)
fn parse_color(tok : String) -> (Int, Int, Int)? {
  let t = tok.trim().to_owned()
  if t.length() == 7 && t.substring(start=0, end=1) == "#" {
    let r = hex2(t.substring(start=1, end=3))
    let g = hex2(t.substring(start=3, end=5))
    let b = hex2(t.substring(start=5, end=7))
    match (r, g, b) {
      (Some(r), Some(g), Some(b)) => Some((r, g, b))
      _ => None
    }
  } else {
    None
  }
}

///|
fn hex2(h : String) -> Int? {
  // 兼容大小写：find 的索引即数值（A-F 映射到 10-15）
  let digits = "0123456789abcdefABCDEF"
  let hi = digits.find(h.substring(start=0, end=1))
  let lo = digits.find(h.substring(start=1, end=2))
  // 大写时索引偏移 16，需折回
  let fix = fn(v : Int?) -> Int? {
    match v {
      // 大写字母从索引 16 起（A=16…F=21），值应折回 10…15
      Some(x) => Some(if x >= 16 { x - 6 } else { x })
      None => None
    }
  }
  let hi = fix(hi)
  let lo = fix(lo)
  match (hi, lo) {
    (Some(a), Some(b)) => Some(a * 16 + b)
    _ => None
  }
}

///|
/// "k:v" 键值对抽取（大小写敏感的 key）
fn kv(args : Array[StringView], key : String) -> String? {
  let prefix = key + ":"
  for a in args {
    let t = a.trim().to_owned()
    if t.length() > prefix.length() && t.substring(start=0, end=prefix.length()) == prefix {
      return Some(t.substring(start=prefix.length()).trim().to_owned())
    }
  }
  None
}

///|
fn kv_double(args : Array[StringView], key : String) -> Double? {
  match kv(args, key) {
    Some(v) => parse_double(v)
    None => None
  }
}

///|
fn kv_int(args : Array[StringView], key : String) -> Int? {
  match kv(args, key) {
    Some(v) => parse_int(v)
    None => None
  }
}

///|
/// 引号内容抽取（probe 的 script:"..." / expect:"..."）
fn quoted(line : String, key : String) -> String? {
  // 找 key:" 开头，再找闭合引号
  let marker = key + ":\""
  let pos = line.find(marker)
  match pos {
    None => None
    Some(i) => {
      let rest = line.substring(start=i + marker.length())
      let end = rest.find("\"")
      match end {
        None => None
        Some(e) => Some(rest.substring(start=0, end=e))
      }
    }
  }
}

///|
/// 消费一行 ASCII 地图：# 墙 p 玩家 b 箱 g 目标 . 地板（其余忽略）
fn consume_level_row(
  spec : GameSpec,
  row_str : String,
  row : Int,
  errors : Array[String]
) -> Unit {
  let mut ci = 0
  for ch in row_str {
    let c = ch.to_string()
    if c == "#" {
      spec.g_walls.push((ci, row))
    } else if c == "p" {
      spec.g_px = ci
      spec.g_py = row
    } else if c == "b" {
      spec.g_boxes.push((ci, row))
    } else if c == "g" {
      spec.g_goals.push((ci, row))
    }
    ci = ci + 1
  }
  if ci != spec.g_cols {
    errors.push("level 行 \{row + 1} 宽度 \{ci} != 声明 cols \{spec.g_cols}")
  }
}

// ---------------- 主解析 ----------------

///|
/// 解析 .mbg.md 全文：只认 ```mbg fence 内的 ops
pub fn parse(source : String) -> ParseResult {
  let errors : Array[String] = []
  let warnings : Array[String] = []
  let spec = default_spec()
  let mut coin_id = 0
  let mut in_fence = false
  // level ASCII 地图收集状态（grid 族）
  let mut pending_rows = 0
  let mut next_row = 0
  let lines : Array[StringView] = source.split("\n").iter().collect()
  let mut line_no = 0

  for raw in lines {
    line_no = line_no + 1
    let line = raw.trim().to_owned()
    // fence 跟踪：```mbg 开，``` 关
    if line.length() >= 3 && line.substring(start=0, end=3) == "```" {
      in_fence = !in_fence
      continue
    }
    if !in_fence {
      continue
    }
    if line.length() == 0 {
      continue // 地图块内空行容忍（不消费行数）
    }
    // level 地图行消费——必须在注释检查之前：地图行的 '#' 是墙字符不是注释
    if pending_rows > 0 {
      consume_level_row(spec, line, next_row, errors)
      next_row = next_row + 1
      pending_rows = pending_rows - 1
      continue
    }
    if line.substring(start=0, end=1) == "#" {
      continue // 注释 op（仅 fence 内非地图上下文）
    }
    // 切词
    let words : Array[StringView] = line.split(" ").iter().collect()
    let op = words[0].trim().to_owned()
    // args = 尾部（probe 的引号值含空格，整行特殊处理）
    if op == "probe" {
      let name = if words.length() > 1 {
        words[1].trim().to_owned()
      } else {
        "probe\{line_no}"
      }
      let script = quoted(line, "script")
      let expect = quoted(line, "expect")
      match (script, expect) {
        (Some(s), Some(e)) =>
          spec.probes.push({ name: name, script: s, expect: e })
        _ => errors.push("line \{line_no}: probe 需要 script:\"…\" 与 expect:\"…\"")
      }
      continue
    }
    let args : Array[StringView] = []
    let mut wi = 1
    while wi < words.length() {
      args.push(words[wi])
      wi = wi + 1
    }

    match op {
      "mode" => {
        let m = if words.length() > 1 {
          words[1].trim().to_owned()
        } else {
          ""
        }
        if m == "grid" || m == "physics" {
          spec.mode = m
        } else {
          errors.push("line \{line_no}: mode 只支持 grid|physics，收到 '\{m}'")
        }
      }
      "level" => {
        let cols = if words.length() > 1 {
          parse_int(words[1].trim().to_owned())
        } else {
          None
        }
        let rows = if words.length() > 2 {
          parse_int(words[2].trim().to_owned())
        } else {
          None
        }
        match (cols, rows) {
          (Some(c), Some(r)) => {
            spec.g_cols = c
            spec.g_rows = r
            pending_rows = r
            next_row = 0
          }
          _ => errors.push("line \{line_no}: level 需要 <cols> <rows>")
        }
        match kv_int(args, "cell") {
          Some(v) => spec.g_cell = v
          None => ()
        }
      }
      "canvas" => {
        let w = if words.length() > 1 {
          parse_int(words[1].trim().to_owned())
        } else {
          None
        }
        let h = if words.length() > 2 {
          parse_int(words[2].trim().to_owned())
        } else {
          None
        }
        match (w, h) {
          (Some(w), Some(h)) => {
            spec.w = w
            spec.h = h
          }
          _ => errors.push("line \{line_no}: canvas 需要 <w> <h>")
        }
        match kv(args, "bg") {
          Some(c) =>
            match parse_color(c) {
              Some(rgb) => spec.bg = rgb
              None => errors.push("line \{line_no}: canvas bg 颜色非法 \{c}")
            }
          None => ()
        }
      }
      "physics" => {
        match kv_double(args, "gravity") {
          Some(v) => spec.gravity = v
          None => errors.push("line \{line_no}: physics 需要 gravity:<数值>")
        }
        match kv_double(args, "jump") {
          Some(v) => spec.jump_v = v
          None => errors.push("line \{line_no}: physics 需要 jump:<数值>")
        }
        match kv_double(args, "speed") {
          Some(v) => spec.speed = v
          None => errors.push("line \{line_no}: physics 需要 speed:<数值>")
        }
      }
      "player" => {
        // 省略即继承：x/y/w/h/seed 全部可选，缺省沿用默认（blueprint §2.1）
        let x = match kv_double(args, "x") {
          Some(v) => v
          None => spec.player.x
        }
        let y = match kv_double(args, "y") {
          Some(v) => v
          None => spec.player.y
        }
        spec.player = {
          x: x,
          y: y,
          w: match kv_double(args, "w") {
            Some(v) => v
            None => spec.player.w
          },
          h: match kv_double(args, "h") {
            Some(v) => v
            None => spec.player.h
          },
        }
        match kv(args, "color") {
          Some(c) =>
            match parse_color(c) {
              Some(rgb) => spec.player_color = rgb
              None => errors.push("line \{line_no}: player 颜色非法 \{c}")
            }
          None => ()
        }
        match kv_int(args, "seed") {
          Some(v) => spec.player_seed = v
          None => ()
        }
      }
      "platform" => {
        let x = kv_double(args, "x")
        let y = kv_double(args, "y")
        let w = kv_double(args, "w")
        let h = kv_double(args, "h")
        match (x, y, w, h) {
          (Some(x), Some(y), Some(w), Some(h)) =>
            spec.solids.push({
              rect: { x: x, y: y, w: w, h: h },
              color: match kv(args, "color") {
                Some(c) =>
                  match parse_color(c) {
                    Some(rgb) => rgb
                    None => {
                      errors.push("line \{line_no}: platform 颜色非法 \{c}")
                      (35, 42, 61)
                    }
                  }
                None => (35, 42, 61)
              },
            })
          _ => errors.push("line \{line_no}: platform 需要 x: y: w: h:")
        }
      }
      "coin" => {
        let x = kv_double(args, "x")
        let y = kv_double(args, "y")
        match (x, y) {
          (Some(x), Some(y)) => {
            let size = match kv_double(args, "w") {
              Some(v) => v
              None => 20.0
            }
            spec.coins.push({
              id: coin_id,
              rect: { x: x, y: y, w: size, h: size },
              color: match kv(args, "color") {
                Some(c) =>
                  match parse_color(c) {
                    Some(rgb) => rgb
                    None => (245, 165, 36)
                  }
                None => (245, 165, 36)
              },
              taken: false,
            })
            coin_id = coin_id + 1
          }
          _ => errors.push("line \{line_no}: coin 需要 x: y:")
        }
      }
      "spike" => {
        let x = kv_double(args, "x")
        let y = kv_double(args, "y")
        let w = kv_double(args, "w")
        match (x, y, w) {
          (Some(x), Some(y), Some(w)) =>
            spec.spikes.push({
              x: x,
              y: y,
              w: w,
              h: match kv_double(args, "h") {
                Some(v) => v
                None => 16.0
              },
            })
          _ => errors.push("line \{line_no}: spike 需要 x: y: w:")
        }
      }
      "goal" => {
        let x = kv_double(args, "x")
        let y = kv_double(args, "y")
        let w = kv_double(args, "w")
        let h = kv_double(args, "h")
        match (x, y, w, h) {
          (Some(x), Some(y), Some(w), Some(h)) =>
            spec.goal = Some({ x: x, y: y, w: w, h: h })
          _ => errors.push("line \{line_no}: goal 需要 x: y: w: h:")
        }
      }
      _ => warnings.push("line \{line_no}: 未知 op '\{op}'（已忽略）")
    }
  }

  if pending_rows > 0 {
    errors.push("level 声明了 \{spec.g_rows} 行但文件在 \{next_row} 行后结束")
  }
  if spec.mode == "physics" && spec.solids.length() == 0 {
    errors.push("关卡无任何 platform——玩家会坠落判死")
  }
  if spec.mode == "grid" && spec.g_walls.length() == 0 {
    errors.push("grid 模式缺少 level 地图")
  }
  // 目标缺失警告按模式判断：physics 用 goal op；grid 用地图里的 g 目标格
  if spec.mode == "grid" {
    if spec.g_goals.length() == 0 {
      warnings.push("grid 地图无 g 目标格——won 不可达")
    }
  } else {
    match spec.goal {
      None => warnings.push("关卡未声明 goal——won 不可达")
      Some(_) => ()
    }
  }
  let final_spec : GameSpec? = if errors.length() == 0 {
    Some(spec)
  } else {
    None
  }
  { spec: final_spec, errors: errors, warnings: warnings }
}
