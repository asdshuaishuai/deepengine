// 递归自改进（RSI）白盒测试：冻结门 / 操弄判据 / 策略集漂移 / 预算与停滞 / 血统 / 复算。
//
// 纪律：这里的断言必须能**证伪**——尤其 gate_shopping 与血统自检，
// 它们存在的意义就是让"每轮都进步"这种幻觉变红。

// ---------------- 构造：直接给体验（决策逻辑测试不依赖物理模拟） ----------------

///|
fn mk_metrics(outcome : String, progress : Int, coverage : Int) -> Metrics {
  {
    frames: 100,
    outcome,
    outcome_rank: outcome_rank(outcome),
    progress_pct: progress,
    coverage_pct: coverage,
    directness_pct: 50,
    stall_max: 10,
    stall_ratio_pct: 5,
    idle_ratio_pct: 5,
    diversity: 3,
    action_switches: 5,
    path_len: 1000,
    revisit_pct: 80,
    jumps: 2,
    truncated: false,
  }
}

///|
fn mk_exp(m : Metrics, union : Int) -> Experience {
  {
    mode: "physics",
    n_policies: 1,
    stuck_policies: 0,
    stuck_ratio_pct: 0,
    truncated_policies: 0,
    cells_union: union,
    arena_cells: 135,
    targets: 1,
    metrics: m,
    per_policy: [],
    outcomes: [m.outcome],
  }
}

///|
fn solvable() -> Array[Criterion] {
  [{ name: "solvable", metric: "progress", op: ">=", value: 100 }]
}

///|
fn cfg_of(cs : Array[Criterion], prefer : Array[String]) -> RsiConfig {
  { gate: gate_of(cs, prefer), policies_digest: "p1", budget: 5, stall_limit: 2 }
}

///|
fn cand(name : String, e : Experience, cs : Array[Criterion], pk : String) -> Candidate {
  { name, exp: e, criteria: cs, policy_key: pk }
}

// ---------------- 指纹：冻结面必须真的"冻住" ----------------

///|
test "rsi：门的指纹对判据与偏好序都敏感" {
  let a = gate_of(solvable(), ["progress", "coverage"])
  let b = gate_of(solvable(), ["coverage", "progress"])
  assert_true(a.digest != b.digest) // 偏好序换了 = 换了尺子
  let c = gate_of([{ name: "solvable", metric: "progress", op: ">=", value: 0 }], [
    "progress", "coverage",
  ])
  assert_true(a.digest != c.digest) // 阈值换了 = 换了尺子
  let d = gate_of(solvable(), ["progress", "coverage"])
  assert_true(a.digest == d.digest) // 同输入必同指纹
}

///|
test "rsi：体验指纹随任一聚合度量变化，同体验必同指纹" {
  let e1 = mk_exp(mk_metrics("won", 100, 30), 30)
  let e2 = mk_exp(mk_metrics("won", 100, 31), 31)
  let e3 = mk_exp(mk_metrics("won", 100, 30), 30)
  assert_true(experience_digest(e1) == experience_digest(e3))
  assert_true(experience_digest(e1) != experience_digest(e2))
}

// ---------------- 冻结门：候选改不了评判自己的尺子 ----------------

///|
test "rsi：真改进（覆盖涨、标准与终局不变）被接受，血统前移" {
  let base = mk_exp(mk_metrics("won", 100, 30), 30)
  let better = mk_exp(mk_metrics("won", 100, 40), 40)
  let run = run_rsi("base", base, cfg_of(solvable(), ["progress", "coverage"]), [
    cand("c1", better, [], "p1"),
  ])
  assert_true(run.accepted == 1)
  assert_true(run.rounds[0].accepted)
  assert_true(run.incumbent == "c1")
  assert_true(run.incumbent_digest == experience_digest(better))
  assert_true(stop_reason_name(run.stop_reason) == "exhausted")
  assert_true(rsi_problems(run).length() == 0)
}

