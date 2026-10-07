// assemble —— 装配层：GuideSpec（指引） + 内容源 → GameSpec（可步进的世界）。
//
// 这是 v1.3 的中枢。指引文件只说"有哪些东西、怎么解析"，具体数据由
// source 声明的内容源提供——两者在这里按 parser 名分派、合并、校验。
//
// 分派表（parser 名 → 处理器）：
//   json_level    level.json      —— 关卡几何（画布/物理/实体/grid 地图）
//   json_probes   probes.json     —— 行为探针声明
//   inline        内联文本        —— 兼容旧 .mbg.md 单文件入口
//   empty         空源            —— 显式"此源不提供数据"
//   runtime       运行时 API      —— 内容在进程内生成，此处只占位
//
// 纪律（DECLARATION.md「无 workaround 重复」）：inline 与 json_level 最终
// 汇入同一个 GameSpec 结构，没有两套世界构建路径。

///|
/// 内容源提供的载荷（parser 的输出）
pub(all) enum Payload {
  Level(GameSpec) // 关卡几何（部分字段可被后续源覆盖）
  Probes(Array[@kernel.Probe])
  Empty
  Runtime(String) // 仅记录名字：内容由运行时 spawn API 生成
}

///|
/// 一次装配的产物 + 诊断
pub(all) struct Assembly {
  spec : GameSpec?
  errors : Array[String]
  warnings : Array[String]
  loaded : Array[String] // 实际载入的源（自审计：报告"哪些被证明了"）
  skipped : Array[String] // 声明了但缺失且 optional 的源
}

///|
fn base_spec(mode : String) -> GameSpec {
  let s = default_spec()
  s.mode = mode
  s
}

///|
/// 把两个 Level 载荷合并到同一 spec（后者覆盖非默认值；实体数组拼接）
fn merge_level(dst : GameSpec, src : GameSpec) -> Unit {
  // 标量：src 非默认值才覆盖（默认 spec 的默认值即"未声明"）
  if src.w != default_spec().w {
    dst.w = src.w
  }
  if src.h != default_spec().h {
    dst.h = src.h
  }
  if src.bg != default_spec().bg {
    dst.bg = src.bg
  }
  if src.gravity != default_spec().gravity {
    dst.gravity = src.gravity
  }
  if src.jump_v != default_spec().jump_v {
    dst.jump_v = src.jump_v
  }
  if src.speed != default_spec().speed {
    dst.speed = src.speed
  }
  if rect_differs(src.player, default_spec().player) {
    dst.player = src.player
  }
  if src.player_color != default_spec().player_color {
    dst.player_color = src.player_color
  }
  if src.player_seed != 0 {
    dst.player_seed = src.player_seed
  }
  if src.goal is Some(_) {
    dst.goal = src.goal
  }
  for s in src.solids {
    dst.solids.push(s)
  }
  for c in src.coins {
    dst.coins.push(c)
  }
  for sp in src.spikes {
    dst.spikes.push(sp)
  }
  for w in src.g_walls {
    dst.g_walls.push(w)
  }
  for b in src.g_boxes {
    dst.g_boxes.push(b)
  }
  for g in src.g_goals {
    dst.g_goals.push(g)
  }
  if src.g_cols != default_spec().g_cols {
    dst.g_cols = src.g_cols
  }
  if src.g_rows != default_spec().g_rows {
    dst.g_rows = src.g_rows
  }
  if src.g_cell != default_spec().g_cell {
    dst.g_cell = src.g_cell
  }
  if src.g_px != default_spec().g_px {
    dst.g_px = src.g_px
  }
  if src.g_py != default_spec().g_py {
    dst.g_py = src.g_py
  }
}

// ---------------- level.json 解码 ----------------

///|
/// Rect 无 Eq trait（MoonBit 内核纪律：不为此加派生），手写字段比较
fn rect_differs(a : @kernel.Rect, b : @kernel.Rect) -> Bool {
  a.x != b.x || a.y != b.y || a.w != b.w || a.h != b.h
}

