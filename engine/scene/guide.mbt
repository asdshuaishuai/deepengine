// guide —— 生命指引文件解析器（v1.3）。
//
// 职责边界（这是本次改造的核心约束）：
//   指引文件回答三个问题——**有哪些东西**（contents）、**怎么解析**
//   （sources）、**怎么渲染与组装**（render / assembly）。
//   它**不携带**关卡数据、坐标、脚本、关卡地图：那些是内容源（level.json /
//   probes.json / 运行时 spawn API）的职责。
//
// 因此 guide 产出的是 GuideSpec（一份"目录 + 装配指令"），不是 GameSpec。
// 数据流：GuideSpec --assemble--> GameSpec --build--> kernel 世界。
//
// 语法：缩进块式（不是 ```mbg fence——fence 是旧入口格式的产物）：
//
//   game "Box Push" mode: grid
//
//   source levels
//     path "level.json"
//     parser json_level
//
//   source probes
//     path "probes.json"
//     parser json_probes
//
//   render hero: procedural seed: player.seed
//     layer platforms   tint: #2b3448 bevel: 3
//     layer coins       spin: 0.18
//
//   assembly
//     attach hero: player
//     hud "state coins frame x y"
//
// 行尾 `#` 之外无特殊语法；未知指令 → 警告不中断（不崩谓词）。

///|
pub(all) struct SourceRef {
  pub name : String // 引用键（contents 里用它指代这个源）
  pub path : String // 相对路径（相对指引文件所在目录）
  pub parser : String // 解析器名（注册表 key）
  pub optional : Bool // 源缺失时不报错（可选项）
}

///|
pub(all) struct RenderLayer {
  pub name : String // 层名：hero / platforms / coins / spikes / goal / hud
  pub params : Array[(String, String)] // 渲染参数（保序）
}

///|
pub(all) struct GuideSpec {
  mut title : String
  mut mode : String // "physics" | "grid"
  mut sources : Array[SourceRef] // 声明式：有哪些源、怎么解析
  mut render : Array[RenderLayer] // 渲染配置：每层用什么参数
  mut hud : String // HUD 显示哪些可观测值
  mut hero_seed_path : String // 角色种子取值路径（hero: procedural seed: <path>）
  game_params : Array[(String, String)] // game 行的其余 key:value（保序）
  errors : Array[String]
  warnings : Array[String]
}

///|
fn gs_default() -> GuideSpec {
  {
    title: "untitled",
    mode: "physics",
    sources: [],
    render: [],
    hud: "state frame",
    hero_seed_path: "",
    game_params: [],
    errors: [],
    warnings: [],
  }
}

///|
fn indent_of(line : String) -> Int {
  let mut n = 0
  for ch in line {
    if ch == ' ' {
      n = n + 1
    } else if ch == '\t' {
      n = n + 2
    } else {
      break
    }
  }
  n
}

///|
/// 去掉行尾注释（`#` 开头到行尾）——注意：行首 `#` 也算注释，
/// 指引文件不含 `#` 开头的字面量（颜色用 `bg:#rrggbb`，`#` 不在行首）。
fn strip_comment(line : String) -> String {
  let mut out = ""
  let mut seen = false
  for ch in line {
    if ch == '#' {
      seen = true
      break
    }
    if ch == '\n' || ch == '\r' {
      break
    }
    out = out + ch.to_string()
  }
  if seen {
    out
  } else {
    out
  }
}

///|
/// 取出 `"..."` 引号内容（第二个参数用）
fn take_quoted(line : String) -> String? {
  let pos = line.find("\"")
  match pos {
    None => None
    Some(i) => {
      let rest = line.substring(start=i + 1)
      let end = rest.find("\"")
      match end {
        None => None
        Some(e) => Some(rest.substring(start=0, end=e))
      }
    }
  }
}

///|
/// 裸词（不含空格的第一个 token），用于 directive 名与 path
fn first_word(line : String) -> String {
  let t = line.trim().to_owned()
  let mut i = 0
  while i < t.length() {
    let c = t.substring(start=i, end=i + 1)
    if c == " " || c == "\t" {
      break
    }
    i = i + 1
  }
  t.substring(start=0, end=i)
}

///|
/// key:value → (key, value)，值可含空格（切首个冒号）
fn take_kv(line : String) -> (String?, String) {
  let pos = line.find(":")
  match pos {
    None => (None, "")
    Some(i) => {
      let k = line.substring(start=0, end=i).trim().to_owned()
      let v = line.substring(start=i + 1).trim().to_owned()
      (Some(k), v)
    }
  }
}

