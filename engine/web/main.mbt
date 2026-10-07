// web —— 内核 wasm 面（blueprint §8 第四面）。
//
// 与 native 共享同一 kernel/scene 代码：玩法语义单一来源，
// 本包只做「状态全局 + JSON 快照」的宿主桥，不含渲染——画布由宿主绘制。
//
// 所有导出均为 String/Int 简单类型（js-string builtins 直通）。

///|
let spec_ref : @ref.Ref[@scene.GameSpec?] = @ref.new(None)

///|
let game_ref : @ref.Ref[@kernel.Game?] = @ref.new(None)

///|
let grid_ref : @ref.Ref[@kernel.GridGame?] = @ref.new(None)

///|
let source_ref : @ref.Ref[String] = @ref.new("")

///|
/// 已注册的内容源：路径 → 文本（v1.3）
///
/// wasm 面无文件 IO（Mechanic 契约：内核不碰 IO）。宿主用 web_put_source
/// 逐个注册源内容，再用 web_load_guide 加载指引。装配层通过这个注册表
/// 解析 source path —— 与 native 面的 mbg_read_file 是同一份装配逻辑，
/// 只是 reader 的实现不同。
let source_store : @ref.Ref[Array[(String, String)]] = @ref.new([])

///|
/// 宿主注册一个内容源（path → text）。重复注册后者覆盖前者。
pub fn web_put_source(path : String, text : String) -> Int {
  let next : Array[(String, String)] = []
  let mut replaced = false
  for kv in source_store.val {
    if kv.0 == path {
      next.push((path, text))
      replaced = true
    } else {
      next.push(kv)
    }
  }
  if !replaced {
    next.push((path, text))
  }
  source_store.val = next
  1
}

///|
/// 清空已注册的内容源（宿主切换项目时用）
pub fn web_clear_sources() -> Int {
  source_store.val = []
  1
}

///|
/// 内存 reader：按已注册的路径查内容（装配层的 reader 注入点）
fn web_reader(path : String) -> String? {
  for kv in source_store.val {
    if kv.0 == path {
      return Some(kv.1)
    }
  }
  None
}

///|
/// 载入指引文件（v1.3 指引入口）。内容源须已由 web_put_source 注册。
/// 返回 {ok, mode, w, h, probes, warnings} 或错误。
pub fn web_load_guide(guide_source : String) -> String {
  source_ref.val = guide_source
  entry_is_guide.val = true
  let guide = @scene.parse_guide(guide_source)
  if guide.errors.length() > 0 {
    let mut msg = ""
    for e in guide.errors {
      msg = msg + e + "; "
    }
    return "{\"ok\":false,\"error\":\"guide parse: \{msg}\"}"
  }
  let asm = @scene.assemble(guide, web_reader)
  if asm.errors.length() > 0 {
    let mut msg = ""
    for e in asm.errors {
      msg = msg + e + "; "
    }
    return "{\"ok\":false,\"error\":\"assembly: \{msg}\"}"
  }
  match asm.spec {
    Some(spec) => {
      spec_ref.val = Some(spec)
      if spec.mode == "grid" {
        grid_ref.val = Some(spec.build_grid())
        game_ref.val = None
        "{\"ok\":true,\"mode\":\"grid\",\"w\":\{spec.w},\"h\":\{spec.h},\"cell\":\{spec.g_cell},\"probes\":\{spec.probes.length()},\"warnings\":\{asm.warnings.length()}}"
      } else {
        game_ref.val = Some(spec.build())
        grid_ref.val = None
        "{\"ok\":true,\"mode\":\"physics\",\"w\":\{spec.w},\"h\":\{spec.h},\"probes\":\{spec.probes.length()},\"warnings\":\{asm.warnings.length()}}"
      }
    }
    None => "{\"ok\":false,\"error\":\"no spec\"}"
  }
}

///|
/// 重载当前指引（内容源改动后调用）
pub fn web_reload_guide() -> String {
  web_load_guide(source_ref.val)
}

///|
///|
/// ---- 运行时衍生 API（v1.2 内核一等接口：不经文本文件直接生成内容）----

///|
pub fn web_spawn_coin(x : Double, y : Double, w : Double) -> Int {
  match game_ref.val {
    Some(g) => @kernel.spawn_coin(g, x, y, w)
    None => -1
  }
}

///|
pub fn web_spawn_platform(x : Double, y : Double, w : Double, h : Double) -> Int {
  match game_ref.val {
    Some(g) =>
      if @kernel.spawn_platform(g, x, y, w, h) {
        1
      } else {
        0
      }
    None => 0
  }
}

