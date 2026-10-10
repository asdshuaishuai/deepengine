// rsi —— 递归自改进（RSIGame "recursive self-improvement"）的**选择半环**：
// 多轮候选 → 冻结门裁决 → 血统台账 → 可复算审计。
//
// 为什么不能直接循环调用一次性的 compare：
//
//   1. **判据漂移（最致命）**：`compare` 的标准取候选声明的（B 优先）。
//      单次比较这没问题；一旦一轮一轮地跑，候选就获得了**改写评判自己那把尺子**
//      的能力——把 `progress >= 100` 改成 `progress >= 0`，下一轮就"进步"了。
//      这是自改进闭环最经典的 reward hacking。本层在 run 开始时把判据**冻结**
//      （取自基线，候选无法影响），候选自己声明的门只作为**对照**记录，
//      并把"按它自己的门更好看"如实标成 `gate_shopping`。
//
//   2. **预算与停滞**：无界迭代会把"反复小改"当成进步。§5.3 的修复循环预算（T=5）
//      与"连续 N 轮被拒即停"在这里落成机械规则，而不是靠 agent 自觉。
//
//   3. **血统与可复算**：每轮记 base/cand 的体验指纹，`rsi check` 能按台账复算。
//      台账不可复算 = 审计链断了（§9.2 run 不可变）。
//
// **边界（同样是纪律）**：候选的产生（Designer/Builder）不是引擎的活。
// 本层只做"选择 + 记账 + 可核验"，绝不自己改关卡去"提升"度量（见 blueprint §11）。

///|
/// 停止原因：把"为什么停下"写成可判据，而不是沉默结束。
pub(all) enum StopReason {
  Exhausted // 候选用完
  Budget // 触及预算上限（§5.3）
  Stalled // 连续 N 轮被拒——继续试下去是在浪费预算
}

///|
pub fn stop_reason_name(r : StopReason) -> String {
  match r {
    Exhausted => "exhausted"
    Budget => "budget"
    Stalled => "stalled"
  }
}

///|
/// 冻结门：run 开始时定下的判据 + 生效偏好序 + 指纹。
pub(all) struct Gate {
  criteria : Array[Criterion]
  prefer : Array[String]
  digest : String
}

///|
/// 判据的规范文本（比较"候选有没有改门" + 算指纹）
pub fn criteria_key(cs : Array[Criterion]) -> String {
  let mut s = ""
  for c in cs {
    s = s + c.name + ":" + c.metric + c.op + c.value.to_string() + ";"
  }
  s
}

///|
/// 建门：prefer 为空则取引擎默认偏好序（生效值进台账，便于事后核对）
pub fn gate_of(criteria : Array[Criterion], prefer : Array[String]) -> Gate {
  let order : Array[String] = if prefer.length() > 0 {
    prefer
  } else {
    default_preference()
  }
  let mut s = criteria_key(criteria)
  s = s + "|prefer:"
  for k in order {
    s = s + k + ","
  }
  { criteria: criteria, prefer: order, digest: fingerprint(s) }
}

///|
/// 一次 run 的**冻结配置**：判据门 + 策略集指纹 + 预算/停滞阈值。
///
/// 三者都在 run 开始时定下、候选无法影响——这是自改进可信的前提。
/// 冻结策略集与冻结判据同样重要：覆盖度是策略并集算出来的，允许候选自带
/// 策略集，它就能靠"多声明几条探索策略"机械抬高覆盖率（外观还像"测得更全"）。
pub(all) struct RsiConfig {
  gate : Gate
  policies_digest : String
  budget : Int
  stall_limit : Int
}

///|
/// 体验指纹：只由**可复现的聚合事实**算出（模式 / 策略数 / 聚合度量 / 逐策略）。
/// 用途：台账里锚定"这一版是哪个版本"——输入被改过就不再匹配。
pub fn experience_digest(e : Experience) -> String {
  let mut s = e.mode + "|n" + e.n_policies.to_string()
  s = s + "|stuck" + e.stuck_policies.to_string() + "/" + e.stuck_ratio_pct.to_string()
  s = s + "|union" + e.cells_union.to_string() + "/" + e.arena_cells.to_string()
  s = s + "|targets" + e.targets.to_string()
  s = s + "|agg" + metrics_json(e.metrics)
  s = s + "|per:"
  for p in e.per_policy {
    let (n, m) = p
    s = s + n + "=" + metrics_json(m) + ";"
  }
  fingerprint(s)
}

///|
/// 候选（已求值）：名字（CLI 面传路径）+ 体验 + **它自己声明的**标准（可空）
pub(all) struct Candidate {
  name : String
  exp : Experience
  criteria : Array[Criterion]
  policy_key : String // 它**自己声明**的策略集指纹（未声明 → ""）；仅作对照
}

