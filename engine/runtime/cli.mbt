// cli —— 消费面入口（blueprint §8 的 CLI 面最小切片）
//
//   deepengine run    <game.guide.md>               交互游玩（GPU）
//   deepengine verify <game.guide.md> [--shot p]    headless 探针验证（SW）
//   deepengine shot   <game.guide.md> [--frame N] [--out p]
//   deepengine inspect <game.guide.md>              只装配不渲染，打印装配报告
//
// 入口分派（v1.3）：`.guide.md` 走「生命指引」路径（parse_guide → assemble），
// `.mbg.md` 走旧 inline 路径（parse）——两者汇入同一个 GameSpec 与同一个内核，
// 没有两套世界构建（DECLARATION.md：禁 workaround 重复）。
//
// verify 输出 JSON 报告（binary 主分 + 自审计字段），退出码 0=PASS / 2=FAIL / 1=解析错。

///|
fn arg_after(args : Array[String], flag : String) -> String? {
  let mut i = 0
  while i < args.length() {
    if args[i] == flag && i + 1 < args.length() {
      return Some(args[i + 1])
    }
    i = i + 1
  }
  None
}

///|
/// 入口分派：`.guide.md` → 指引路径；其他 → inline 路径。
/// 返回 (GameSpec?, 原始源文本) —— 源文本供契约指纹用。
fn is_guide_path(path : String) -> Bool {
  path.length() >= 9 && path.substring(start=path.length() - 9) == ".guide.md"
}

///|
/// 取路径的目录部分（源路径相对指引文件解析）
fn dir_of(path : String) -> String {
  let mut i = path.length()
  while i > 0 {
    let c = path.substring(start=i - 1, end=i)
    if c == "/" {
      return path.substring(start=0, end=i)
    }
    i = i - 1
  }
  "."
}

///|
/// 相对路径拼接（source path 相对指引文件目录）
fn join_path(dir : String, rel : String) -> String {
  if rel.length() > 0 && rel.substring(start=0, end=1) == "/" {
    return rel // 绝对路径直接用
  }
  if dir == "." {
    rel
  } else {
    dir + "/" + rel
  }
}

///|
/// 装载游戏：指引路径 → parse_guide + assemble；inline 路径 → parse。
/// 失败时已打印错误 JSON，返回 None。
fn load_spec(path : String) -> @scene.GameSpec? {
  if @bridge.mbg_file_exists(path) == 0 {
    println("{\"error\":\"file not found: \{path}\"}")
    return None
  }
  if is_guide_path(path) {
    return load_via_guide(path)
  }
  let source = @bridge.mbg_read_file(path)
  let r = @scene.parse(source)
  if r.errors.length() > 0 {
    let mut msg = ""
    for e in r.errors {
      msg = msg + e + "; "
    }
    println("{\"error\":\"parse failed\",\"details\":\"\{msg}\"}")
    return None
  }
  match r.spec {
    Some(spec) => {
      // warnings 不拦截，但如实报告（可解释反馈）——走 stderr，
      // stdout 只留报告 JSON（verify 的机器协议必须单文档）
      for w in r.warnings {
        @bridge.mbg_warn(w)
      }
      Some(spec)
    }
    None => {
      println("{\"error\":\"no spec\"}")
      None
    }
  }
}

///|
/// 指引路径装配：解析指引 → 按 source 声明读内容 → 组装 GameSpec
/// 顺带把 render / assembly 声明落成渲染配置（指引说了就算）。
fn load_via_guide(path : String) -> @scene.GameSpec? {
  let guide_src = @bridge.mbg_read_file(path)
  let guide = @scene.parse_guide(guide_src)
  for e in guide.errors {
    @bridge.mbg_warn("guide error: \{e}")
  }
  if guide.errors.length() > 0 {
    let mut msg = ""
    for e in guide.errors {
      msg = msg + e + "; "
    }
    println("{\"error\":\"guide parse failed\",\"details\":\"\{msg}\"}")
    return None
  }
  let base_dir = dir_of(path)
  // reader 闭包：把相对 source 路径解析为绝对（相对指引文件目录）
  let reader = fn(rel : String) -> String? {
    let full = join_path(base_dir, rel)
    if @bridge.mbg_file_exists(full) == 0 {
      None
    } else {
      Some(@bridge.mbg_read_file(full))
    }
  }
  let asm = @scene.assemble(guide, reader)
  for w in asm.warnings {
    @bridge.mbg_warn(w)
  }
  if asm.errors.length() > 0 {
    let mut msg = ""
    for e in asm.errors {
      msg = msg + e + "; "
    }
    println("{\"error\":\"assembly failed\",\"details\":\"\{msg}\"}")
    return None
  }
  match asm.spec {
    Some(spec) => {
      apply_guide_view(guide, spec)
      Some(spec)
    }
    None => {
      println("{\"error\":\"no spec\"}")
      None
    }
  }
}