///|
test "rsi：退化被拒，血统不动" {
  let base = mk_exp(mk_metrics("won", 100, 30), 30)
  let worse = mk_exp(mk_metrics("dead", 0, 10), 10)
  let run = run_rsi("base", base, cfg_of(solvable(), ["progress"]), [cand("c1", worse, [], "p1")])
  assert_true(run.accepted == 0)
  assert_true(run.rejected == 1)
  assert_true(run.incumbent == "base")
  assert_true(run.incumbent_digest == experience_digest(base))
}

///|
test "rsi：候选自带更松的尺子——仍按冻结门判，并标出操弄" {
  let base = mk_exp(mk_metrics("won", 100, 30), 30)
  let worse = mk_exp(mk_metrics("dead", 0, 10), 10)
  let loose : Array[Criterion] = [
    { name: "solvable", metric: "progress", op: ">=", value: 0 },
  ]
  let run = run_rsi("base", base, cfg_of(solvable(), ["progress"]), [
    cand("sneaky", worse, loose, "p1"),
  ])
  // 关键：判定依据是冻结门 → 与不带尺子时一样被拒
  assert_true(run.rounds[0].accepted == false)
  assert_true(verdict_name(run.rounds[0].decision.verdict) == "keep_a")
  assert_true(run.rounds[0].frozen_passed == 0)
  assert_true(run.rounds[0].self_passed == 1)
  assert_true(run.rounds[0].gate_shopping)
  assert_true(run.rounds[0].criteria_drift)
}

///|
test "rsi：更优但换了尺子——接受，但仍如实标记操弄" {
  let base = mk_exp(mk_metrics("won", 100, 30), 30)
  let better = mk_exp(mk_metrics("won", 100, 40), 40)
  let loose : Array[Criterion] = [
    { name: "solvable", metric: "progress", op: ">=", value: 0 },
  ]
  // 冻结门本身放行（progress 100 >= 100），它自己的门也放行 → self 1 vs frozen 1 不算操弄信号，
  // 但判据文本确实变了 → criteria_drift 必须为真
  let run = run_rsi("base", base, cfg_of(solvable(), ["progress", "coverage"]), [
    cand("c1", better, loose, "p1"),
  ])
  assert_true(run.rounds[0].accepted)
  assert_true(run.rounds[0].criteria_drift)
}

///|
test "rsi：候选自带另一套策略集 → 标记 policy_drift（独立跑 trace 会对不上账）" {
  let base = mk_exp(mk_metrics("won", 100, 30), 30)
  let same = mk_exp(mk_metrics("won", 100, 30), 30)
  let run = run_rsi("base", base, cfg_of([], ["progress"]), [cand("c1", same, [], "OTHER")])
  assert_true(run.rounds[0].policy_drift)
  assert_true(verdict_name(run.rounds[0].decision.verdict) == "inconclusive")
}

// ---------------- 预算与停滞：不把预算烧在同一个死角 ----------------

///|
test "rsi：触及轮预算即停（§5.3）" {
  let base = mk_exp(mk_metrics("won", 100, 30), 30)
  let c = cand("c", mk_exp(mk_metrics("dead", 0, 5), 5), [], "p1")
  let cfg = cfg_of(solvable(), ["progress"])
  let run = run_rsi("base", base, { ..cfg, budget: 2 }, [c, c, c, c, c])
  assert_true(run.rounds.length() == 2)
  assert_true(stop_reason_name(run.stop_reason) == "budget")
}

///|
test "rsi：连续被拒达上限即停（不死磕）" {
  let base = mk_exp(mk_metrics("won", 100, 30), 30)
  let c = cand("c", mk_exp(mk_metrics("dead", 0, 5), 5), [], "p1")
  let run = run_rsi("base", base, cfg_of(solvable(), ["progress"]), [c, c, c, c, c])
  assert_true(run.rounds.length() == 2) // stall_limit 默认 2
  assert_true(stop_reason_name(run.stop_reason) == "stalled")
  assert_true(run.rejected == 2)
}

