// experience —— 体验评估的**唯一编排**（blueprint §3.9）。
//
// 为什么编排放在 scene 而不是各消费面：native CLI 与 wasm 面都要
// "策略集 → 轨迹 → 体验聚合"。若各写一份，就会出现两套评估路径——
// 与"没有两套世界构建路径"是同一条纪律（DECLARATION.md 禁 workaround 重复）。
//
// 内核只提供原语（run_policy / experience_of / adjudicate），
// 组合方式在这里定一次。

///|
/// 缺省策略集：没声明 policies.json 时用一条种子化探索策略。
///
/// 为什么必须有缺省：`trace` 在任何游戏上都应可用——包括只有
/// `game.mbg.md` 旧入口、根本没有策略声明的游戏。否则这一层只能
/// "测那些已经会测的游戏"，覆盖不了存量内容。
pub fn default_policies() -> Array[@kernel.Policy] {
  let d : Array[@kernel.Policy] = []
  d.push(@kernel.policy_explore("default_explore", 7, 600))
  d
}

///|
/// 声明的策略集（为空则取缺省）
pub fn policies_of(spec : GameSpec) -> Array[@kernel.Policy] {
  if spec.policies.length() > 0 {
    spec.policies
  } else {
    default_policies()
  }
}

///|
/// 在一个游戏规格上跑完整个策略集并聚合体验。
///
/// 每次策略都在 `build()`/`build_grid()` 的**新副本**上跑——
/// 策略之间不共享世界（否则"并集覆盖"会变成"上一条的残留"）。
pub fn run_experience(spec : GameSpec) -> @kernel.Experience {
  run_experience_with(spec, policies_of(spec))
}

///|
/// **用指定的策略集**评估一个游戏规格（自改进面必需）。
///
/// 为什么自改进比较必须冻结策略集：覆盖度是"所有策略走到的格子并集"，
/// 若允许候选自带策略集，那么"多声明 8 条探索策略"就能机械抬高覆盖率——
/// 看起来像"测得更全"，其实游戏一个像素都没改。那是比改判据更隐蔽的作弊，
/// 因为它的外观恰好是"更严谨的测试"。
///
/// 冻结策略集 = **同一套探针测两版**；候选自己声明的策略集只会被拿来比对
/// （policy_drift），不参与判定。
pub fn run_experience_with(
  spec : GameSpec,
  policies : Array[@kernel.Policy]
) -> @kernel.Experience {
  let wi = spec.world_info()
  let traces : Array[(String, @kernel.Trace)] = []
  for p in policies {
    let t = if spec.mode == "grid" {
      @kernel.run_policy_grid(spec.build_grid(), p, wi.targets, wi.arena_cells)
    } else {
      @kernel.run_policy(spec.build(), p, wi.targets, wi.arena_cells)
    }
    traces.push((@kernel.policy_name(p), t))
  }
  @kernel.experience_of(traces)
}

///|
/// 候选**自己声明**的策略集指纹（未声明 → ""）。
///
/// 与冻结集不同不等于作弊，但必须如实报告：它意味着这个版本独立跑 `trace`
/// 时给出的数字会和台账不一致——不报，agent 会以为引擎在骗它。
pub fn declared_policy_key(spec : GameSpec) -> String {
  if spec.policies.length() == 0 {
    ""
  } else {
    policy_set_key(spec.policies)
  }
}

///|
/// 策略集的 JSON（证据可复现：报告里必须带上"用什么策略测的"）
pub fn policies_json(policies : Array[@kernel.Policy]) -> String {
  let mut s = "["
  let mut i = 0
  for p in policies {
    if i > 0 {
      s = s + ","
    }
    s = s + "{\"name\":\"" + @kernel.policy_name(p) + "\",\"spec\":\"" + @kernel.policy_spec(p) + "\"}"
    i = i + 1
  }
  s + "]"
}

///|
/// 策略集指纹（比较两版是否用了同一套策略——不同套的比较没有意义）
pub fn policy_set_key(policies : Array[@kernel.Policy]) -> String {
  let mut s = ""
  for p in policies {
    s = s + @kernel.policy_spec(p) + ";"
  }
  s
}
