// metrics —— 体验度量与版本裁决（blueprint §3.9「体验裁决面」）。
//
// 参考落点：Recursive Game Creator（arXiv 2610.08621）的 **Reviewer**
// ——"uses carefully designed trajectory-based metrics to induce player preferences,
// integrating with visual evidence and explicit textual preferences to evaluate games
// against game-specific criteria. Finally, the Reviewer accepts the better version and
// provides improvement reviews for the next round, closing the recursive loop"；
// 以及 RSIGame 的递归自改进（接受更好的版本）。
//
// 引擎侧的翻译，三条硬纪律：
//   1. **度量只从轨迹来**。不是声明、不是截图、不是 VLM 打分——同轨迹必同度量；
//   2. **标准是显式文本**（criteria 内容源），不是藏在代码里的启发式；
//   3. **主分不动**。体验度量是诊断与裁决输入（accept/keep/inconclusive），
//      不参与 verify 的 binary 主分——两套分数各有职责，混在一起两个都不可信。
//
// 为什么"聚合"要上下限分离 + 覆盖并集：单条手写路径不能证明游戏可玩
// （RGC 指出的评估偏差）。多策略取并集回答的是"**至少存在**这样一条游玩轨迹"，
// 最差策略的停滞率回答的是"**最差会差到哪**"，stuck_ratio 回答"多少策略完全没进展"。

///|
/// 终局状态序（won 2 > playing 1 > dead 0）——版本比较的第一道硬门
pub fn outcome_rank(state : String) -> Int {
  if state == "won" {
    2
  } else if state == "playing" {
    1
  } else {
    0
  }
}

///|
fn pct(a : Int, b : Int) -> Int {
  if b <= 0 {
    0
  } else {
    a * 100 / b
  }
}

///|
fn clamp100(v : Int) -> Int {
  if v < 0 {
    0
  } else if v > 100 {
    100
  } else {
    v
  }
}

///|
fn max_i(a : Int, b : Int) -> Int {
  if a > b {
    a
  } else {
    b
  }
}

///|
fn iabs(v : Int) -> Int {
  if v < 0 {
    -v
  } else {
    v
  }
}

///|
/// 单条轨迹的体验度量（全部整型 → 逐字节确定）
pub(all) struct Metrics {
  frames : Int
  outcome : String
  outcome_rank : Int
  progress_pct : Int // 已完成目标 / 目标总数
  coverage_pct : Int // 访问格 / 场地格
  directness_pct : Int // 净位移 / 路径长度（乱走低、直奔目标高）
  stall_max : Int // 最长连续不动帧
  stall_ratio_pct : Int
  idle_ratio_pct : Int // 无输入帧占比
  diversity : Int // 用到的语义动作种类数
  action_switches : Int
  path_len : Int
  revisit_pct : Int // 重复踏入已访问格的比例
  jumps : Int
  truncated : Bool // 是否被帧数上限截断（诚实报告边界）
}

///|
pub fn metrics_of(t : Trace) -> Metrics {
  let frames = t.samples.length()
  let mut max_prog = 0
  for s in t.samples {
    if s.progress > max_prog {
      max_prog = s.progress
    }
  }
  let rank = outcome_rank(t.final_state)
  let progress_pct = if t.targets > 0 {
    clamp100(pct(max_prog, t.targets))
  } else if rank == 2 {
    // 没有可收集目标的游戏（纯到达型）：通关即 100
    100
  } else {
    0
  }
  let dx = iabs(t.end_x - t.start_x)
  let dy = iabs(t.end_y - t.start_y)
  {
    frames: frames,
    outcome: t.final_state,
    outcome_rank: rank,
    progress_pct: progress_pct,
    coverage_pct: clamp100(pct(t.cells.length(), t.arena_cells)),
    directness_pct: if t.path_len > 0 {
      clamp100(pct(dx + dy, t.path_len))
    } else {
      0
    },
    stall_max: t.stall_max,
    stall_ratio_pct: clamp100(pct(t.stalled_frames, frames)),
    idle_ratio_pct: clamp100(pct(t.idle_frames, frames)),
    diversity: t.actions.length(),
    action_switches: t.action_switches,
    path_len: t.path_len,
    revisit_pct: clamp100(pct(t.revisits, frames)),
    jumps: t.jumps,
    truncated: t.truncated,
  }
}