///|
/// 把指引的 render / assembly 声明装进渲染层。
/// 渲染契约的 errors 是 P0（画面会画错就必须拦），warnings 走 stderr 不拦。
fn apply_guide_view(guide : @scene.GuideSpec, spec : @scene.GameSpec) -> Unit {
  let cfg = @rendercfg.from_guide(guide.render, "procedural", guide.hero_seed_path, spec.player_seed)
  for w in cfg.warnings {
    @bridge.mbg_warn(w)
  }
  if cfg.errors.length() > 0 {
    let mut msg = ""
    for e in cfg.errors {
      msg = msg + e + "; "
    }
    println("{\"error\":\"render config invalid\",\"details\":\"\{msg}\"}")
    return
  }
  set_render_config(cfg)
  let hud = @rendercfg.hud_from(guide.hud, spec.mode == "grid")
  for w in hud.warnings {
    @bridge.mbg_warn(w)
  }
  set_hud_config(hud)
}

///|
/// inspect：只装配不渲染——打印装配报告（诊断用：哪些源被载入/跳过）
fn cmd_inspect(path : String) -> Unit {
  if @bridge.mbg_file_exists(path) == 0 {
    println("{\"error\":\"file not found: \{path}\"}")
    @bridge.exit(1)
    return
  }
  if !is_guide_path(path) {
    // inline 路径：报告解析产物
    let r = @scene.parse(@bridge.mbg_read_file(path))
    let mut s = "{\"entry\":\"inline\",\"warnings\":\{r.warnings.length()},\"errors\":\{r.errors.length()}"
    match r.spec {
      Some(spec) => {
        s = s + ",\"ok\":true,\"title\":\"\{spec.title}\",\"mode\":\"\{spec.mode}\""
        s = s + ",\"probes\":\{spec.probes.length()},\"solids\":\{spec.solids.length()},\"coins\":\{spec.coins.length()}}"
      }
      None => {
        s = s + ",\"ok\":false}"
      }
    }
    println(s)
    @bridge.exit(if r.errors.length() > 0 { 1 } else { 0 })
    return
  }
  let guide = @scene.parse_guide(@bridge.mbg_read_file(path))
  for e in guide.errors {
    @bridge.mbg_warn("guide error: \{e}")
  }
  let base_dir = dir_of(path)
  let reader = fn(rel : String) -> String? {
    let full = join_path(base_dir, rel)
    if @bridge.mbg_file_exists(full) == 0 {
      None
    } else {
      Some(@bridge.mbg_read_file(full))
    }
  }
  let asm = @scene.assemble(guide, reader)
  let mut s = "{\"entry\":\"guide\",\"title\":\"\{guide.title}\",\"mode\":\"\{guide.mode}\""
  s = s + ",\"sources\":["
  let mut i = 0
  for src in guide.sources {
    if i > 0 {
      s = s + ","
    }
    s = s + "{\"name\":\"\{src.name}\",\"parser\":\"\{src.parser}\",\"path\":\"\{src.path}\",\"optional\":\{src.optional}}"
    i = i + 1
  }
  s = s + "],\"layers\":["
  let mut j = 0
  for l in guide.render {
    if j > 0 {
      s = s + ","
    }
    s = s + "\"\{l.name}\""
    j = j + 1
  }
  s = s + "],\"hud\":\"\{guide.hud}\""
  // 生效后的渲染配置（agent 要看到"声明 → 实际值"，而不只是"声明了什么"）
  let cfg = @rendercfg.from_guide(guide.render, "procedural", guide.hero_seed_path, 0)
  s = s + ",\"view\":{\"hero\":\"\{cfg.hero_mode}\",\"bevel\":\{cfg.platform_bevel},\"edge\":\{cfg.platform_edge},\"spin\":\{cfg.coin_spin}"
  s = s + ",\"teeth\":\{cfg.spike_teeth},\"flag\":\{cfg.goal_flag},\"grip\":\{cfg.grid_grip}"
  s = s + ",\"dust\":\{cfg.dust},\"rig\":\{cfg.hero_rig}}"
  let hud_cfg = @rendercfg.hud_from(guide.hud, guide.mode == "grid")
  s = s + ",\"hud_fields\":["
  let mut hf = 0
  for f in hud_cfg.fields {
    if hf > 0 {
      s = s + ","
    }
    s = s + "\"\{f}\""
    hf = hf + 1
  }
  s = s + "]"
  s = s + ",\"view_warnings\":["
  let mut vw = 0
  for w in cfg.warnings {
    if vw > 0 {
      s = s + ","
    }
    s = s + "\"\{w}\""
    vw = vw + 1
  }
  for w in hud_cfg.warnings {
    if vw > 0 {
      s = s + ","
    }
    s = s + "\"\{w}\""
    vw = vw + 1
  }
  s = s + "]"
  // 渲染契约的 errors 是 P0（画面会画错），必须在 inspect 里可见——
  // 只报 warnings 会让"值域非法"看起来像"生效了"
  s = s + ",\"view_errors\":["
  let mut ve = 0
  for e in cfg.errors {
    if ve > 0 {
      s = s + ","
    }
    s = s + "\"\{e}\""
    ve = ve + 1
  }
  s = s + "]"
  s = s + ",\"loaded\":["
  let mut k = 0
  for l in asm.loaded {
    if k > 0 {
      s = s + ","
    }
    s = s + "\"\{l}\""
    k = k + 1
  }
  s = s + "],\"skipped\":["
  let mut m = 0
  for l in asm.skipped {
    if m > 0 {
      s = s + ","
    }
    s = s + "\"\{l}\""
    m = m + 1
  }
  s = s + "]"
  match asm.spec {
    Some(spec) => {
      let total_err = asm.errors.length() + cfg.errors.length()
      let ok = total_err == 0
      s = s + ",\"ok\":\{ok},\"probes\":\{spec.probes.length()},\"solids\":\{spec.solids.length()},\"coins\":\{spec.coins.length()},\"warnings\":\{asm.warnings.length()},\"errors\":\{total_err}"
      s = s + "}"
    }
    None => s = s + ",\"ok\":false,\"warnings\":\{asm.warnings.length()},\"errors\":\{asm.errors.length()}}"
  }
  println(s)
  @bridge.exit(if asm.errors.length() > 0 || cfg.errors.length() > 0 { 1 } else { 0 })
}

