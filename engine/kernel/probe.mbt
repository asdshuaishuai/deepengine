// probe —— 行为探针：声明式脚本 + 期望断言 + binary 主分报告（blueprint §3.4–3.7）。
//
// 评分模型：全部必需探针过 = reward 1，否则 0（零 LLM）。
// 诊断分只做 near-miss 定位，不替代主分。报告自带 evidence_basis /
// unsupported_claims / contract_fingerprint 三个自审计字段。

///|
/// 一个探针 = 名字 + 输入脚本 + 期望
pub(all) struct Probe {
  name : String
  script : String // "right:60, jump, right:120"
  expect : String // "state==won" / "coins>=1"
}

///|
/// 单条脚本指令
priv enum Cmd {
  Move(String, Int) // 方向（left/right），持续帧数
  Jump(Int) // 按住帧数
  Wait(Int)
}

///|
fn parse_script(script : String) -> Array[Cmd] {
  let cmds : Array[Cmd] = []
  let toks : Array[StringView] = script.split(",").iter().collect()
  for tok in toks {
    let t = tok.trim().to_owned()
    if t.length() == 0 {
      continue
    }
    let parts : Array[StringView] = t.split(":").iter().collect()
    let head = parts[0].trim().to_owned()
    let n : Int = if parts.length() > 1 {
      match parse_int(parts[1].trim().to_owned()) {
        Some(v) => v
        None => 1
      }
    } else {
      1
    }
    match head {
      "right" => cmds.push(Move("right", n))
      "left" => cmds.push(Move("left", n))
      "jump" => cmds.push(Jump(n))
      "wait" => cmds.push(Wait(n))
      _ => () // 未知指令由解析层 P0 门禁报，这里容错
    }
  }
  cmds
}

///|
/// 脚本 → [(语义输入, 帧数)]——**唯一**脚本解析器。
///
/// 探针执行（run_script）、轨迹采样（trace）、渲染回放（runtime/cli）三条路径
/// 共用这一份展开：脚本语法的第二份实现是漂移的温床（DECLARATION.md 禁重复）。
pub fn script_plan(script : String) -> Array[(Input, Int)] {
  let out : Array[(Input, Int)] = []
  for cmd in parse_script(script) {
    match cmd {
      Move(dir, n) =>
        out.push((
          if dir == "right" {
            { left: false, right: true, jump: false }
          } else {
            { left: true, right: false, jump: false }
          },
          n,
        ))
      Jump(n) => out.push(({ left: false, right: false, jump: true }, n))
      Wait(n) => out.push((Input::none(), n))
    }
  }
  out
}

///|
/// 语义输入的标签（轨迹用）：跳跃优先于方向——跳是这一帧的注意点
pub fn input_label(input : Input) -> String {
  if input.jump {
    "J"
  } else if input.right {
    "R"
  } else if input.left {
    "L"
  } else {
    "-"
  }
}

///|
/// 在副本上执行脚本，返回终局状态
pub fn run_script(g0 : Game, script : String) -> Game {
  let g = Game::clone(g0)
  for cmd in script_plan(script) {
    let (input, n) = cmd
    let mut frames = 0
    while frames < n {
      step(g, input)
      frames = frames + 1
    }
  }
  g
}

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
/// 期望求值："key==val" / "key>=n" / "key<=n" / "key!=val"
fn eval_expect(g : Game, expect : String) -> Bool {
  let ops = ["==", ">=", "<=", "!="]
  for op in ops {
    let pos = expect.find(op)
    match pos {
      Some(i) => {
        let key = expect.substring(start=0, end=i).trim().to_owned()
        let val = expect.substring(start=i + op.length()).trim().to_owned()
        let actual = match runtime_value(g, key) {
          Some(a) => a
          None => return false // 未知 key = 失败（宁可假阴不假阳）
        }
        if op == "==" {
          return actual == val
        }
        if op == "!=" {
          return actual != val
        }
        // 数值比较
        let a = match parse_int(actual) {
          Some(v) => v
          None => return false
        }
        let b = match parse_int(val) {
          Some(v) => v
          None => return false
        }
        if op == ">=" {
          return a >= b
        }
        return a <= b
      }
      None => ()
    }
  }
  false // 无可识别操作符
}

///|
/// 探针结果
pub(all) struct ProbeResult {
  name : String
  pass : Bool
  detail : String
}

///|
/// 验证报告（binary 主分 + 诊断分 + 自审计字段）
pub(all) struct Report {
  reward : Int
  total : Int
  passed : Int
  results : Array[ProbeResult]
  evidence : Array[String]
  unsupported : Array[String]
}

///|
/// 契约指纹：源文本校验和（检测"证据过期"——代码一变指纹变）
fn checksum(text : String) -> String {
  // 多项式滚动哈希（模大素数），仅作变更检测，非密码学
  let mut h1 : Int = 7
  let mut h2 : Int = 31
  for c in text {
    let cp = c.to_int()
    h1 = (h1 * 31 + cp) % 1000003
    h2 = (h2 * 131 + cp) % 999983
  }
  "\{h1}-\{h2}-\{text.length()}"
}

///|
pub fn fingerprint(text : String) -> String {
  checksum(text)
}