///|
fn num_field(obj : Json, key : String, errors : Array[String], where_ : String) -> Double? {
  match json_get(obj, key) {
    None => None
    Some(v) =>
      match json_as_num(v) {
        Some(n) => Some(n)
        None => {
          errors.push("level.json: \{where_}.\{key} 需要数值")
          None
        }
      }
  }
}

///|
fn color_field(obj : Json, key : String, fallback : (Int, Int, Int)) -> (Int, Int, Int) {
  match json_get(obj, key) {
    Some(v) =>
      match json_as_str(v) {
        Some(s) =>
          match parse_color(s) {
            Some(rgb) => rgb
            None => fallback
          }
        None => fallback
      }
    None => fallback
  }
}

///|
fn rect_of(obj : Json, errors : Array[String], where_ : String) -> @kernel.Rect? {
  let x = num_field(obj, "x", errors, where_)
  let y = num_field(obj, "y", errors, where_)
  let w = num_field(obj, "w", errors, where_)
  let h = num_field(obj, "h", errors, where_)
  match (x, y, w, h) {
    (Some(x), Some(y), Some(w), Some(h)) => Some({ x: x, y: y, w: w, h: h })
    _ => None
  }
}

///|
/// level.json → GameSpec（关卡几何）
pub fn decode_level(text : String, mode : String) -> (GameSpec, Array[String], Array[String]) {
  let errors : Array[String] = []
  let warnings : Array[String] = []
  let spec = base_spec(mode)
  let (parsed, jerrs) = parse_text(text)
  for e in jerrs {
    errors.push(e)
  }
  match parsed {
    None => return (spec, errors, warnings)
    Some(root) => {
      // 顶层可选 mode 覆盖（指引声明优先，但 level.json 显式写了就听 level.json 的）
      if mode == "" {
        match json_get(root, "mode") {
          Some(v) =>
            match json_as_str(v) {
              Some(m) => spec.mode = m
              None => ()
            }
          None => ()
        }
      }
      // canvas
      if json_get(root, "canvas") is Some(c) {
        match json_get(c, "w") {
          Some(v) =>
            match json_as_num(v) {
              Some(n) => spec.w = n.to_int()
              None => errors.push("level.json: canvas.w 需要数值")
            }
          None => ()
        }
        match json_get(c, "h") {
          Some(v) =>
            match json_as_num(v) {
              Some(n) => spec.h = n.to_int()
              None => errors.push("level.json: canvas.h 需要数值")
            }
          None => ()
        }
        spec.bg = color_field(c, "bg", default_spec().bg)
      }
      // physics
      if json_get(root, "physics") is Some(p) {
        match num_field(p, "gravity", errors, "physics") {
          Some(v) => spec.gravity = v
          None => ()
        }
        match num_field(p, "jump", errors, "physics") {
          Some(v) => spec.jump_v = v
          None => ()
        }
        match num_field(p, "speed", errors, "physics") {
          Some(v) => spec.speed = v
          None => ()
        }
      }
      // player（省略即继承）
      if json_get(root, "player") is Some(pl) {
        let d = default_spec().player
        let x = match num_field(pl, "x", errors, "player") {
          Some(v) => v
          None => d.x
        }
        let y = match num_field(pl, "y", errors, "player") {
          Some(v) => v
          None => d.y
        }
        let w = match num_field(pl, "w", errors, "player") {
          Some(v) => v
          None => d.w
        }
        let h = match num_field(pl, "h", errors, "player") {
          Some(v) => v
          None => d.h
        }
        spec.player = { x: x, y: y, w: w, h: h }
        spec.player_color = color_field(pl, "color", default_spec().player_color)
        match num_field(pl, "seed", errors, "player") {
          Some(v) => spec.player_seed = v.to_int()
          None => ()
        }
      }
      // platforms
      if json_get(root, "platforms") is Some(pv) {
        match json_as_arr(pv) {
          Some(items) => {
            let mut idx = 0
            for it in items {
              match rect_of(it, errors, "platforms[\{idx}]") {
                Some(r) => spec.solids.push({ rect: r, color: color_field(it, "color", (35, 42, 61)) })
                None => errors.push("level.json: platforms[\{idx}] 缺 x/y/w/h")
              }
              idx = idx + 1
            }
          }
          None => errors.push("level.json: platforms 需为数组")
        }
      }
      // coins
      if json_get(root, "coins") is Some(cv) {
        match json_as_arr(cv) {
          Some(items) => {
            let mut idx = 0
            for it in items {
              let x = num_field(it, "x", errors, "coins")
              let y = num_field(it, "y", errors, "coins")
              match (x, y) {
                (Some(x), Some(y)) => {
                  let w = match num_field(it, "w", errors, "coins") {
                    Some(v) => v
                    None => 20.0
                  }
                  let id = spec.coins.length()
                  spec.coins.push({
                    id: id,
                    rect: { x: x, y: y, w: w, h: w },
                    color: color_field(it, "color", (245, 165, 36)),
                    taken: false,
                  })
                }
                _ => errors.push("level.json: coins[\{idx}] 缺 x/y")
              }
              idx = idx + 1
            }
          }
          None => errors.push("level.json: coins 需为数组")
        }
      }
      // spikes
      if json_get(root, "spikes") is Some(sv) {
        match json_as_arr(sv) {
          Some(items) => {
            let mut idx = 0
            for it in items {
              let x = num_field(it, "x", errors, "spikes")
              let y = num_field(it, "y", errors, "spikes")
              let w = num_field(it, "w", errors, "spikes")
              match (x, y, w) {
                (Some(x), Some(y), Some(w)) => {
                  let h = match num_field(it, "h", errors, "spikes") {
                    Some(v) => v
                    None => 16.0
                  }
                  spec.spikes.push({ x: x, y: y, w: w, h: h })
                }
                _ => errors.push("level.json: spikes[\{idx}] 缺 x/y/w")
              }
              idx = idx + 1
            }
          }
          None => errors.push("level.json: spikes 需为数组")
        }
      }
      // goal
      if json_get(root, "goal") is Some(gv) {
        match rect_of(gv, errors, "goal") {
          Some(r) => spec.goal = Some(r)
          None => errors.push("level.json: goal 缺 x/y/w/h")
        }
      }
      // grid：level 声明 + ASCII 地图
      if json_get(root, "level") is Some(lv) {
        let cols = num_field(lv, "cols", errors, "level")
        let rows = num_field(lv, "rows", errors, "level")
        match (cols, rows) {
          (Some(c), Some(r)) => {
            spec.g_cols = c.to_int()
            spec.g_rows = r.to_int()
            match num_field(lv, "cell", errors, "level") {
              Some(v) => spec.g_cell = v.to_int()
              None => ()
            }
            match json_get(lv, "rows_map") {
              Some(rv) =>
                match json_as_arr(rv) {
                  Some(map_rows) => {
                    let mut ri = 0
                    for mr in map_rows {
                      match json_as_str(mr) {
                        Some(s) => {
                          consume_level_row(spec, s, ri, errors)
                          ri = ri + 1
                        }
                        None => errors.push("level.json: level.rows_map[\{ri}] 需为字符串")
                      }
                    }
                    if ri != spec.g_rows {
                      errors.push("level.json: level.rows_map 有 \{ri} 行，声明 rows=\{spec.g_rows}")
                    }
                  }
                  None => errors.push("level.json: level.rows_map 需为数组")
                }
              None => errors.push("level.json: grid 模式缺 level.rows_map")
            }
          }
          _ => errors.push("level.json: level 需 cols 与 rows")
        }
      }
    }
  }
  (spec, errors, warnings)
}

