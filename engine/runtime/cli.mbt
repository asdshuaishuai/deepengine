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
        s = s + ",\"probes\":\{spec.probes.length()},\"solids\":\{spec.solids.length()},\"coins\":\{spec.coins.length()}"
        s = s + ",\"policies_declared\":\{spec.policies.length()},\"criteria_declared\":\{spec.criteria.length()}}"
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
      // 体验裁决面自省：agent 必须能看到"trace 会用什么策略去测、按什么标准判"
      // （声明为空时如实报告将走的缺省策略——否则 inspect 会掩盖实际行为）
      let eff = @scene.policies_of(spec)
      s = s + ",\"policies_declared\":\{spec.policies.length()}"
      s = s + ",\"policies_effective\":" + @scene.policies_json(eff)
      s = s + ",\"criteria_declared\":\{spec.criteria.length()}"
      s = s + ",\"prefer\":["
      let mut pi = 0
      for k in spec.prefer {
        if pi > 0 {
          s = s + ","
        }
        s = s + "\"" + k + "\""
        pi = pi + 1
      }
      s = s + "]"
      s = s + "}"
    }
    None => s = s + ",\"ok\":false,\"warnings\":\{asm.warnings.length()},\"errors\":\{asm.errors.length()}}"
  }
  println(s)
  @bridge.exit(if asm.errors.length() > 0 || cfg.errors.length() > 0 { 1 } else { 0 })
}

// ---------------- 体验裁决面（blueprint §3.9）----------------
//
// 编排（策略集 → 轨迹 → 聚合）在 scene/experience.mbt 只有一份：
// 本层只做分派、JSON 组装与退出码——native 与 wasm 面共用同一份评估路径。

///|
/// trace：程序化玩家策略 → 轨迹 → 体验度量 + 标准裁决（零渲染、零 LLM）
///
/// exit 0 = 全部标准通过（或未声明标准）；2 = 有标准未过；1 = 装配失败。
fn cmd_trace(path : String) -> Unit {
  let spec = match load_spec(path) {
    Some(s) => s
    None => {
      @bridge.exit(1)
      return
    }
  }
  let policies = @scene.policies_of(spec)
  let exp = @scene.run_experience(spec)
  let crs = @kernel.eval_criteria(exp, spec.criteria)
  let mut failed = 0
  for r in crs {
    if !r.pass {
      failed = failed + 1
    }
  }
  let mut s = "{\"experience\":" + @kernel.experience_json(exp)
  s = s + ",\"criteria\":" + @kernel.criteria_json(crs)
  s = s + ",\"policies\":" + @scene.policies_json(policies)
  s = s + ",\"criteria_failed\":\{failed}}"
  println(s)
  @bridge.exit(if failed > 0 {
    2
  } else {
    0
  })
}