///|
/// 度量方向：+1 越大越好 / -1 越小越好 / 0 中性（只报告，不参与偏好序）
pub fn metric_dir(key : String) -> Int {
  match key {
    "outcome_rank" | "progress" | "coverage" | "directness" | "diversity" | "jumps" => 1
    "stall_max" | "stall_ratio" | "idle_ratio" | "revisit" | "stuck_ratio" | "stuck_policies" => -1
    _ => 0
  }
}

///|
/// 度量字段取值（Metrics 层；未知 key → None，由调用方决定"宁可假阴"）
pub fn metric_field(m : Metrics, key : String) -> Int? {
  match key {
    "frames" => Some(m.frames)
    "outcome_rank" => Some(m.outcome_rank)
    "progress" => Some(m.progress_pct)
    "coverage" => Some(m.coverage_pct)
    "directness" => Some(m.directness_pct)
    "stall_max" => Some(m.stall_max)
    "stall_ratio" => Some(m.stall_ratio_pct)
    "idle_ratio" => Some(m.idle_ratio_pct)
    "diversity" => Some(m.diversity)
    "action_switches" => Some(m.action_switches)
    "path_len" => Some(m.path_len)
    "revisit" => Some(m.revisit_pct)
    "jumps" => Some(m.jumps)
    _ => None
  }
}

///|
/// 全部可用的度量 key（自省 + 解析层 P0 门禁用）
pub fn known_metric(key : String) -> Bool {
  match key {
    "frames"
    | "outcome_rank"
    | "progress"
    | "coverage"
    | "directness"
    | "stall_max"
    | "stall_ratio"
    | "idle_ratio"
    | "diversity"
    | "action_switches"
    | "path_len"
    | "revisit"
    | "jumps"
    | "stuck_ratio"
    | "stuck_policies"
    | "policies" => true
    _ => false
  }
}

///|
/// 策略集上的体验。
///
/// `metrics` 是聚合：能力类取最优策略、风险类取最差策略、覆盖度用**并集**重算。
/// `stuck_ratio` = 一个目标都没完成且没通关的策略占比。
pub(all) struct Experience {
  mode : String
  n_policies : Int
  stuck_policies : Int
  stuck_ratio_pct : Int
  truncated_policies : Int
  cells_union : Int
  arena_cells : Int
  targets : Int
  metrics : Metrics // 聚合（coverage 用并集重算）
  per_policy : Array[(String, Metrics)]
  outcomes : Array[String]
}

///|
fn zero_metrics() -> Metrics {
  {
    frames: 0,
    outcome: "none",
    outcome_rank: 0,
    progress_pct: 0,
    coverage_pct: 0,
    directness_pct: 0,
    stall_max: 0,
    stall_ratio_pct: 0,
    idle_ratio_pct: 0,
    diversity: 0,
    action_switches: 0,
    path_len: 0,
    revisit_pct: 0,
    jumps: 0,
    truncated: false,
  }
}

///|
/// 聚合合并：**上下限分离**。
///
/// 能力类（进展/覆盖/直达/多样性）取最好那条——回答"**至多**能玩到什么程度"；
/// 风险类（停滞/闲置/重复）取最差那条——回答"**至少**会卡到什么程度"。
///
/// 两类都取单边会说谎：只看最好那条，"有一条路径会卡死"被吞掉；
/// 只看最差那条，一条笨策略就把可玩的上限抹平。
fn best_metrics(a : Metrics, b : Metrics) -> Metrics {
  {
    frames: max_i(a.frames, b.frames),
    outcome: if b.outcome_rank > a.outcome_rank {
      b.outcome
    } else {
      a.outcome
    },
    outcome_rank: max_i(a.outcome_rank, b.outcome_rank),
    progress_pct: max_i(a.progress_pct, b.progress_pct),
    coverage_pct: max_i(a.coverage_pct, b.coverage_pct),
    directness_pct: max_i(a.directness_pct, b.directness_pct),
    stall_max: max_i(a.stall_max, b.stall_max),
    stall_ratio_pct: max_i(a.stall_ratio_pct, b.stall_ratio_pct),
    idle_ratio_pct: max_i(a.idle_ratio_pct, b.idle_ratio_pct),
    diversity: max_i(a.diversity, b.diversity),
    action_switches: max_i(a.action_switches, b.action_switches),
    path_len: max_i(a.path_len, b.path_len),
    revisit_pct: max_i(a.revisit_pct, b.revisit_pct),
    jumps: max_i(a.jumps, b.jumps),
    truncated: a.truncated || b.truncated,
  }
}