///|
test "rsi：中间一次接受会清零连续拒绝计数" {
  let base = mk_exp(mk_metrics("won", 100, 30), 30)
  let bad = cand("bad", mk_exp(mk_metrics("dead", 0, 5), 5), [], "p1")
  let good = cand("good", mk_exp(mk_metrics("won", 100, 40), 40), [], "p1")
  let cfg = cfg_of(solvable(), ["progress", "coverage"])
  let run = run_rsi("base", base, { ..cfg, budget: 4 }, [bad, good, bad])
  assert_true(run.accepted == 1)
  assert_true(stop_reason_name(run.stop_reason) == "exhausted") // 拒绝没有连续两次
  assert_true(run.incumbent == "good")
}

///|
test "rsi：空候选集不崩（不崩谓词），直接 exhausted" {
  let base = mk_exp(mk_metrics("won", 100, 30), 30)
  let run = run_rsi("base", base, cfg_of(solvable(), ["progress"]), [])
  assert_true(run.rounds.length() == 0)
  assert_true(stop_reason_name(run.stop_reason) == "exhausted")
  assert_true(run.incumbent == "base")
  assert_true(run.accepted + run.rejected == 0)
}

// ---------------- 失败记忆与血统自检 ----------------

///|
test "rsi：失败记忆按决定项归类（agent 读它避免重复同一种无效改动）" {
  let base = mk_exp(mk_metrics("won", 100, 30), 30)
  let bad = cand("bad", mk_exp(mk_metrics("dead", 0, 5), 5), [], "p1")
  let run = run_rsi("base", base, cfg_of(solvable(), ["progress"]), [bad, bad])
  let mem = rejection_memory(run)
  assert_true(mem.length() == 1)
  let (key, n) = mem[0]
  assert_true(key == "criteria")
  assert_true(n == 2)
}

///|
test "rsi：接受后再比较用的是新 incumbent（血统逐轮相连）" {
  let base = mk_exp(mk_metrics("won", 100, 30), 30)
  let b1 = mk_exp(mk_metrics("won", 100, 40), 40)
  let b2 = mk_exp(mk_metrics("won", 100, 50), 50)
  let run = run_rsi("base", base, cfg_of(solvable(), ["progress", "coverage"]), [
    cand("c1", b1, [], "p1"),
    cand("c2", b2, [], "p1"),
  ])
  assert_true(run.accepted == 2)
  assert_true(run.rounds[0].base_digest == run.base_digest)
  assert_true(run.rounds[1].base_digest == run.rounds[0].cand_digest)
  assert_true(run.incumbent == "c2")
  assert_true(rsi_problems(run).length() == 0)
}

///|
test "rsi：血统自检能抓出断裂的台账（不是永远空）" {
  let ea = mk_exp(mk_metrics("won", 100, 30), 30)
  let eb = mk_exp(mk_metrics("won", 100, 40), 40)
  let d = adjudicate(ea, eb, [], ["progress", "coverage"])
  let bogus : Round = {
    index: 3, // 序号也不连续
    base_name: "someone-else", // 不接血统
    cand_name: "b",
    base_digest: "X",
    cand_digest: experience_digest(eb),
    decision: d,
    accepted: true,
    frozen_passed: 0,
    self_passed: 0,
    criteria_drift: false,
    gate_shopping: false,
    policy_drift: false,
    mode_drift: false,
  }
  let bad : RsiRun = {
    gate: gate_of(solvable(), ["progress"]),
    policies_digest: "p1",
    base_name: "a",
    base_digest: "Y",
    rounds: [bogus],
    incumbent: "b",
    incumbent_digest: experience_digest(eb),
    accepted: 1,
    rejected: 0,
    stop_reason: Exhausted,
    budget: 5,
    stall_limit: 2,
  }
  assert_true(rsi_problems(bad).length() > 0)
}