// ---------------- probes.json 解码 ----------------

///|
/// probes.json → Array[Probe]
pub fn decode_probes(text : String) -> (Array[@kernel.Probe], Array[String], Array[String]) {
  let errors : Array[String] = []
  let warnings : Array[String] = []
  let probes : Array[@kernel.Probe] = []
  let (parsed, jerrs) = parse_text(text)
  for e in jerrs {
    errors.push(e)
  }
  match parsed {
    None => ()
    Some(root) =>
      match json_get(root, "probes") {
        Some(pv) =>
          match json_as_arr(pv) {
            Some(items) => {
              let mut idx = 0
              for it in items {
                let name = match json_get(it, "name") {
                  Some(v) =>
                    match json_as_str(v) {
                      Some(s) => s
                      None => {
                        errors.push("probes.json: probes[\{idx}].name 需为字符串")
                        "probe\{idx}"
                      }
                    }
                  None => "probe\{idx}"
                }
                let script = match json_get(it, "script") {
                  Some(v) =>
                    match json_as_str(v) {
                      Some(s) => s
                      None => {
                        errors.push("probes.json: probes[\{idx}].script 需为字符串")
                        ""
                      }
                    }
                  None => {
                    errors.push("probes.json: probes[\{idx}] 缺 script")
                    ""
                  }
                }
                let expect = match json_get(it, "expect") {
                  Some(v) =>
                    match json_as_str(v) {
                      Some(s) => s
                      None => {
                        errors.push("probes.json: probes[\{idx}].expect 需为字符串")
                        ""
                      }
                    }
                  None => {
                    errors.push("probes.json: probes[\{idx}] 缺 expect")
                    ""
                  }
                }
                if script.length() > 0 && expect.length() > 0 {
                  probes.push({ name: name, script: script, expect: expect })
                }
                idx = idx + 1
              }
            }
            None => errors.push("probes.json: probes 需为数组")
          }
        None => errors.push("probes.json: 顶层缺 probes 数组")
      }
  }
  (probes, errors, warnings)
}