///|
/// 策略集 → 体验聚合。traces 的 name 用于逐策略报告（可解释性）。
pub fn experience_of(traces : Array[(String, Trace)]) -> Experience {
  let per : Array[(String, Metrics)] = []
  let outcomes : Array[String] = []
  let union : Array[(Int, Int)] = []
  let mut n = 0
  let mut stuck = 0
  let mut truncated = 0
  let mut arena = 0
  let mut targets = 0
  let mut mode = ""
  let mut acc : Metrics? = None
  for item in traces {
    let (name, t) = item
    let m = metrics_of(t)
    per.push((name, m))
    outcomes.push(m.outcome)
    n = n + 1
    if t.arena_cells > arena {
      arena = t.arena_cells
    }
    if t.targets > targets {
      targets = t.targets
    }
    if t.mode != "" {
      mode = t.mode
    }
    if t.truncated {
      truncated = truncated + 1
    }
    // "毫无进展"：一个目标都没完成且没通关——不是"没赢"，是"没动起来"
    if m.progress_pct == 0 && m.outcome_rank < 2 {
      stuck = stuck + 1
    }
    for c in t.cells {
      let (cx, cy) = c
      if !in_cells(union, cx, cy) {
        union.push(c)
      }
    }
    acc = match acc {
      None => Some(m)
      Some(b) => Some(best_metrics(b, m))
    }
  }
  let agg = match acc {
    Some(m) => m
    None => zero_metrics()
  }
  // 覆盖度用**并集**重算：多策略各自没走到的格，合起来可能走到了
  let coverage = clamp100(pct(union.length(), arena))
  let agg2 : Metrics = {
    frames: agg.frames,
    outcome: agg.outcome,
    outcome_rank: agg.outcome_rank,
    progress_pct: agg.progress_pct,
    coverage_pct: coverage,
    directness_pct: agg.directness_pct,
    stall_max: agg.stall_max,
    stall_ratio_pct: agg.stall_ratio_pct,
    idle_ratio_pct: agg.idle_ratio_pct,
    diversity: agg.diversity,
    action_switches: agg.action_switches,
    path_len: agg.path_len,
    revisit_pct: agg.revisit_pct,
    jumps: agg.jumps,
    truncated: agg.truncated,
  }
  {
    mode: mode,
    n_policies: n,
    stuck_policies: stuck,
    stuck_ratio_pct: clamp100(pct(stuck, n)),
    truncated_policies: truncated,
    cells_union: union.length(),
    arena_cells: arena,
    targets: targets,
    metrics: agg2,
    per_policy: per,
    outcomes: outcomes,
  }
}

///|
/// 体验层取值（含只在策略集上才有意义的 stuck_ratio / policies）
pub fn metric_of(e : Experience, key : String) -> Int? {
  match key {
    "stuck_ratio" => Some(e.stuck_ratio_pct)
    "stuck_policies" => Some(e.stuck_policies)
    "policies" => Some(e.n_policies)
    _ => metric_field(e.metrics, key)
  }
}

///|
/// 默认偏好序（越大越好在前，越小越好在中）——RGC 的"player preferences"
/// 在引擎侧的可核对形态：**显式文本**，可由 criteria.json 的 prefer 覆盖。
pub fn default_preference() -> Array[String] {
  ["progress", "coverage", "directness", "stall_max", "stuck_ratio", "idle_ratio", "diversity"]
}

///|
/// 一条体验标准（game-specific criteria）
pub(all) struct Criterion {
  name : String
  metric : String
  op : String // == >= <= !=
  value : Int
}

///|
pub(all) struct CriterionResult {
  name : String
  pass : Bool
  detail : String
}

///|
/// 标准的实际取值（未知度量 → None → 判失败：宁可假阴不假阳）
fn criterion_actual(e : Experience, c : Criterion) -> Int? {
  metric_of(e, c.metric)
}

///|
/// 标准求值（逐条给 detail，agent 可自我修正）
pub fn eval_criteria(e : Experience, cs : Array[Criterion]) -> Array[CriterionResult] {
  let out : Array[CriterionResult] = []
  for c in cs {
    match criterion_actual(e, c) {
      None =>
        out.push({
          name: c.name,
          pass: false,
          detail: "未知度量 \{c.metric}（可用：见 metrics_json.known）",
        })
      Some(v) => {
        let ok = if c.op == "==" {
          v == c.value
        } else if c.op == "!=" {
          v != c.value
        } else if c.op == ">=" {
          v >= c.value
        } else if c.op == "<=" {
          v <= c.value
        } else {
          false
        }
        out.push({
          name: c.name,
          pass: ok,
          detail: "\{c.metric}=\{v} \{c.op} \{c.value}",
        })
      }
    }
  }
  out
}