///|
/// compare：同一游戏两版（A 基线 / B 候选）裁决——**判据与探针都从 A 冻结**。
///
/// exit 0 = accept_b；2 = keep_a；3 = inconclusive；**4 = 检测到操弄判据（gate shopping）**；1 = 装配失败。
///
/// v1.4 曾让标准优先取 B 声明的（"候选版本要达到的质量门才是门"）。那在**单轮**里看着无害，
/// 实际是一个真实漏洞：候选自带一份宽松的 `criteria.json` 就能把打不通的关卡判成 `accept_b`
/// （实测 `compare base c3_selfserving → exit 0`）。判据是**尺子**，尺子不能由被量的那一方提供。
/// 现在与 `rsi` 共用同一个裁决单元（`kernel.judge_versions`）：判据取自 A、探针集取 A 声明的，
/// B 自己的声明只作对照并标记 `criteria_drift` / `gate_shopping` / `policy_drift` / `mode_drift`。
fn cmd_compare(a_path : String, b_path : String) -> Unit {
  let spec_a = match load_spec(a_path) {
    Some(s) => s
    None => {
      @bridge.exit(1)
      return
    }
  }
  let spec_b = match load_spec(b_path) {
    Some(s) => s
    None => {
      @bridge.exit(1)
      return
    }
  }
  // 冻结：判据 + 偏好序 + 策略集，全部取自基线 A
  let pol_a = @scene.policies_of(spec_a)
  let base_key = @scene.policy_set_key(pol_a)
  let gate = @kernel.gate_of(spec_a.criteria, spec_a.prefer)
  let exp_a = @scene.run_experience(spec_a)
  let exp_b = @scene.run_experience_with(spec_b, pol_a)
  let cand : @kernel.Candidate = {
    name: b_path,
    exp: exp_b,
    criteria: spec_b.criteria,
    policy_key: @scene.declared_policy_key(spec_b),
  }
  let j = @kernel.judge_versions(exp_a, base_key, cand, gate)
  let d = j.decision
  let mut s = "{\"decision\":" + @kernel.decision_json(d)
  s = s + ",\"gate\":" + @kernel.gate_json(gate)
  s = s + ",\"a\":{\"path\":\"" + a_path + "\",\"experience\":" + @kernel.experience_json(exp_a)
  s = s + ",\"criteria\":" + @kernel.criteria_json(@kernel.eval_criteria(exp_a, gate.criteria)) + "}"
  s = s + ",\"b\":{\"path\":\"" + b_path + "\",\"experience\":" + @kernel.experience_json(exp_b)
  s = s + ",\"criteria\":" + @kernel.criteria_json(@kernel.eval_criteria(exp_b, gate.criteria)) + "}"
  // policies = 实际使用的**冻结**探针集；policies_declared_b = B 自己声明的（可能不同）
  s = s + ",\"policies\":" + @scene.policies_json(pol_a)
  s = s + ",\"policies_declared_b\":" + @scene.policies_json(@scene.policies_of(spec_b))
  s = s + ",\"frozen_passed\":" + j.frozen_passed.to_string()
  s = s + ",\"self_passed\":" + j.self_passed.to_string()
  s = s + ",\"criteria_drift\":" + j.criteria_drift.to_string()
  s = s + ",\"gate_shopping\":" + j.gate_shopping.to_string()
  s = s + ",\"policy_drift\":" + j.policy_drift.to_string()
  s = s + ",\"mode_drift\":" + j.mode_drift.to_string()
  s = s + ",\"policy_set_mismatch\":" + j.policy_drift.to_string() + "}"
  println(s)
  let v = @kernel.verdict_name(d.verdict)
  // 操弄优先报：靠换尺子"更好看"必须比 accept/keep 更响
  @bridge.exit(if j.gate_shopping {
    4
  } else if v == "accept_b" {
    0
  } else if v == "keep_a" {
    2
  } else {
    3
  })
}

// ---------------- 递归自改进面（RSI，blueprint §3.10）----------------
//
// `compare` 是一次性裁决；递归自改进要跑**多轮**，而多轮会引入两个新问题：
//   1) 候选可能改写评判自己的判据（gate shopping）→ 判据在 run 开始**冻结**；
//   2) 无界迭代会把"反复小改"当进步 → 预算 + 连续被拒即停。
// 台账（stdout 单文档，可重定向存盘）记下血统与停止原因，`rsi check` 可复算。

///|
/// 台账 JSON 字段读取（缺失一律给安全默认，由调用方校验）
fn jstr(o : @scene.Json, k : String) -> String? {
  match @scene.json_get(o, k) {
    Some(v) => @scene.json_as_str(v)
    None => None
  }
}

///|
fn jint(o : @scene.Json, k : String) -> Int? {
  match @scene.json_get(o, k) {
    Some(v) =>
      match @scene.json_as_num(v) {
        Some(n) => Some(n.to_int())
        None => None
      }
    None => None
  }
}

///|
fn jbool(o : @scene.Json, k : String) -> Bool? {
  match @scene.json_get(o, k) {
    Some(v) => @scene.json_as_bool(v)
    None => None
  }
}

///|
fn jobj(o : @scene.Json, k : String) -> @scene.Json? {
  @scene.json_get(o, k)
}

///|
fn jarr(o : @scene.Json, k : String) -> Array[@scene.Json] {
  match @scene.json_get(o, k) {
    Some(v) =>
      match @scene.json_as_arr(v) {
        Some(a) => a
        None => []
      }
    None => []
  }
}

///|
/// 从台账还原冻结门——**判据取自台账而不是当前文件**。
///
/// 若改成"重新读基线声明的标准"，那么"事后把基线标准改松"这件事会被悄悄吞掉：
/// 复算会用新尺子量旧记录，然后报告"一致"。审计要的恰恰相反。
fn gate_from_ledger(g : @scene.Json, errs : Array[String]) -> @kernel.Gate {
  let cs : Array[@kernel.Criterion] = []
  for item in jarr(g, "criteria") {
    let name = match jstr(item, "name") {
      Some(v) => v
      None => ""
    }
    let metric = match jstr(item, "metric") {
      Some(v) => v
      None => ""
    }
    let op = match jstr(item, "op") {
      Some(v) => v
      None => ""
    }
    let value = match jint(item, "value") {
      Some(v) => v
      None => 0
    }
    if name == "" || metric == "" || op == "" {
      errs.push("台账里有一条标准缺 name/metric/op")
    }
    cs.push({ name: name, metric: metric, op: op, value: value })
  }
  let prefer : Array[String] = []
  for item in jarr(g, "prefer") {
    match @scene.json_as_str(item) {
      Some(v) => prefer.push(v)
      None => errs.push("prefer 里有非字符串项")
    }
  }
  @kernel.gate_of(cs, prefer)
}