///|
/// 一次版本裁决的完整结果：裁决 + 四条"可比性/尺子"漂移标记。
///
/// **`compare`（单轮）与 `rsi`（多轮）共用它**——同一个引擎不能有两套裁决规则：
/// 各写一套的下场就是"`rsi` 修好了、`compare` 还留着同一个洞"（v1.4 实测：`compare` 会被
/// 候选自带的宽松判据骗到 `accept_b`）。
pub(all) struct Judgment {
  decision : Decision
  frozen_passed : Int // 按冻结门通过数（判定依据）
  self_passed : Int // 按候选自己声明的门通过数（仅对照）
  criteria_drift : Bool
  gate_shopping : Bool
  policy_drift : Bool
  mode_drift : Bool
}

///|
/// 用**冻结门**裁决两版，并把候选在"尺子/探针/原型族"上的改动如实标记出来。
///
/// 判定依据永远是 `gate`（run 开始时从基线冻结）；候选自己的门只作对照。
/// `base_policy_key` 是冻结策略集指纹：候选自己声明的策略集与它不同时标记 `policy_drift`
/// （意味着它独立跑 `trace` 的数字会和这里不一致）。
pub fn judge_versions(
  base_exp : Experience,
  base_policy_key : String,
  cand : Candidate,
  gate : Gate
) -> Judgment {
  let mode_drift = cand.exp.mode != base_exp.mode
  // 原型族不同 = 度量同名不同义（grid 的 progress 是"箱子归位"，physics 是"金币/终点"）。
  // 这时给出 accept/keep 都是**可比性谎言**——直接判不可裁决，并说明原因。
  let d = if mode_drift {
    {
      verdict: Inconclusive,
      deciding: "mode",
      reason: "模式不同（\{base_exp.mode} ≠ \{cand.exp.mode}）：度量同名不同义，不予裁决",
      a_passed: count_passed(eval_criteria(base_exp, gate.criteria)),
      b_passed: count_passed(eval_criteria(cand.exp, gate.criteria)),
      criteria_total: gate.criteria.length(),
      used_criteria: gate.criteria.length() > 0,
      deltas: [],
    }
  } else {
    adjudicate(base_exp, cand.exp, gate.criteria, gate.prefer)
  }
  let frozen = count_passed(eval_criteria(cand.exp, gate.criteria))
  let declared = cand.criteria.length() > 0
  let self_n = if declared {
    count_passed(eval_criteria(cand.exp, cand.criteria))
  } else {
    0
  }
  {
    decision: d,
    frozen_passed: frozen,
    self_passed: self_n,
    criteria_drift: declared && criteria_key(cand.criteria) != criteria_key(gate.criteria),
    gate_shopping: declared && self_n > frozen,
    policy_drift: cand.policy_key != base_policy_key,
    mode_drift,
  }
}

///|
/// 一轮的完整裁决记录（含"候选自己的门"对照——防操弄）
pub(all) struct Round {
  index : Int
  base_name : String
  cand_name : String
  base_digest : String
  cand_digest : String
  decision : Decision
  accepted : Bool
  frozen_passed : Int // 按冻结门通过数（**这是判定依据**）
  self_passed : Int // 按候选自己声明的门通过数（仅对照）
  criteria_drift : Bool // 候选声明的判据与冻结门不同
  gate_shopping : Bool // 按它自己的门比按冻结门更好看 → 想换尺子
  policy_drift : Bool // 它自己声明的策略集与冻结集不同（独立跑 trace 会对不上账）
  mode_drift : Bool // 原型族不同（physics vs grid）→ 度量同名不同义，不可比
}

///|
/// 一次自改进 run 的台账：血统（base → 每轮 → incumbent）+ 停止原因 + 计数。
pub(all) struct RsiRun {
  gate : Gate
  policies_digest : String
  base_name : String
  base_digest : String
  rounds : Array[Round]
  incumbent : String
  incumbent_digest : String
  accepted : Int
  rejected : Int
  stop_reason : StopReason
  budget : Int
  stall_limit : Int
}

///|
/// 一轮裁决：**一律用冻结门判**；候选自己的门只做对照。
///
/// `gate_shopping` 的判据是"按它自己的门严格更好看"——更宽的门必然更容易过。
/// 不拦（它可能只是换了表述），但必须如实标记：审计者一眼能看到。
fn judge_round(
  index : Int,
  base_name : String,
  base_exp : Experience,
  base_digest : String,
  cand : Candidate,
  cfg : RsiConfig
) -> Round {
  let j = judge_versions(base_exp, cfg.policies_digest, cand, cfg.gate)
  {
    index,
    base_name,
    cand_name: cand.name,
    base_digest,
    cand_digest: experience_digest(cand.exp),
    decision: j.decision,
    accepted: verdict_name(j.decision.verdict) == "accept_b",
    frozen_passed: j.frozen_passed,
    self_passed: j.self_passed,
    criteria_drift: j.criteria_drift,
    gate_shopping: j.gate_shopping,
    policy_drift: j.policy_drift,
    mode_drift: j.mode_drift,
  }
}