// ---------------- parser 分派 ----------------

///|
/// 已知 parser 名（自省用：指引里写了未注册的 parser 要报错，不是静默忽略）
pub fn known_parser(name : String) -> Bool {
  name == "json_level" || name == "json_probes" || name == "inline" || name == "empty" || name == "runtime"
}

///|
/// 单源解析：文本 → 载荷。text 为 None 表示源文件不存在。
pub fn run_parser(parser : String, text : String?, mode : String) -> (Payload, Array[String], Array[String]) {
  let errors : Array[String] = []
  let warnings : Array[String] = []
  if !known_parser(parser) {
    errors.push("未注册的 parser '\{parser}'（可用：json_level / json_probes / inline / empty / runtime）")
    return (Payload::Empty, errors, warnings)
  }
  match parser {
    "empty" => (Payload::Empty, errors, warnings)
    "runtime" => {
      warnings.push("runtime 源：内容由进程内 spawn API 生成，此处仅占位")
      (Payload::Runtime("runtime"), errors, warnings)
    }
    "inline" =>
      match text {
        None => {
          errors.push("inline 源缺少内容（inline 需要文件内有旧式 ```mbg 块）")
          (Payload::Empty, errors, warnings)
        }
        Some(t) => {
          let r = parse(t)
          (Payload::Level(r.spec.unwrap_or(default_spec())), r.errors, r.warnings)
        }
      }
    "json_level" =>
      match text {
        None => {
          errors.push("json_level 源文件缺失或不可读")
          (Payload::Empty, errors, warnings)
        }
        Some(t) => {
          let (spec, es, ws) = decode_level(t, mode)
          (Payload::Level(spec), es, ws)
        }
      }
    "json_probes" =>
      match text {
        None => {
          errors.push("json_probes 源文件缺失或不可读")
          (Payload::Empty, errors, warnings)
        }
        Some(t) => {
          let (ps, es, ws) = decode_probes(t)
          (Payload::Probes(ps), es, ws)
        }
      }
    _ => (Payload::Empty, errors, warnings)
  }
}