///|
pub fn cli(args : Array[String]) -> Unit {
  if args.length() < 3 {
    println("usage: deepengine <run|verify|shot|inspect> <game.guide.md> [--shot p] [--frame N] [--out p]")
    println("       deepengine retro <hero|palette|chr|ascii|identify|check> [args]")
    @bridge.exit(1)
  }
  let cmd = args[1]
  let path = args[2]
  // skin <seed>：直接生成角色 SVG 工件（stdout——agent 可保存/diff）
  if cmd == "skin" {
    let seed = match parse_int_arg(args[2]) {
      Some(v) => v
      None => {
        println("{\"error\":\"skin 需要 <seed> 整数\"}")
        return
      }
    }
    println(@skin.skin_svg(seed))
    @bridge.exit(0)
  }
  // retro <子命令>：FC/SFC 资源制作与识别面（blueprint §6.5）
  if cmd == "retro" {
    cmd_retro(args)
    return
  }
  match cmd {
    "run" => cmd_run(path)
    "verify" => cmd_verify(path, arg_after(args, "--shot"))
    "shot" => cmd_shot(path, arg_after(args, "--frame"), arg_after(args, "--out"))
    "inspect" => cmd_inspect(path)
    _ => {
      println("{\"error\":\"unknown command \{cmd}\"}")
      @bridge.exit(1)
    }
  }
}