///|
/// 驱动一次自改进 run：
///
/// - 逐候选用**冻结门**裁决，接受则 incumbent 前移（血统），拒绝则 incumbent 不动；
/// - `budget` 轮上限（默认见 CLI 的 --budget，§5.3 T=5）；
/// - 连续 `stall_limit` 轮被拒即停（`stalled`）——不把预算烧在同一个死角上。
pub fn run_rsi(
  base_name : String,
  base_exp : Experience,
  cfg : RsiConfig,
  cands : Array[Candidate]
) -> RsiRun {
  let budget = cfg.budget
  let stall_limit = cfg.stall_limit
  let base_digest = experience_digest(base_exp)
  let rounds : Array[Round] = []
  let mut inc_name = base_name
  let mut inc_exp = base_exp
  let mut inc_digest = base_digest
  let mut accepted = 0
  let mut rejected = 0
  let mut consecutive = 0
  let mut stop = Exhausted
  let mut stopped = false
  for c in cands {
    if !stopped {
      let r = judge_round(rounds.length(), inc_name, inc_exp, inc_digest, c, cfg)
      rounds.push(r)
      if r.accepted {
        inc_name = c.name
        inc_exp = c.exp
        inc_digest = r.cand_digest
        accepted = accepted + 1
        consecutive = 0
      } else {
        rejected = rejected + 1
        consecutive = consecutive + 1
      }
      if rounds.length() >= budget {
        stop = Budget
        stopped = true
      } else if consecutive >= stall_limit {
        stop = Stalled
        stopped = true
      }
    }
  }
  {
    gate: cfg.gate,
    policies_digest: cfg.policies_digest,
    base_name,
    base_digest,
    rounds,
    incumbent: inc_name,
    incumbent_digest: inc_digest,
    accepted,
    rejected,
    stop_reason: stop,
    budget,
    stall_limit,
  }
}

///|
/// 失败记忆（blueprint §5.2 errors.md 的机械形态）：
/// 被拒轮次按**决定项**归类——agent 读它就能知道"这一路已经被试过并否决了"，
/// 不必重复同一种无效改动。返回 (决定项, 次数)，按首次出现顺序。
pub fn rejection_memory(run : RsiRun) -> Array[(String, Int)] {
  let out : Array[(String, Int)] = []
  for r in run.rounds {
    if !r.accepted {
      let key = r.decision.deciding
      let mut found = false
      let mut i = 0
      while i < out.length() && !found {
        let (k, n) = out[i]
        if k == key {
          out[i] = (k, n + 1)
          found = true
        }
        i = i + 1
      }
      if !found {
        out.push((key, 1))
      }
    }
  }
  out
}

///|
/// 台账自检：血统必须连通（base → 每轮 → incumbent），接受/拒绝必须与裁决一致。
/// 空 = 自洽。对"刚算出来的 run"必然为空——它的价值在 `rsi check`：
/// 对**复算出来的 run** 也成立，才说明台账没有说谎。
pub fn rsi_problems(run : RsiRun) -> Array[String] {
  let out : Array[String] = []
  let mut expect_name = run.base_name
  let mut expect_digest = run.base_digest
  let mut i = 0
  for r in run.rounds {
    if r.index != i {
      out.push("第 \{i} 轮序号不连续（记的是 \{r.index}）")
    }
    if r.base_name != expect_name {
      out.push("第 \{i} 轮基线不接血统（记的是 \{r.base_name}，应为 \{expect_name}）")
    }
    if r.base_digest != expect_digest {
      out.push("第 \{i} 轮基线指纹不接血统")
    }
    let v = verdict_name(r.decision.verdict)
    if r.accepted && v != "accept_b" {
      out.push("第 \{i} 轮标为接受，但裁决是 \{v}")
    }
    if !r.accepted && v == "accept_b" {
      out.push("第 \{i} 轮裁决 accept_b 却未接受")
    }
    if r.accepted {
      expect_name = r.cand_name
      expect_digest = r.cand_digest
    }
    i = i + 1
  }
  if run.incumbent != expect_name {
    out.push("血统末端 \{run.incumbent} 与逐轮推导 \{expect_name} 不符")
  }
  if run.incumbent_digest != expect_digest {
    out.push("血统末端指纹与逐轮推导不符")
  }
  if run.accepted + run.rejected != run.rounds.length() {
    out.push("接受 + 拒绝 ≠ 轮数")
  }
  out
}