///|
/// rsi run：冻结门多轮驱动（base 为基线，其余为按序候选）
///
/// 退出码：0 = 至少有改进被接受；2 = 一轮都没接受；3 = 检测到操弄判据（最严重，优先报）；
/// 1 = 装配失败或参数错。
fn cmd_rsi_run(args : Array[String]) -> Unit {
  let paths : Array[String] = []
  let mut budget = 5
  let mut stall = 2
  let mut i = 3
  while i < args.length() {
    let a = args[i]
    if a == "--budget" || a == "--stall" {
      let v = if i + 1 < args.length() {
        match parse_int_arg(args[i + 1]) {
          Some(x) => x
          None => 0
        }
      } else {
        0
      }
      if a == "--budget" {
        budget = v
      } else {
        stall = v
      }
      i = i + 2
    } else {
      paths.push(a)
      i = i + 1
    }
  }
  if paths.length() < 2 || budget < 1 || stall < 1 {
    println(
      "{\"error\":\"用法：rsi run <base.guide.md> <cand.guide.md>... [--budget N>=1] [--stall N>=1]\"}",
    )
    @bridge.exit(1)
    return
  }
  let base_path = paths[0]
  let base_spec = match load_spec(base_path) {
    Some(s) => s
    None => {
      @bridge.exit(1)
      return
    }
  }
  let base_exp = @scene.run_experience(base_spec)
  let gate = @kernel.gate_of(base_spec.criteria, base_spec.prefer)
  // 冻结策略集：候选一律用**基线声明的**策略集测（否则"多带几条策略"就能抬高覆盖率）
  let base_policies = @scene.policies_of(base_spec)
  let cfg : @kernel.RsiConfig = {
    gate: gate,
    policies_digest: @scene.policy_set_key(base_policies),
    budget: budget,
    stall_limit: stall,
  }
  let cands : Array[@kernel.Candidate] = []
  let mut j = 1
  while j < paths.length() {
    let p = paths[j]
    let sp = match load_spec(p) {
      Some(s) => s
      None => {
        @bridge.exit(1)
        return
      }
    }
    cands.push({
      name: p,
      exp: @scene.run_experience_with(sp, base_policies),
      criteria: sp.criteria,
      policy_key: @scene.declared_policy_key(sp),
    })
    j = j + 1
  }
  let run = @kernel.run_rsi(base_path, base_exp, cfg, cands)
  println(@kernel.rsi_json(run))
  let mut shopping = false
  for r in run.rounds {
    if r.gate_shopping {
      shopping = true
    }
  }
  @bridge.exit(if shopping {
    3
  } else if run.accepted > 0 {
    0
  } else {
    2
  })
}