///|
/// retro 子命令分发
///
///   retro hero <fc|sfc> [scale]      生成 FC/SFC 受约束角色 clip → SVG（stdout）
///   retro ascii <fc|sfc> <pose>      生成单帧并输出 ASCII 预览（终端可读）
///   retro chr <fc|sfc> <pose>        生成单帧并输出 CHR hexdump（16 字节）
///   retro palette                   输出 FC 64 色调色板文本
///   retro identify <fc|sfc> <pose>   生成→CHR→读回→普查→合规报告（JSON）
///   retro check <fc|sfc>             生成完整 clip 并跑全部资源契约门禁
///
/// 设计：所有子命令零 IO、零渲染依赖（apphead 的软件光栅不需要窗口）。
fn cmd_retro(args : Array[String]) -> Unit {
  if args.length() < 3 {
    println("{\"error\":\"retro 需要子命令: hero|ascii|chr|palette|identify|check\"}")
    @bridge.exit(1)
    return
  }
  let sub = args[2]
  if sub == "palette" {
    println(@retro.fc_palette_text())
    @bridge.exit(0)
    return
  }
  let plat = if args.length() > 3 { args[3] } else { "fc" }
  let r : @retro.Retro = if plat == "sfc" { @retro.SFC } else { @retro.FC }
  let pose = if args.length() > 4 { args[4] } else { "idle" }
  let preset = match arg_after(args, "--preset") {
    Some(p) => p
    None => "plumber"
  }
  let spec = retro_spec_of(preset)
  match sub {
    "hero" => {
      let scale = match arg_after(args, "--scale") {
        Some(v) => parse_int_or(v, 8)
        None => 8
      }
      let c = retro_clip_of(r, spec)
      println(@retro.clip_svg(c, scale))
      @bridge.exit(0)
    }
    "presets" => {
      // 自省：agent 要知道有哪些具名造型可用
      let names = ["plumber", "green_cap", "tan_hero", "ninja", "ice", "fire"]
      let mut s = "{\"presets\":["
      let mut i = 0
      for n in names {
        if i > 0 {
          s = s + ","
        }
        s = s + "\"" + n + "\""
        i = i + 1
      }
      s = s + "]}"
      println(s)
      @bridge.exit(0)
    }
    "ascii" => {
      println(@retro.frame_ascii(retro_frame_of(r, spec, pose)))
      @bridge.exit(0)
    }
    "chr" => {
      let f = retro_frame_of(r, spec, pose)
      println(@retro.chr_hexdump(@retro.to_chr(f), 8))
      @bridge.exit(0)
    }
    "svg" => {
      let f = retro_frame_of(r, spec, pose)
      let pal = @retro.fc_sprite_palette(spec.cap, spec.skin, spec.cloth)
      let scale = match arg_after(args, "--scale") {
        Some(v) => parse_int_or(v, 16)
        None => 16
      }
      println(@retro.frame_svg(f, pal, scale))
      @bridge.exit(0)
    }
    "identify" => {
      println(retro_identify_json(r, pose, preset))
      @bridge.exit(0)
    }
    "check" => {
      let c = retro_clip_of(r, spec)
      println(@retro.clip_report(c))
      @bridge.exit(if c.errors.length() > 0 { 2 } else { 0 })
    }
    _ => {
      println("{\"error\":\"unknown retro subcommand \{sub}\"}")
      @bridge.exit(1)
    }
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
/// 角色造型 preset：具名而非手写色值——blueprint §6.3
/// 「name it, do not hand-describe it」：名字本身就是美术指令。
/// 可用：plumber / green_cap / tan_hero / ninja / ice / fire
fn retro_demo_spec() -> @retro.HeroSpec {
  @retro.preset_by_name("plumber")
}

///|
/// preset 名 → HeroSpec（CLI 的 --preset 入口）
fn retro_spec_of(name : String) -> @retro.HeroSpec {
  @retro.preset_by_name(name)
}

///|
fn retro_demo_poses() -> Array[String] {
  ["idle", "walk1", "walk2", "jump", "fall", "duck"]
}

///|
fn retro_clip_of(r : @retro.Retro, spec : @retro.HeroSpec) -> @retro.Clip {
  @retro.hero_clip("hero", spec, r, retro_demo_poses())
}

///|
fn retro_frame_of(r : @retro.Retro, spec : @retro.HeroSpec, pose : String) -> @retro.Frame {
  let (w, h) = match r {
    @retro.SFC => (16, 16)
    _ => (8, 16)
  }
  @retro.hero_frame(@retro.spec_with_pose(spec, pose), w, h)
}

///|
/// 资源识别闭环（JSON）：生成 → CHR → 读回 → 颜色普查 → 合规裁决
///
/// 这是"识别能力"的可核对形态：它不是"看图说话"，而是从字节里
/// 把资源读回来，逐项核对硬件契约。
fn retro_identify_json(r : @retro.Retro, pose : String, preset : String) -> String {
  let spec = retro_spec_of(preset)
  let f = retro_frame_of(r, spec, pose)
  let pal = @retro.fc_sprite_palette(spec.cap, spec.skin, spec.cloth)
  let chr = @retro.to_chr(f)
  let back = @retro.from_chr(chr, f.w, f.h)
  // 往返核对
  let mut identical = true
  let mut i = 0
  while i < f.pix.length() {
    if back.pix[i] != f.pix[i] {
      identical = false
      break
    }
    i = i + 1
  }
  // 展平 RGB → 颜色普查（**剔除透明**：洋红不是第 4 色，是"没有颜色"）
  let rgb_all = @retro.frame_to_rgb(f, pal)
  let rgb = @retro.frame_to_rgb_opaque(f, pal)
  let cen = @retro.census(rgb)
  let cen_all = @retro.census(rgb_all)
  let budget = @retro.sprite_colors(r)
  let q = @retro.quantize_fc(rgb, budget)
  let transp = @retro.transparent_count(f)
  let mut s = "{\"ok\":"
  s = s + (if identical && cen.distinct <= budget { "true" } else { "false" })
  s = s + ",\"platform\":\"\{@retro.retro_name(r)}\",\"pose\":\"\{pose}\""
  s = s + ",\"size\":[\{f.w},\{f.h}],\"chr_bytes\":\{chr.length()}"
  s = s + ",\"roundtrip_identical\":\{identical}"
  s = s + ",\"tiles_per_frame\":\{@retro.tiles_per_sprite(f.w, f.h)}"
  s = s + ",\"palette_size\":\{pal.length()}"
  s = s + ",\"colors_used\":\{@retro.distinct_indices([f])},\"color_budget\":\{budget}"
  s = s + ",\"distinct_opaque\":\{cen.distinct},\"distinct_with_alpha\":\{cen_all.distinct}"
  s = s + ",\"transparent_px\":\{transp},\"opacity\":\{pct(transp, f.pix.length())}"
  s = s + ",\"sprites_per_scanline\":\{@retro.sprites_per_scanline(r)}"
  s = s + ",\"quantized_to_fc_palette\":\{q.unique.length()}"
  s = s + ",\"errors\":["
  let mut k = 0
  for e in q.errors {
    if k > 0 {
      s = s + ","
    }
    s = s + "\"" + e + "\""
    k = k + 1
  }
  s = s + "]}"
  s
}

///|
fn pct(a : Int, b : Int) -> Int {
  if b == 0 {
    0
  } else {
    a * 100 / b
  }
}

///|
/// 交互游玩：真实键盘 → 语义输入 → 内核步进 → 渲染
fn cmd_run(path : String) -> Unit {
  let spec = match load_spec(path) {
    Some(s) => s
    None => {
      @bridge.exit(1)
      return
    }
  }
  let title = "deepengine — \{spec.title}"
  @bridge.mbg_init(title, spec.w, spec.h, 0)
  @bridge.mbg_audio_init() // 程序化音效（无硬件则静默降级）
  // 两族各自持有可变状态；热重载重建时保持同步
  let mut g = spec.build()
  let mut gg = spec.build_grid()
  // 音效事件沿（上一帧状态/金币/跳跃沿）
  let mut prev_state = "playing"
  let mut prev_coins = 0
  let mut prev_jump = false
  while @bridge.mbg_should_close() == 0 {
    // R 热重载（廉价迭代闭环）
    if @bridge.mbg_key_down(@bridge.KEY_R) == 1 {
      match load_spec(path) {
        Some(s2) => {
          g = s2.build()
          gg = s2.build_grid()
          println("{\"reloaded\":true}")
        }
        None => ()
      }
    }
    if @bridge.mbg_key_down(@bridge.KEY_ESCAPE) == 1 {
      break
    }
    if spec.mode == "grid" {
      // grid：离散方向步进（按下沿触发一次）
      if @bridge.mbg_key_down(@bridge.KEY_LEFT) == 1 {
        grid_move_once(gg, "left")
      }
      if @bridge.mbg_key_down(@bridge.KEY_RIGHT) == 1 {
        grid_move_once(gg, "right")
      }
      if @bridge.mbg_key_down(@bridge.KEY_UP) == 1 {
        grid_move_once(gg, "up")
      }
      if @bridge.mbg_key_down(@bridge.KEY_DOWN) == 1 {
        grid_move_once(gg, "down")
      }
      @bridge.mbg_begin_frame()
      draw_grid(gg, spec.g_cell)
      @bridge.mbg_end_frame()
    } else {
      let input : @kernel.Input = {
        left: @bridge.mbg_key_down(@bridge.KEY_LEFT) == 1,
        right: @bridge.mbg_key_down(@bridge.KEY_RIGHT) == 1,
        jump: @bridge.mbg_key_down(@bridge.KEY_SPACE) == 1,
      }
      if input.jump && !prev_jump {
        @bridge.mbg_sfx("jump")
      }
      prev_jump = input.jump
      @kernel.step(g, input)
      if g.coins_taken > prev_coins {
        @bridge.mbg_sfx("coin")
        prev_coins = g.coins_taken
      }
      if g.state != prev_state {
        if g.state == "won" {
          @bridge.mbg_sfx("win")
        }
        if g.state == "dead" {
          @bridge.mbg_sfx("dead")
        }
        prev_state = g.state
      }
      @bridge.mbg_begin_frame()
      draw(g)
      @bridge.mbg_end_frame()
    }
  }
  @bridge.mbg_close()
  @bridge.exit(0)
}

///|
/// 契约指纹源文本：指引路径取「指引 + 全部已载入内容源」，
/// inline 路径取原文件内容。
///
/// 理由（blueprint §3.5）：证据绑定指纹以检测"证据过期"。若只哈希指引
/// 文件，内容源改动不会让旧证据作废——这是把指纹做弱的漏洞。
fn fingerprint_source(path : String) -> String {
  if !is_guide_path(path) {
    return @bridge.mbg_read_file(path)
  }
  let guide_src = @bridge.mbg_read_file(path)
  let guide = @scene.parse_guide(guide_src)
  let base_dir = dir_of(path)
  let mut acc = guide_src
  for s in guide.sources {
    let full = join_path(base_dir, s.path)
    if @bridge.mbg_file_exists(full) != 0 {
      acc = acc + "\n--- source: \{s.name} (\{s.parser}) \{s.path} ---\n" + @bridge.mbg_read_file(full)
    } else {
      acc = acc + "\n--- source: \{s.name} (\{s.parser}) \{s.path} [missing] ---\n"
    }
  }
  acc
}

///|
/// headless 验证：探针（纯内核）→ 报告 → 截图证据
fn cmd_verify(path : String, shot : String?) -> Unit {
  let spec = match load_spec(path) {
    Some(s) => s
    None => {
      @bridge.exit(1)
      return
    }
  }
  let source = fingerprint_source(path)
  // 1) 探针全在内核层跑（无渲染依赖——Mechanic 契约）；按原型族分派
  let report = if spec.mode == "grid" {
    @kernel.verify_grid(spec.build_grid(), spec.probes)
  } else {
    @kernel.verify(spec.build(), spec.probes)
  }

  // 2) 截图证据：回放首个声明脚本（或默认脚本）并逐帧渲染，末帧截图
  match shot {
    Some(p) => {
      let script : String = if spec.probes.length() > 0 {
        spec.probes[0].script
      } else if spec.mode == "grid" {
        "right:3"
      } else {
        "right:90"
      }
      replay_and_shoot(spec, script, p)
      println("{\"screenshot\":\"\{p}\"}")
    }
    None => ()
  }

  // 3) 报告（stdout 协议，agent 直接消费）
  println(@kernel.report_json(report, source))
  @bridge.exit(if report.reward == 1 {
    0
  } else {
    2
  })
}

///|
/// 确定性截图：回放脚本逐帧渲染，到末帧截图
fn cmd_shot(path : String, frame_arg : String?, out_arg : String?) -> Unit {
  let spec = match load_spec(path) {
    Some(s) => s
    None => {
      @bridge.exit(1)
      return
    }
  }
  let out = match out_arg {
    Some(p) => p
    None => "shot.png"
  }
  let script : String = if spec.probes.length() > 0 {
    spec.probes[0].script
  } else {
    "right:90"
  }
  // --frame N：截到第 N 帧的画面（在脚本回放里推进到 N 或脚本末尾）
  replay_and_shoot(spec, script, out)
  println("{\"screenshot\":\"\{out}\"}")
  @bridge.exit(0)
}

///|
/// grid 交互步进（按住方向连走——60fps 下的手感可接受，MVP 取舍）
fn grid_move_once(g : @kernel.GridGame, dir : String) -> Unit {
  @kernel.grid_step(g, dir)
}

///|
/// 回放脚本（带渲染），到末帧截图。窗口隐藏——headless 语义。
fn replay_and_shoot(spec : @scene.GameSpec, script : String, out : String) -> Unit {
  let title = "deepengine-verify"
  @bridge.mbg_init(title, spec.w, spec.h, 1)
  @bridge.mbg_set_fps(0) // 验证不限帧——尽快跑完（fork D1 后计时器可用，这里显式关限速）
  if spec.mode == "grid" {
    let gg = spec.build_grid()
    let cmds = split_script_dirs(script)
    @bridge.mbg_begin_frame()
    draw_grid(gg, spec.g_cell)
    @bridge.mbg_end_frame()
    for c in cmds {
      let (dir, frames) = c
      let mut f = 0
      while f < frames {
        @kernel.grid_step(gg, dir)
        @bridge.mbg_begin_frame()
        draw_grid(gg, spec.g_cell)
        @bridge.mbg_end_frame()
        f = f + 1
      }
    }
  } else {
    let g = spec.build()
    let cmds = split_script(script)
    @bridge.mbg_begin_frame()
    draw(g)
    @bridge.mbg_end_frame()
    for c in cmds {
      let (left, right, jump, frames) = c
      let mut f = 0
      while f < frames {
        @kernel.step(g, { left: left, right: right, jump: jump })
        @bridge.mbg_begin_frame()
        draw(g)
        @bridge.mbg_end_frame()
        f = f + 1
      }
    }
  }
  @bridge.mbg_screenshot(out)
  @bridge.mbg_close()
}

///|
/// 脚本 → [(left,right,jump,frames)] 指令流（与 kernel 的私有解析器同语法）
fn split_script(script : String) -> Array[(Bool, Bool, Bool, Int)] {
  let out : Array[(Bool, Bool, Bool, Int)] = []
  let toks : Array[StringView] = script.split(",").iter().collect()
  for tok in toks {
    let t = tok.trim().to_owned()
    if t.length() == 0 {
      continue
    }
    let parts : Array[StringView] = t.split(":").iter().collect()
    let head = parts[0].trim().to_owned()
    let n : Int = if parts.length() > 1 {
      let raw = parts[1].trim().to_owned()
      let mut v = 0
      let mut ok = raw.length() > 0
      for ch in raw {
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
        1
      }
    } else {
      1
    }
    match head {
      "right" => out.push((false, true, false, n))
      "left" => out.push((true, false, false, n))
      "jump" => out.push((false, false, true, n))
      "wait" => out.push((false, false, false, n))
      _ => ()
    }
  }
  out
}

///|
/// grid 脚本 → [(方向, 帧数)]
fn split_script_dirs(script : String) -> Array[(String, Int)] {
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
      match parse_count(parts[1]) {
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
fn parse_count(v : StringView) -> Int? {
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
fn parse_int_arg(text : String) -> Int? {
  let t = text.trim().to_owned()
  if t.length() == 0 {
    return None
  }
  let mut v = 0
  for ch in t {
    let d = "0123456789".find(ch.to_string())
    match d {
      Some(x) => v = v * 10 + x
      None => return None
    }
  }
  Some(v)
}