///|
pub fn count_passed(rs : Array[CriterionResult]) -> Int {
  let mut n = 0
  for r in rs {
    if r.pass {
      n = n + 1
    }
  }
  n
}

///|
/// 版本裁决结论（RSIGame 的"接受更好版本"）
pub(all) enum Verdict {
  AcceptB // B 更好 → 接受候选
  KeepA // A 更好 → 保留基线
  Inconclusive // 无差别 → 不接受"改动即进步"
}

///|
pub fn verdict_name(v : Verdict) -> String {
  match v {
    AcceptB => "accept_b"
    KeepA => "keep_a"
    Inconclusive => "inconclusive"
  }
}

///|
pub(all) struct Decision {
  verdict : Verdict
  deciding : String // 决定项：criteria / outcome / <metric> / none
  reason : String
  a_passed : Int
  b_passed : Int
  criteria_total : Int
  used_criteria : Bool
  deltas : Array[(String, Int, Int)] // (metric, a, b) —— 全部可比项，不只决定项
}

///|
/// 版本裁决：**先硬门后偏好**。
///
///   1. 标准通过数（game-specific criteria = 这一版到底做没做到）——多者胜；
///   2. 终局序（won > playing > dead）——防止"覆盖度涨了但游戏打不通了"被接受；
///   3. 偏好序逐项比较（default_preference 或 criteria.json 的 prefer 显式声明）；
///   4. 全同 → inconclusive（**改动不等于进步**）。
pub fn adjudicate(
  a : Experience,
  b : Experience,
  criteria : Array[Criterion],
  prefer : Array[String]
) -> Decision {
  let ra = eval_criteria(a, criteria)
  let rb = eval_criteria(b, criteria)
  let pa = count_passed(ra)
  let pb = count_passed(rb)
  let order : Array[String] = if prefer.length() > 0 {
    prefer
  } else {
    default_preference()
  }
  // 全量 delta（可解释性：不只报决定项）
  let deltas : Array[(String, Int, Int)] = []
  let keys = [
    "outcome_rank", "progress", "coverage", "directness", "stall_max", "stuck_ratio", "idle_ratio",
    "diversity", "revisit", "jumps", "path_len", "frames",
  ]
  for k in keys {
    match (metric_of(a, k), metric_of(b, k)) {
      (Some(x), Some(y)) => deltas.push((k, x, y))
      _ => ()
    }
  }
  let mut verdict = Inconclusive
  let mut deciding = "none"
  let mut reason = "两版在全部可比度量上相同——不接受'改动即进步'"
  if criteria.length() > 0 && pa != pb {
    if pb > pa {
      verdict = AcceptB
      deciding = "criteria"
      reason = "候选通过标准 \{pb}/\{criteria.length()}，基线 \{pa}/\{criteria.length()}"
    } else {
      verdict = KeepA
      deciding = "criteria"
      reason = "基线通过标准 \{pa}/\{criteria.length()}，候选 \{pb}/\{criteria.length()}"
    }
  } else if a.metrics.outcome_rank != b.metrics.outcome_rank {
    if b.metrics.outcome_rank > a.metrics.outcome_rank {
      verdict = AcceptB
      deciding = "outcome"
      reason = "终局 \{a.metrics.outcome} → \{b.metrics.outcome}"
    } else {
      verdict = KeepA
      deciding = "outcome"
      reason = "终局 \{a.metrics.outcome} → \{b.metrics.outcome}"
    }
  } else {
    let mut i = 0
    while i < order.length() {
      let k = order[i]
      match (metric_of(a, k), metric_of(b, k)) {
        (Some(x), Some(y)) =>
          if x != y {
            let d = metric_dir(k)
            let b_better = if d < 0 { y < x } else { y > x }
            verdict = if b_better {
              AcceptB
            } else {
              KeepA
            }
            deciding = k
            reason = "\{k}: \{x} → \{y}（\{if d < 0 { "越小越好" } else { "越大越好" }}）"
            i = order.length() // 首个差异即决定——偏好序的意义就在"先后"
          } else {
            i = i + 1
          }
        _ => i = i + 1
      }
    }
  }
  {
    verdict: verdict,
    deciding: deciding,
    reason: reason,
    a_passed: pa,
    b_passed: pb,
    criteria_total: criteria.length(),
    used_criteria: criteria.length() > 0,
    deltas: deltas,
  }
}