///|
/// rsi check：按台账复算——台账不可复算等于审计链断了（§9.2）。
///
/// 退出码：0 = 逐轮复算一致；2 = 有不一致（列出）；1 = 读不了/不是合法台账。
fn cmd_rsi_check(path : String) -> Unit {
  if @bridge.mbg_file_exists(path) == 0 {
    println("{\"ok\":false,\"error\":\"file not found: \{path}\"}")
    @bridge.exit(1)
    return
  }
  let (doc, perrs) = @scene.parse_text(@bridge.mbg_read_file(path))
  let root = match doc {
    Some(j) => j
    None => {
      println(
        "{\"ok\":false,\"error\":\"台账不是合法 JSON\",\"parse_errors\":\{perrs.length()}}",
      )
      @bridge.exit(1)
      return
    }
  }
  let mismatches : Array[String] = []
  let gate_obj = match jobj(root, "gate") {
    Some(g) => g
    None => {
      println("{\"ok\":false,\"error\":\"台账缺 gate\"}")
      @bridge.exit(1)
      return
    }
  }
  let gate_errs : Array[String] = []
  let gate = gate_from_ledger(gate_obj, gate_errs)
  for e in gate_errs {
    mismatches.push(e)
  }
  let rec_gate_digest = match jstr(gate_obj, "digest") {
    Some(v) => v
    None => ""
  }
  if rec_gate_digest != gate.digest {
    mismatches.push(
      "台账的判据文本与其自带指纹不符（记录 \{rec_gate_digest}，按文本重算 \{gate.digest}）",
    )
  }
  let base_path = match jobj(root, "base") {
    Some(b) =>
      match jstr(b, "path") {
        Some(v) => v
        None => ""
      }
    None => ""
  }
  if base_path == "" {
    println("{\"ok\":false,\"error\":\"台账缺 base.path\"}")
    @bridge.exit(1)
    return
  }
  let budget = match jint(root, "budget") {
    Some(v) => v
    None => 5
  }
  let stall = match jint(root, "stall_limit") {
    Some(v) => v
    None => 2
  }
  // 逐轮记录的候选路径（台账里的 cand.path 是复算入口）
  let rec_cand_path : Array[String] = []
  let rec_cand_digest : Array[String] = []
  let rec_accepted : Array[Bool] = []
  let rec_verdict : Array[String] = []
  let rec_frozen : Array[Int] = []
  let rec_policy_drift : Array[Bool] = []
  let rec_mode_drift : Array[Bool] = []
  for r in jarr(root, "rounds") {
    let cand = match jobj(r, "cand") {
      Some(c) => c
      None => @scene.Json::Null
    }
    rec_cand_path.push(
      match jstr(cand, "path") {
        Some(v) => v
        None => ""
      },
    )
    rec_cand_digest.push(
      match jstr(cand, "digest") {
        Some(v) => v
        None => ""
      },
    )
    rec_accepted.push(
      match jbool(r, "accepted") {
        Some(v) => v
        None => false
      },
    )
    rec_frozen.push(
      match jint(r, "frozen_passed") {
        Some(v) => v
        None => -1
      },
    )
    rec_policy_drift.push(
      match jbool(r, "policy_drift") {
        Some(v) => v
        None => false
      },
    )
    rec_mode_drift.push(
      match jbool(r, "mode_drift") {
        Some(v) => v
        None => false
      },
    )
    let dec = match jobj(r, "decision") {
      Some(d) => d
      None => @scene.Json::Null
    }
    rec_verdict.push(
      match jstr(dec, "verdict") {
        Some(v) => v
        None => ""
      },
    )
  }
  let rec_accepted_n = match jint(root, "accepted") {
    Some(v) => v
    None => -1
  }
  let rec_rejected_n = match jint(root, "rejected") {
    Some(v) => v
    None => -1
  }
  let rec_pol_digest = match jstr(root, "policies_digest") {
    Some(v) => v
    None => ""
  }
  let rec_stop = match jstr(root, "stop_reason") {
    Some(v) => v
    None => ""
  }
  let rec_incumbent = match jobj(root, "incumbent") {
    Some(b) =>
      match jstr(b, "digest") {
        Some(v) => v
        None => ""
      }
    None => ""
  }
  // 复算
  let base_spec = match load_spec(base_path) {
    Some(s) => s
    None => {
      @bridge.exit(1)
      return
    }
  }
  let base_exp = @scene.run_experience(base_spec)
  let base_policies = @scene.policies_of(base_spec)
  let live_pol_digest = @scene.policy_set_key(base_policies)
  let policies_drift = live_pol_digest != rec_pol_digest
  if policies_drift {
    mismatches.push("基线当前策略集与台账冻结的策略集不同——台账不再可复算（这是如实报告，不是失败）")
  }
  let cfg : @kernel.RsiConfig = {
    gate: gate,
    policies_digest: rec_pol_digest,
    budget: budget,
    stall_limit: stall,
  }
  let cands : Array[@kernel.Candidate] = []
  for p in rec_cand_path {
    let sp = match load_spec(p) {
      Some(s) => s
      None => {
        @bridge.exit(1)
        return
      }
    }
    cands.push({
      name: p,
      exp: @scene.run_experience_with(sp, base_policies),
      criteria: sp.criteria,
      policy_key: @scene.declared_policy_key(sp),
    })
  }
  let run = @kernel.run_rsi(base_path, base_exp, cfg, cands)
  for p in @kernel.rsi_problems(run) {
    mismatches.push("复算出的台账不自洽：" + p)
  }
  if run.rounds.length() != rec_cand_digest.length() {
    mismatches.push(
      "轮数不一致：台账 \{rec_cand_digest.length()}，复算 \{run.rounds.length()}",
    )
  }
  let mut k = 0
  for r in run.rounds {
    if k < rec_cand_digest.length() {
      if r.cand_digest != rec_cand_digest[k] {
        mismatches.push("第 \{k} 轮候选指纹不一致——候选内容在记账后被改过")
      }
      if r.accepted != rec_accepted[k] {
        mismatches.push("第 \{k} 轮接受/拒绝与台账不一致")
      }
      if @kernel.verdict_name(r.decision.verdict) != rec_verdict[k] {
        mismatches.push("第 \{k} 轮裁决与台账不一致")
      }
      if r.frozen_passed != rec_frozen[k] {
        mismatches.push("第 \{k} 轮冻结门通过数与台账不一致")
      }
      if r.policy_drift != rec_policy_drift[k] {
        mismatches.push("第 \{k} 轮策略集漂移标记与台账不一致")
      }
      if r.mode_drift != rec_mode_drift[k] {
        mismatches.push("第 \{k} 轮原型族漂移标记与台账不一致")
      }
    }
    k = k + 1
  }
  if run.accepted != rec_accepted_n || run.rejected != rec_rejected_n {
    mismatches.push("接受/拒绝计数与台账不一致")
  }
  if @kernel.stop_reason_name(run.stop_reason) != rec_stop {
    mismatches.push("停止原因与台账不一致")
  }
  if run.incumbent_digest != rec_incumbent {
    mismatches.push("血统末端指纹与台账不一致")
  }
  // 基线当前声明的门 vs 台账冻结的门：只报告，不改判（改了才好——如实说出来）
  let live_gate = @kernel.gate_of(base_spec.criteria, base_spec.prefer)
  let gate_drift = live_gate.digest != gate.digest
  if mismatches.length() == 0 {
    let mut s = "{\"ok\":true,\"rounds\":" + run.rounds.length().to_string()
    s = s + ",\"accepted\":" + run.accepted.to_string()
    s = s + ",\"stop_reason\":\"" + @kernel.stop_reason_name(run.stop_reason) + "\""
    s = s + ",\"incumbent\":\"" + run.incumbent + "\""
    s = s + ",\"gate_drift\":" + gate_drift.to_string()
    s = s + ",\"policies_drift\":" + policies_drift.to_string() + "}"
    println(s)
    @bridge.exit(0)
    return
  }
  let mut s = "{\"ok\":false,\"mismatches\":["
  let mut i = 0
  for m in mismatches {
    if i > 0 {
      s = s + ","
    }
    s = s + "\"" + m + "\""
    i = i + 1
  }
  s = s + "],\"gate_drift\":" + gate_drift.to_string()
  s = s + ",\"policies_drift\":" + policies_drift.to_string() + "}"
  println(s)
  @bridge.exit(2)
}