///|
/// 收集 `key: value` 形式的参数（用于 layer 行）
fn collect_params(rest : String, into : Array[(String, String)]) -> Unit {
  // rest 形如 "hero: procedural  seed: player.seed" 或 "tint: #2b3448 bevel: 3"
  let toks : Array[StringView] = rest.split(" ").iter().collect()
  let mut key : String? = None
  for tok in toks {
    let t = tok.trim().to_owned()
    if t.length() == 0 {
      continue
    }
    let (k, v) = take_kv(t)
    match k {
      Some(kk) => {
        // "tint:" 后面若紧跟值（无空格粘连）已在 v 里；否则下一个 token 是值
        if v.length() > 0 {
          into.push((kk, v))
          key = None
        } else {
          key = Some(kk)
        }
      }
      None =>
        match key {
          Some(kk) => {
            into.push((kk, t))
            key = None
          }
          None => ()
        }
    }
  }
  // 悬挂的 key（后面没值）忽略
}

///|
fn find_param(params : Array[(String, String)], key : String) -> String? {
  for p in params {
    if p.0 == key {
      return Some(p.1)
    }
  }
  None
}

///|
/// 取指令词之后的尾部（`word` 已由 first_word 得出）。
/// 用词长而非魔法数字——`substring(start=5)` 这类偏移在指令重命名时会静默错切。
fn tail_after(line : String, word_len : Int) -> String {
  if line.length() > word_len {
    line.substring(start=word_len)
  } else {
    ""
  }
}

///|
/// 剥掉一层成对引号（路径/名字允许引号包裹）
fn unquote(s : String) -> String {
  let t = s.trim().to_owned()
  if t.length() >= 2 {
    let a = t.substring(start=0, end=1)
    let b = t.substring(start=t.length() - 1, end=t.length())
    if a == "\"" && b == "\"" {
      return t.substring(start=1, end=t.length() - 1)
    }
  }
  t
}