///|
pub fn web_spawn_goal(x : Double, y : Double, w : Double, h : Double) -> Int {
  match game_ref.val {
    Some(g) =>
      if @kernel.spawn_goal(g, x, y, w, h) {
        1
      } else {
        0
      }
    None => 0
  }
}

///|
pub fn web_grid_spawn_box(cx : Int, cy : Int) -> Int {
  match grid_ref.val {
    Some(g) =>
      if @kernel.grid_spawn_box(g, cx, cy) {
        1
      } else {
        0
      }
    None => 0
  }
}

///|
pub fn web_grid_spawn_goal(cx : Int, cy : Int) -> Int {
  match grid_ref.val {
    Some(g) =>
      if @kernel.grid_spawn_goal(g, cx, cy) {
        1
      } else {
        0
      }
    None => 0
  }
}

///|
/// 种子 → 角色 SVG（文本工件：宿主可直接 innerHTML 渲染或保存）
pub fn web_skin_svg(seed : Int) -> String {
  @skin.skin_svg(seed)
}

///|
pub fn version_info() -> String {
  "{\"engine\":\"deepengine\",\"version\":\"0.2.0\",\"entries\":[\"inline-mbg\",\"guide\"],\"faces\":[\"native-gpu\",\"native-sw-headless\",\"cli\",\"wasm\"]}"
}

///|
/// 载入 .mbg.md 源：解析 + 建世界 + 初始化全局。返回 {ok, mode, w, h} 或错误。
pub fn web_load(source : String) -> String {
  source_ref.val = source
  entry_is_guide.val = false
  let r = @scene.parse(source)
  if r.errors.length() > 0 {
    let mut msg = ""
    for e in r.errors {
      msg = msg + e + "; "
    }
    // 警告合并进返回（不静默）
    return "{\"ok\":false,\"error\":\"\{msg}\"}"
  }
  match r.spec {
    Some(spec) => {
      spec_ref.val = Some(spec)
      if spec.mode == "grid" {
        grid_ref.val = Some(spec.build_grid())
        game_ref.val = None
        "{\"ok\":true,\"mode\":\"grid\",\"w\":\{spec.w},\"h\":\{spec.h},\"cell\":\{spec.g_cell},\"warnings\":\{r.warnings.length()}}"
      } else {
        game_ref.val = Some(spec.build())
        grid_ref.val = None
        "{\"ok\":true,\"mode\":\"physics\",\"w\":\{spec.w},\"h\":\{spec.h},\"warnings\":\{r.warnings.length()}}"
      }
    }
    None => "{\"ok\":false,\"error\":\"no spec\"}"
  }
}

///|
/// 当前载入的是指引还是 inline（R 键语义要分派）
let entry_is_guide : @ref.Ref[Bool] = @ref.new(false)

///|
/// 重置到载入时的初始状态（R 键语义）——按载入方式分派
pub fn web_reset() -> String {
  if entry_is_guide.val {
    web_load_guide(source_ref.val)
  } else {
    web_load(source_ref.val)
  }
}

///|
/// 物理族步进一帧：left/right/jump 为 0|1
pub fn web_step(left : Int, right : Int, jump : Int) -> String {
  match game_ref.val {
    Some(g) => {
      @kernel.step(
        g,
        {
          left: left == 1,
          right: right == 1,
          jump: jump == 1,
        },
      )
      web_frame()
    }
    None => "{\"error\":\"no physics game\"}"
  }
}

///|
/// grid 族单步移动：dir ∈ left/right/up/down
pub fn web_grid_move(dir : String) -> String {
  match grid_ref.val {
    Some(g) => {
      @kernel.grid_step(g, dir)
      web_frame()
    }
    None => "{\"error\":\"no grid game\"}"
  }
}

///|
/// 完整渲染载荷（宿主据此绘制——状态投影，同 native 的 render 职责划分）
pub fn web_frame() -> String {
  match spec_ref.val {
    Some(spec) =>
      if spec.mode == "grid" {
        match grid_ref.val {
          Some(g) => grid_frame(g, spec)
          None => "{\"error\":\"no grid game\"}"
        }
      } else {
        match game_ref.val {
          Some(g) => physics_frame(g)
          None => "{\"error\":\"no physics game\"}"
        }
      }
    None => "{\"error\":\"not loaded\"}"
  }
}