///|
/// rsi 子命令分派
fn cmd_rsi(args : Array[String]) -> Unit {
  if args.length() < 4 {
    println(
      "{\"error\":\"用法：rsi run <base.guide.md> <cand.guide.md>... | rsi check <ledger.json>\"}",
    )
    @bridge.exit(1)
    return
  }
  let sub = args[2]
  if sub == "run" {
    cmd_rsi_run(args)
  } else if sub == "check" {
    cmd_rsi_check(args[3])
  } else {
    println("{\"error\":\"unknown rsi subcommand: \{sub}\"}")
    @bridge.exit(1)
  }
}

///|
pub fn cli(args : Array[String]) -> Unit {
  if args.length() < 3 {
    println("usage: deepengine <run|verify|shot|inspect> <game.guide.md> [--shot p] [--frame N] [--out p]")
    println("       deepengine trace <game.guide.md>                     # 体验度量（策略→轨迹→度量→标准）")
    println("       deepengine compare <baseline.guide.md> <candidate.guide.md>  # 版本裁决（0=accept 2=keep 3=不可判 4=操弄判据）")
    println("       deepengine rsi run <base.guide.md> <cand.guide.md>... [--budget N] [--stall N]  # 递归自改进（冻结门多轮）")
    println("       deepengine rsi check <ledger.json>                   # 按台账复算（审计链）")
    println("       deepengine retro <hero|palette|chr|ascii|identify|check> [args]")
    println("       deepengine skin <seed>")
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
  // rsi <子命令>：递归自改进的选择半环（blueprint §3.10）
  if cmd == "rsi" {
    cmd_rsi(args)
    return
  }
  match cmd {
    "run" => cmd_run(path)
    "verify" => cmd_verify(path, arg_after(args, "--shot"))
    "trace" => cmd_trace(path)
    "compare" =>
      if args.length() < 4 {
        println("{\"error\":\"compare 需要两个入口：compare <baseline.guide.md> <candidate.guide.md>\"}")
        @bridge.exit(1)
      } else {
        cmd_compare(path, args[3])
      }
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
    let cmds = @kernel.grid_plan(script)
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
    let cmds = @kernel.script_plan(script)
    @bridge.mbg_begin_frame()
    draw(g)
    @bridge.mbg_end_frame()
    for c in cmds {
      let (input, frames) = c
      let mut f = 0
      while f < frames {
        @kernel.step(g, input)
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