///|
/// 装配：按指引声明的顺序跑各源，合并成一份 GameSpec。
///
/// reader : (String) -> String?  —— 路径 → 内容（由 CLI 注入，解析层零 IO）
pub fn assemble(g : GuideSpec, reader : (String) -> String?) -> Assembly {
  let errors : Array[String] = []
  let warnings : Array[String] = []
  let loaded : Array[String] = []
  let skipped : Array[String] = []
  let spec = base_spec(g.mode)
  let mut have_level = false

  for s in g.sources {
    let text_opt = reader(s.path)
    if text_opt is None {
      if s.optional {
        skipped.push("\{s.name}(\{s.parser})")
        continue
      }
      errors.push("源 '\{s.name}' 声明的路径 '\{s.path}' 不存在")
      continue
    }
    let (payload, es, ws) = run_parser(s.parser, text_opt, g.mode)
    for e in es {
      errors.push("[\{s.name}] \{e}")
    }
    for w in ws {
      warnings.push("[\{s.name}] \{w}")
    }
    match payload {
      Payload::Level(ls) => {
        if have_level {
          merge_level(spec, ls) // 多源叠加（组合式内容源）
        } else {
          // 首个 Level 源直接采用（含未声明的默认值），保证 physics 默认值来自内容源
          let dst = ls
          dst.mode = if ls.mode == "" { g.mode } else { ls.mode }
          spec.w = dst.w
          spec.h = dst.h
          spec.bg = dst.bg
          spec.gravity = dst.gravity
          spec.jump_v = dst.jump_v
          spec.speed = dst.speed
          spec.player = dst.player
          spec.player_color = dst.player_color
          spec.player_seed = dst.player_seed
          spec.goal = dst.goal
          for x in dst.solids {
            spec.solids.push(x)
          }
          for x in dst.coins {
            spec.coins.push(x)
          }
          for x in dst.spikes {
            spec.spikes.push(x)
          }
          for x in dst.g_walls {
            spec.g_walls.push(x)
          }
          for x in dst.g_boxes {
            spec.g_boxes.push(x)
          }
          for x in dst.g_goals {
            spec.g_goals.push(x)
          }
          spec.g_cols = dst.g_cols
          spec.g_rows = dst.g_rows
          spec.g_cell = dst.g_cell
          spec.g_px = dst.g_px
          spec.g_py = dst.g_py
          have_level = true
        }
        loaded.push("\{s.name}(\{s.parser})")
      }
      Payload::Probes(ps) => {
        for p in ps {
          spec.probes.push(p)
        }
        loaded.push("\{s.name}(\{s.parser})")
      }
      Payload::Empty => loaded.push("\{s.name}(\{s.parser})")
      Payload::Runtime(n) => loaded.push("\{s.name}(\{n})")
    }
  }

  // 角色种子：指引声明的取值路径优先于 level.json 的固定值
  // （hero: procedural seed: player.seed 表示"种子来自 player.seed 字段"）
  if g.hero_seed_path == "player.seed" && spec.player_seed == 0 {
    warnings.push("hero seed 指向 player.seed 但该字段缺省为 0")
  }
  // 指引声明的 mode 优先（指引是"生命指引"——它说这个游戏属于哪族）
  spec.mode = g.mode
  spec.title = g.title

  // ---- 与旧入口同款门禁（不崩谓词）----
  if spec.mode == "physics" && spec.solids.length() == 0 {
    errors.push("physics 模式但无任何 platform——玩家会坠落判死")
  }
  if spec.mode == "grid" && spec.g_walls.length() == 0 {
    errors.push("grid 模式缺少 level 地图（墙为空）")
  }
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
  { spec: final_spec, errors: errors, warnings: warnings, loaded: loaded, skipped: skipped }
}