///|
/// 台账里必须写明的"没证明什么"（与验证报告同一条纪律）
pub fn rsi_unsupported_claims() -> Array[String] {
  [
    "候选由外部（agent）产生——本引擎只做选择与记账，不生成内容、不改关卡",
    "接受只意味着**按冻结门与偏好序**更优，不意味着绝对质量更高",
    "度量只覆盖声明的策略集：未被任何策略走到的玩法路径不在证据内",
    "体验度量不进 binary 主分；台账不替代 verify 的 reward",
  ]
}

///|
fn criteria_json_full(cs : Array[Criterion]) -> String {
  let mut s = "["
  let mut i = 0
  for c in cs {
    if i > 0 {
      s = s + ","
    }
    s = s + "{\"name\":\"" + c.name + "\",\"metric\":\"" + c.metric + "\""
    s = s + ",\"op\":\"" + c.op + "\",\"value\":" + c.value.to_string() + "}"
    i = i + 1
  }
  s + "]"
}

///|
fn prefer_json(order : Array[String]) -> String {
  let mut s = "["
  let mut i = 0
  for k in order {
    if i > 0 {
      s = s + ","
    }
    s = s + "\"" + k + "\""
    i = i + 1
  }
  s + "]"
}

///|
pub fn gate_json(g : Gate) -> String {
  let mut s = "{\"digest\":\"" + g.digest + "\""
  s = s + ",\"criteria\":" + criteria_json_full(g.criteria)
  s = s + ",\"prefer\":" + prefer_json(g.prefer) + "}"
  s
}

///|
fn round_json(r : Round) -> String {
  let mut s = "{\"index\":" + r.index.to_string()
  s = s + ",\"base\":{\"path\":\"" + r.base_name + "\",\"digest\":\"" + r.base_digest + "\"}"
  s = s + ",\"cand\":{\"path\":\"" + r.cand_name + "\",\"digest\":\"" + r.cand_digest + "\"}"
  s = s + ",\"accepted\":" + r.accepted.to_string()
  s = s + ",\"frozen_passed\":" + r.frozen_passed.to_string()
  s = s + ",\"self_passed\":" + r.self_passed.to_string()
  s = s + ",\"criteria_drift\":" + r.criteria_drift.to_string()
  s = s + ",\"gate_shopping\":" + r.gate_shopping.to_string()
  s = s + ",\"policy_drift\":" + r.policy_drift.to_string()
  s = s + ",\"mode_drift\":" + r.mode_drift.to_string()
  s = s + ",\"decision\":" + decision_json(r.decision) + "}"
  s
}

///|
fn rejection_memory_json(run : RsiRun) -> String {
  let mut s = "["
  let mut i = 0
  for item in rejection_memory(run) {
    let (k, n) = item
    if i > 0 {
      s = s + ","
    }
    s = s + "{\"deciding\":\"" + k + "\",\"count\":" + n.to_string() + "}"
    i = i + 1
  }
  s + "]"
}

///|
fn problems_json(ps : Array[String]) -> String {
  let mut s = "["
  let mut i = 0
  for p in ps {
    if i > 0 {
      s = s + ","
    }
    s = s + "\"" + p + "\""
    i = i + 1
  }
  s + "]"
}

///|
/// 台账 JSON（stdout 单文档；`rsi check` 读回同一份）。
pub fn rsi_json(run : RsiRun) -> String {
  let mut s = "{\"gate\":" + gate_json(run.gate)
  s = s + ",\"policies_digest\":\"" + run.policies_digest + "\""
  s = s + ",\"base\":{\"path\":\"" + run.base_name + "\",\"digest\":\"" + run.base_digest + "\"}"
  s = s + ",\"rounds\":["
  let mut i = 0
  for r in run.rounds {
    if i > 0 {
      s = s + ","
    }
    s = s + round_json(r)
    i = i + 1
  }
  s = s + "]"
  s = s + ",\"accepted\":" + run.accepted.to_string()
  s = s + ",\"rejected\":" + run.rejected.to_string()
  s = s + ",\"incumbent\":{\"path\":\"" + run.incumbent + "\",\"digest\":\"" + run.incumbent_digest + "\"}"
  s = s + ",\"stop_reason\":\"" + stop_reason_name(run.stop_reason) + "\""
  // 停止参数必须进台账：否则 `rsi check` 无法重现同一次停止（复算会给出别的轮数）
  s = s + ",\"budget\":" + run.budget.to_string()
  s = s + ",\"stall_limit\":" + run.stall_limit.to_string()
  s = s + ",\"rejection_memory\":" + rejection_memory_json(run)
  s = s + ",\"problems\":" + problems_json(rsi_problems(run))
  s = s + ",\"unsupported_claims\":" + problems_json(rsi_unsupported_claims()) + "}"
  s
}