///|
test "rsi：血统自检能抓出『逐轮相连但末端不对』的台账" {
  // 这个用例刻意只让 incumbent 校验负责：逐轮记录全部自洽，唯一被改的是"末端是谁"。
  // 若把 rsi_problems 里的 incumbent 校验删掉，本用例必须变红（否则那条校验就是摆设）。
  let base = mk_exp(mk_metrics("won", 100, 30), 30)
  let b1 = mk_exp(mk_metrics("won", 100, 40), 40)
  let good = run_rsi("base", base, cfg_of(solvable(), ["progress", "coverage"]), [
    cand("c1", b1, [], "p1"),
  ])
  assert_true(rsi_problems(good).length() == 0)
  let tampered : RsiRun = { ..good, incumbent: "别处" }
  assert_true(rsi_problems(tampered).length() > 0)
}

///|
test "rsi：共享裁决单元 judge_versions 直接标出操弄（compare 与 rsi 都走它）" {
  // 这是两个面共用的那一个单元：它错了，`compare` 与 `rsi` 就一起错。
  let base = mk_exp(mk_metrics("won", 100, 30), 30)
  let worse = mk_exp(mk_metrics("dead", 0, 10), 10)
  let loose : Array[Criterion] = [
    { name: "solvable", metric: "progress", op: ">=", value: 0 },
  ]
  let j = judge_versions(base, "p1", cand("sneaky", worse, loose, "p1"), gate_of(solvable(), [
    "progress",
  ]))
  assert_true(verdict_name(j.decision.verdict) == "keep_a") // 判定用冻结门，不用它自己的
  assert_true(j.frozen_passed == 0)
  assert_true(j.self_passed == 1)
  assert_true(j.gate_shopping)
  assert_true(j.criteria_drift)
  assert_true(!j.policy_drift)
  assert_true(!j.mode_drift)
}

///|
test "rsi：原型族不同 → 不予裁决（度量同名不同义）" {
  // physics 的 progress 是"金币/终点"，grid 的是"箱子归位"——同名不同义。
  // 给出 accept/keep 都是可比性谎言；且阻断后血统自检仍须自洽（不能出现"accept_b 却未接受"）。
  let base = mk_exp(mk_metrics("won", 100, 30), 30)
  let same = mk_exp(mk_metrics("won", 100, 30), 30)
  let grid : Experience = { ..same, mode: "grid" }
  let run = run_rsi("base", base, cfg_of(solvable(), ["progress", "coverage"]), [
    cand("g", grid, [], "p1"),
  ])
  assert_true(run.rounds[0].mode_drift)
  assert_true(verdict_name(run.rounds[0].decision.verdict) == "inconclusive")
  assert_true(run.rounds[0].decision.deciding == "mode")
  assert_true(run.accepted == 0)
  assert_true(rsi_problems(run).length() == 0)
}

///|
test "rsi：同输入两次 run → 台账逐字节相同（零墙钟、零随机）" {
  let base = mk_exp(mk_metrics("won", 100, 30), 30)
  let c1 = cand("c1", mk_exp(mk_metrics("won", 100, 40), 40), [], "p1")
  let c2 = cand("c2", mk_exp(mk_metrics("dead", 0, 5), 5), [], "p1")
  let cfg = cfg_of(solvable(), ["progress", "coverage"])
  let a = rsi_json(run_rsi("base", base, cfg, [c1, c2]))
  let b = rsi_json(run_rsi("base", base, cfg, [c1, c2]))
  assert_true(a == b)
}

///|
test "rsi：台账自陈没证明什么（自审计字段不是空话）" {
  let claims = rsi_unsupported_claims()
  assert_true(claims.length() > 0)
  let mut mentions_content = false
  for c in claims {
    if c.contains("不生成内容") {
      mentions_content = true
    }
  }
  assert_true(mentions_content)
}