///|
/// 解析指引文件全文 → GuideSpec（不崩：errors 收集，不中断）
pub fn parse_guide(source : String) -> GuideSpec {
  let g = gs_default()
  let lines : Array[StringView] = source.split("\n").iter().collect()
  let mut i = 0
  let mut line_no = 0
  let mut block : String = "" // 当前块上下文："" | "source:<name>" | "render" | "assembly" | "render layer:<name>"
  let mut cur_source_name : String = ""
  let mut cur_layer : RenderLayer? = None

  // 提交挂起的 layer
  let flush_layer = fn() -> Unit {
    match cur_layer {
      Some(l) => g.render.push(l)
      None => ()
    }
  }

  while i < lines.length() {
    let raw = lines[i].to_owned()
    line_no = line_no + 1
    i = i + 1
    let no_comment = strip_comment(raw)
    let trimmed = no_comment.trim().to_owned()
    if trimmed.length() == 0 {
      continue
    }
    let ind = indent_of(no_comment)
    let word = first_word(trimmed)

    // ---- 顶层（缩进 0）----
    if ind == 0 {
      flush_layer()
      cur_layer = None
      block = ""
      cur_source_name = ""
      match word {
        "game" => {
          // game "Title" mode: grid|physics
          // 关键：mode: 在标题之后，不能用整行 find(":")——那会命中标题里的冒号。
          // 做法：先取标题，再在"去掉 game 与标题"后的余部里解析 key:value。
          let rest = tail_after(trimmed, word.length())
          match take_quoted(rest) {
            Some(t) => {
              g.title = t
              // 余部 = 标题之后的文字
              let after = rest.substring(start=t.length() + 2)
              collect_params(after, g.game_params)
              match find_param(g.game_params, "mode") {
                Some(v) =>
                  if v == "grid" || v == "physics" {
                    g.mode = v
                  } else {
                    g.errors.push("line \{line_no}: mode 只支持 grid|physics，收到 '\{v}'")
                  }
                None => ()
              }
            }
            None => g.errors.push("line \{line_no}: game 需要 \"标题\"")
          }
        }
        "source" => {
          let name = tail_after(trimmed, word.length()).trim().to_owned()
          if name.length() == 0 {
            g.errors.push("line \{line_no}: source 需要名字（source levels）")
          } else {
            block = "source"
            cur_source_name = name
            g.sources.push({ name: name, path: "", parser: "", optional: false })
          }
        }
        "render" => {
          block = "render"
        }
        "assembly" => {
          block = "assembly"
        }
        _ => g.warnings.push("line \{line_no}: 顶层未知指令 '\{word}'（已忽略）")
      }
      continue
    }

    // ---- 缩进块内 ----
    if block == "source" {
      match word {
        "path" => {
          let p = unquote(tail_after(trimmed, word.length()))
          if p.length() > 0 {
            if g.sources.length() > 0 {
              let last = g.sources[g.sources.length() - 1]
              if last.name == cur_source_name {
                g.sources[g.sources.length() - 1] = { name: last.name, path: p, parser: last.parser, optional: last.optional }
              }
            }
          } else {
            g.errors.push("line \{line_no}: path 需要值")
          }
        }
        "parser" => {
          let p = unquote(tail_after(trimmed, word.length()))
          if p.length() > 0 {
            if g.sources.length() > 0 {
              let last = g.sources[g.sources.length() - 1]
              if last.name == cur_source_name {
                g.sources[g.sources.length() - 1] = { name: last.name, path: last.path, parser: p, optional: last.optional }
              }
            }
          } else {
            g.errors.push("line \{line_no}: parser 需要值")
          }
        }
        "optional" => {
          if g.sources.length() > 0 {
            let last = g.sources[g.sources.length() - 1]
            if last.name == cur_source_name {
              g.sources[g.sources.length() - 1] = { name: last.name, path: last.path, parser: last.parser, optional: true }
            }
          }
        }
        _ => g.warnings.push("line \{line_no}: source 块内未知指令 '\{word}'（已忽略）")
      }
      continue
    }

    if block == "render" || block == "render layer" {
      // render 子项：layer <name> <params>  或  hero: procedural seed: <path>
      // 注意 block 可能是 "render layer"——续行参数里若再出现 layer
      // 说明开始了新的一层，必须先提交旧的（否则 layer 列表会只剩一层）。
      if word == "layer" {
        flush_layer()
        cur_layer = None
        let rest = tail_after(trimmed, word.length()).trim().to_owned()
        let lname = first_word(rest)
        let params : Array[(String, String)] = []
        collect_params(tail_after(rest, lname.length()).trim().to_owned(), params)
        cur_layer = Some({ name: lname, params: params })
        block = "render layer"
        continue
      }
      if word == "hero" || word == "hero:" {
        // hero: procedural seed: <path>  [rig: on|off]  [dust: on|off]
        //
        // 关键：参数要从 `hero:` **之后**取，不能对整行 collect_params——
        // 那会把指令名 "hero" 本身连同 "procedural" 收成一对参数，
        // 于是 hero 层凭空多出名为 "hero" 的假参数。
        let rest = tail_after(trimmed, word.length()).trim().to_owned()
        let params : Array[(String, String)] = []
        collect_params(rest, params)
        match find_param(params, "seed") {
          Some(sp) => g.hero_seed_path = sp
          None => g.warnings.push("line \{line_no}: hero 未声明 seed: <path>")
        }
        // seed 走 hero_seed_path（渲染契约在层循环外读它）；
        // 其余参数挂到 hero 层——不挂层等于写了不生效，静默失效最坏。
        let hero_params : Array[(String, String)] = []
        for p in params {
          if p.0 != "seed" {
            hero_params.push(p)
          }
        }
        if hero_params.length() > 0 {
          flush_layer()
          cur_layer = Some({ name: "hero", params: hero_params })
          block = "render layer"
        }
        continue
      }
      g.warnings.push("line \{line_no}: render 块内未知指令 '\{word}'（已忽略）")
      continue
    }

    if block == "render layer" {
      // layer 的续行参数
      match cur_layer {
        Some(l) => {
          let params2 : Array[(String, String)] = []
          for p in l.params {
            params2.push(p)
          }
          collect_params(trimmed, params2)
          cur_layer = Some({ name: l.name, params: params2 })
        }
        None => ()
      }
      continue
    }

    if block == "assembly" {
      match word {
        "hud" => {
          g.hud = unquote(tail_after(trimmed, word.length()).trim().to_owned())
        }
        "attach" => g.warnings.push("line \{line_no}: attach 在装配层由 source 名隐式完成（已忽略）")
        _ => g.warnings.push("line \{line_no}: assembly 块内未知指令 '\{word}'（已忽略）")
      }
      continue
    }
    g.warnings.push("line \{line_no}: 未知上下文下的缩进内容（已忽略）")
  }
  flush_layer()

  // ---- 门禁（不崩谓词：结构性错误才拦，缺省不拦）----
  if g.sources.length() == 0 {
    g.warnings.push("指引未声明任何 source——将以空世界启动")
  }
  for s in g.sources {
    if s.parser.length() == 0 {
      g.errors.push("source '\{s.name}' 缺 parser 声明")
    }
    if s.path.length() == 0 && !s.optional {
      g.errors.push("source '\{s.name}' 缺 path 声明")
    }
  }
  g
}