// ---------------- JSON 产出（stdout 协议——agent 直接消费）----------------

///|
pub fn metrics_json(m : Metrics) -> String {
  let mut s = "{\"frames\":\{m.frames},\"outcome\":\"\{m.outcome}\",\"outcome_rank\":\{m.outcome_rank}"
  s = s + ",\"progress\":\{m.progress_pct},\"coverage\":\{m.coverage_pct}"
  s = s + ",\"directness\":\{m.directness_pct}"
  s = s + ",\"stall_max\":\{m.stall_max},\"stall_ratio\":\{m.stall_ratio_pct}"
  s = s + ",\"idle_ratio\":\{m.idle_ratio_pct},\"diversity\":\{m.diversity}"
  s = s + ",\"action_switches\":\{m.action_switches},\"path_len\":\{m.path_len}"
  s = s + ",\"revisit\":\{m.revisit_pct},\"jumps\":\{m.jumps}"
  s = s + ",\"truncated\":\{m.truncated}}"
  s
}

///|
pub fn experience_json(e : Experience) -> String {
  let mut s = "{\"mode\":\"\{e.mode}\",\"n_policies\":\{e.n_policies}"
  s = s + ",\"stuck_policies\":\{e.stuck_policies},\"stuck_ratio\":\{e.stuck_ratio_pct}"
  s = s + ",\"truncated_policies\":\{e.truncated_policies}"
  s = s + ",\"cells_union\":\{e.cells_union},\"arena_cells\":\{e.arena_cells}"
  s = s + ",\"targets\":\{e.targets}"
  s = s + ",\"metrics\":" + metrics_json(e.metrics)
  s = s + ",\"outcomes\":["
  let mut i = 0
  for o in e.outcomes {
    if i > 0 {
      s = s + ","
    }
    s = s + "\"" + o + "\""
    i = i + 1
  }
  s = s + "],\"per_policy\":["
  let mut j = 0
  for item in e.per_policy {
    let (name, m) = item
    if j > 0 {
      s = s + ","
    }
    s = s + "{\"name\":\"" + name + "\",\"metrics\":" + metrics_json(m) + "}"
    j = j + 1
  }
  s = s + "],\"known_metrics\":["
  let names = [
    "outcome_rank", "progress", "coverage", "directness", "stall_max", "stall_ratio", "idle_ratio",
    "diversity", "revisit", "jumps", "path_len", "frames", "stuck_ratio", "stuck_policies",
    "policies",
  ]
  let mut k = 0
  for n in names {
    if k > 0 {
      s = s + ","
    }
    s = s + "\"" + n + "\""
    k = k + 1
  }
  s = s + "]}"
  s
}

///|
pub fn criteria_json(rs : Array[CriterionResult]) -> String {
  let mut s = "["
  let mut i = 0
  for r in rs {
    if i > 0 {
      s = s + ","
    }
    s = s + "{\"name\":\"" + r.name + "\",\"pass\":" + r.pass.to_string()
    s = s + ",\"detail\":\"" + r.detail + "\"}"
    i = i + 1
  }
  s + "]"
}

///|
pub fn decision_json(d : Decision) -> String {
  let mut s = "{\"verdict\":\"" + verdict_name(d.verdict) + "\""
  s = s + ",\"deciding\":\"" + d.deciding + "\""
  s = s + ",\"reason\":\"" + d.reason + "\""
  s = s + ",\"criteria\":{\"used\":" + d.used_criteria.to_string()
  s = s + ",\"a_passed\":" + d.a_passed.to_string()
  s = s + ",\"b_passed\":" + d.b_passed.to_string()
  s = s + ",\"total\":" + d.criteria_total.to_string() + "}"
  s = s + ",\"deltas\":["
  let mut i = 0
  for item in d.deltas {
    let (k, a, b) = item
    if i > 0 {
      s = s + ","
    }
    s = s + "{\"metric\":\"" + k + "\",\"a\":" + a.to_string() + ",\"b\":" + b.to_string() + "}"
    i = i + 1
  }
  s + "]}"
}