///|
/// 执行全部探针：引擎通用（universal）+ 文件声明
pub fn verify(g0 : Game, probes : Array[Probe]) -> Report {
  let results : Array[ProbeResult] = []
  let evidence : Array[String] = []

  // ---- 通用探针（引擎内置，无需声明）----
  // U1 确定性：同脚本双跑，序列化必须一致
  let determinism_script : String = if probes.length() > 0 {
    probes[0].script
  } else {
    "right:60"
  }
  let a1 = serialize(run_script(g0, determinism_script))
  let a2 = serialize(run_script(g0, determinism_script))
  results.push({
    name: "u_determinism",
    pass: a1 == a2,
    detail: "double-run serialize equal=\{a1 == a2}",
  })
  evidence.push("kernel double-run serialize compare")

  // U2 输入响应：按右 30 帧，x 必须前进（"帧在动"不算证据——要状态 diff）
  let g_moved = run_script(g0, "right:30")
  let x0 = match runtime_value(g0, "x") {
    Some(v) => v
    None => "0"
  }
  let x1 = match runtime_value(g_moved, "x") {
    Some(v) => v
    None => "0"
  }
  let moved_ok = match (parse_int(x0), parse_int(x1)) {
    (Some(a), Some(b)) => b > a
    _ => false
  }
  results.push({ name: "u_input_response", pass: moved_ok, detail: "x \{x0}→\{x1}" })
  evidence.push("input_response x diff f0→f30")

  // U3 原地稳定：站立 30 帧，y 漂移 ≤2px 且仍在 playing
  let g_still = run_script(g0, "wait:30")
  let y0 = match runtime_value(g0, "y") {
    Some(v) => v
    None => "0"
  }
  let y1 = match runtime_value(g_still, "y") {
    Some(v) => v
    None => "0"
  }
  let stable_ok = match (parse_int(y0), parse_int(y1)) {
    (Some(a), Some(b)) => {
      let d = if a > b {
        a - b
      } else {
        b - a
      }
      d <= 2 && g_still.state == "playing"
    }
    _ => false
  }
  results.push({
    name: "u_grounded_stability",
    pass: stable_ok,
    detail: "y \{y0}→\{y1} state=\{g_still.state}",
  })
  evidence.push("grounded stability y drift f0→f30")

  // U4 有限性：位置非 NaN（x==x 自反检查）
  let finite_ok = g_moved.player.x == g_moved.player.x && g_moved.player.y == g_moved.player.y
  results.push({ name: "u_finite_state", pass: finite_ok, detail: "no NaN" })
  evidence.push("finite check after scripts")

  // ---- 文件声明探针 ----
  for p in probes {
    let g_end = run_script(g0, p.script)
    let ok = eval_expect(g_end, p.expect)
    let got = match runtime_value(g_end, key_of(p.expect)) {
      Some(v) => v
      None => "?"
    }
    results.push({
      name: p.name,
      pass: ok,
      detail: "expect[\{p.expect}] got[\{key_of(p.expect)}=\{got}] state=\{g_end.state} f\{g_end.frame}",
    })
    evidence.push("script replay serialize=\{serialize(g_end)}")
  }

  let total = results.length()
  let mut passed = 0
  for r in results {
    if r.pass {
      passed = passed + 1
    }
  }
  {
    reward: if passed == total {
      1
    } else {
      0
    },
    total: total,
    passed: passed,
    results: results,
    evidence: evidence,
    unsupported: [
      "未覆盖非脚本路径（自由输入/暂停）",
      "截图未做逐字节回归（仅采样证据）",
      "未证明不同 seed/关卡变体的一致性",
    ],
  }
}

///|
/// 取期望里的 key 部分（"state==won" → "state"）
fn key_of(expect : String) -> String {
  let ops = ["==", ">=", "<=", "!="]
  for op in ops {
    let pos = expect.find(op)
    match pos {
      Some(i) => return expect.substring(start=0, end=i).trim().to_owned()
      None => ()
    }
  }
  expect
}

///|
/// 报告 → JSON 文本（stdout 协议）
pub fn report_json(r : Report, source : String) -> String {
  let mut s = "{\"reward\":\{r.reward}"
  s = s + ",\"passed\":\{r.passed},\"total\":\{r.total}"
  s = s + ",\"contract_fingerprint\":\"\{fingerprint(source)}\""
  s = s + ",\"results\":["
  let mut i = 0
  for res in r.results {
    if i > 0 {
      s = s + ","
    }
    s = s + "{\"name\":\"\{res.name}\",\"pass\":\{res.pass},\"detail\":\"\{res.detail}\"}"
    i = i + 1
  }
  s = s + "]"
  s = s + ",\"evidence_basis\":["
  let mut k = 0
  for e in r.evidence {
    if k > 0 {
      s = s + ","
    }
    s = s + "\"\{e}\""
    k = k + 1
  }
  s = s + "]"
  s = s + ",\"unsupported_claims\":["
  let mut j = 0
  for u in r.unsupported {
    if j > 0 {
      s = s + ","
    }
    s = s + "\"\{u}\""
    j = j + 1
  }
  s = s + "]}"
  s
}