///|
fn physics_frame(g : @kernel.Game) -> String {
  let (br, bg_, bb) = g.bg
  let (pr, pg, pb) = g.player_color
  let mut s = "{\"mode\":\"physics\",\"w\":\{g.w},\"h\":\{g.h},\"bg\":[\{br},\{bg_},\{bb}]"
  s = s + ",\"frame\":\{g.frame},\"state\":\"\{g.state}\",\"coins_taken\":\{g.coins_taken},\"coins_total\":\{g.coins.length()}"
  s = s + ",\"player\":{\"x\":\{g.player.x},\"y\":\{g.player.y},\"w\":\{g.player.w},\"h\":\{g.player.h},\"vx\":\{g.player.vx},\"seed\":\{g.player_seed},\"color\":[\{pr},\{pg},\{pb}]}"
  s = s + ",\"solids\":["
  let mut i = 0
  for so in g.solids {
    let (r1, g1, b1) = so.color
    if i > 0 {
      s = s + ","
    }
    s = s + "{\"x\":\{so.rect.x},\"y\":\{so.rect.y},\"w\":\{so.rect.w},\"h\":\{so.rect.h},\"color\":[\{r1},\{g1},\{b1}]}"
    i = i + 1
  }
  s = s + "],\"coins\":["
  let mut j = 0
  for c in g.coins {
    let (r1, g1, b1) = c.color
    if j > 0 {
      s = s + ","
    }
    s = s + "{\"id\":\{c.id},\"x\":\{c.rect.x},\"y\":\{c.rect.y},\"w\":\{c.rect.w},\"taken\":\{c.taken},\"color\":[\{r1},\{g1},\{b1}]}"
    j = j + 1
  }
  s = s + "],\"spikes\":["
  let mut k = 0
  for sp in g.spikes {
    if k > 0 {
      s = s + ","
    }
    s = s + "{\"x\":\{sp.x},\"y\":\{sp.y},\"w\":\{sp.w},\"h\":\{sp.h}}"
    k = k + 1
  }
  s = s + "],\"goal\":"
  match g.goal {
    Some(gl) => s = s + "{\"x\":\{gl.x},\"y\":\{gl.y},\"w\":\{gl.w},\"h\":\{gl.h}}"
    None => s = s + "null"
  }
  s = s + "}"
  s
}

///|
fn grid_frame(g : @kernel.GridGame, spec : @scene.GameSpec) -> String {
  let mut s = "{\"mode\":\"grid\",\"w\":\{spec.w},\"h\":\{spec.h},\"cell\":\{spec.g_cell},\"cols\":\{g.cols},\"rows\":\{g.rows}"
  s = s + ",\"state\":\"\{g.state}\",\"moves\":\{g.moves},\"boxes_on\":\{@kernel.grid_boxes_on(g)},\"boxes_total\":\{g.boxes.length()}"
  s = s + ",\"player\":{\"cx\":\{g.px},\"cy\":\{g.py},\"seed\":\{g.seed}}"
  s = s + ",\"walls\":["
  let mut i = 0
  for w in g.walls {
    let (wx, wy) = w
    if i > 0 {
      s = s + ","
    }
    s = s + "[\{wx},\{wy}]"
    i = i + 1
  }
  s = s + "],\"boxes\":["
  let mut j = 0
  for b in g.boxes {
    let (bx, by) = b
    if j > 0 {
      s = s + ","
    }
    s = s + "[\{bx},\{by}]"
    j = j + 1
  }
  s = s + "],\"goals\":["
  let mut k = 0
  for t in g.goals {
    let (gx, gy) = t
    if k > 0 {
      s = s + ","
    }
    s = s + "[\{gx},\{gy}]"
    k = k + 1
  }
  s = s + "]}"
  s
}

///|
/// 在内核层跑声明探针（不扰动进行中的对局——副本上执行）。
/// 返回与 CLI verify 相同的 binary 主分报告。
pub fn web_verify() -> String {
  match spec_ref.val {
    Some(spec) => {
      let report = if spec.mode == "grid" {
        @kernel.verify_grid(spec.build_grid(), spec.probes)
      } else {
        @kernel.verify(spec.build(), spec.probes)
      }
      @kernel.report_json(report, source_ref.val)
    }
    None => "{\"error\":\"not loaded\"}"
  }
}

///|
fn main {
  // wasm 面：宿主直接调用导出函数，无 CLI 入口（is-main 约束的空 main）
  ignore(0)
}
