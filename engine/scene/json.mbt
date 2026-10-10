// json —— 最小 JSON 解析器（零依赖）。
//
// 纪律：只实现内容源需要的能力（object/array/string/number/bool/null），
// 不做完整 JSON 规范（不处理转义 \u、指数记法、科学计数尾部）——
// 内容源是我们自己产出的，解析失败要报错不静默（不崩谓词：收集错误）。
//
// 语义：parse 返回 (值?, 错误数组)。重复 key 后者覆盖前者（与主流实现一致）。

///|
pub(all) enum Json {
  Null
  Bool(Bool)
  Num(Double)
  Str(String)
  Arr(Array[Json])
  Obj(Array[(String, Json)]) // 保序：解析回写与诊断需要稳定顺序
}

///|
fn jerr(errors : Array[String], msg : String) -> Json {
  errors.push(msg)
  Json::Null
}

///|
fn skip_ws(s : String, i : Int) -> Int {
  let mut i = i
  while i < s.length() {
    let c = s.substring(start=i, end=i + 1)
    if c == " " || c == "\t" || c == "\n" || c == "\r" {
      i = i + 1
    } else {
      break
    }
  }
  i
}

///|
/// 单个十六进制字符 → 值（大小写皆可）
fn hex_val(c : String) -> Int? {
  match "0123456789abcdef".find(c) {
    Some(v) => Some(v)
    None =>
      match "0123456789ABCDEF".find(c) {
        Some(v) => Some(v)
        None => None
      }
  }
}

///|
/// `\uXXXX` → 一个 UTF-16 码元；`\uD83D\uDE00` 这种代理对由相邻两次转义自然拼成。
///
/// 为什么必须支持：台账/工具产物常由别的程序写出（Python `json.dump` 默认转义非 ASCII），
/// 只收原字符会让"经标准工具转手过的 JSON"读不回来——审计链就此断在解析上。
fn read_u_escape(s : String, i : Int, errors : Array[String]) -> (String, Int) {
  if i + 4 > s.length() {
    errors.push("json: \\u 转义不足 4 位")
    return ("", s.length())
  }
  let hex = s.substring(start=i, end=i + 4)
  let mut v = 0
  let mut k = 0
  let mut ok = true
  while k < 4 {
    match hex_val(hex.substring(start=k, end=k + 1)) {
      Some(d) => v = v * 16 + d
      None => ok = false
    }
    k = k + 1
  }
  if !ok {
    errors.push("json: \\u 转义含非十六进制字符")
    return ("", i + 4)
  }
  (v.unsafe_to_char().to_string(), i + 4)
}

///|
fn parse_string_lit(s : String, i : Int, errors : Array[String]) -> (String, Int) {
  // s[i] == '"'，返回 (内容, 闭合引号后的下标)
  let mut i = i + 1
  let mut out = ""
  while i < s.length() {
    let c = s.substring(start=i, end=i + 1)
    if c == "\\" {
      // 转义：\" \\ \/ \n \r \t \b \f 与 \uXXXX
      if i + 1 >= s.length() {
        errors.push("json: 字符串在转义处截断")
        return (out, s.length())
      }
      let e = s.substring(start=i + 1, end=i + 2)
      i = i + 2
      match e {
        "n" => out = out + "\n"
        "r" => out = out + "\r"
        "t" => out = out + "\t"
        "b" => out = out + "\u{8}"
        "f" => out = out + "\u{c}"
        "u" => {
          let (ch, ni) = read_u_escape(s, i, errors)
          out = out + ch
          i = ni
        }
        _ => out = out + e // \" \\ \/ 及其他
      }
      continue
    }
    if c == "\"" {
      return (out, i + 1)
    }
    out = out + c
    i = i + 1
  }
  errors.push("json: 字符串未闭合")
  (out, s.length())
}

///|
fn parse_value(s : String, i : Int, errors : Array[String]) -> (Json, Int) {
  let i = skip_ws(s, i)
  if i >= s.length() {
    return (jerr(errors, "json: 值缺失（输入截断）"), s.length())
  }
  let c = s.substring(start=i, end=i + 1)
  match c {
    "{" => parse_object(s, i, errors)
    "[" => parse_array(s, i, errors)
    "\"" => {
      let (str, ni) = parse_string_lit(s, i, errors)
      (Json::Str(str), ni)
    }
    "t" => {
      if s.substring(start=i, end=i + 4) == "true" {
        (Json::Bool(true), i + 4)
      } else {
        (jerr(errors, "json: 非法字面量"), s.length())
      }
    }
    "f" => {
      if s.substring(start=i, end=i + 5) == "false" {
        (Json::Bool(false), i + 5)
      } else {
        (jerr(errors, "json: 非法字面量"), s.length())
      }
    }
    "n" => {
      if s.substring(start=i, end=i + 4) == "null" {
        (Json::Null, i + 4)
      } else {
        (jerr(errors, "json: 非法字面量"), s.length())
      }
    }
    _ => {
      // 数字：可选负号 + 数字 + 可选小数（内容源不产生指数）
      let mut j = i
      let neg = if s.substring(start=j, end=j + 1) == "-" {
        j = j + 1
        true
      } else {
        false
      }
      let mut int_part = 0.0
      let mut seen = false
      let mut frac = 0.0
      let mut div = 1.0
      let mut seen_dot = false
      while j < s.length() {
        let ch = s.substring(start=j, end=j + 1)
        if ch == "." && !seen_dot {
          seen_dot = true
          j = j + 1
        } else {
          let d = "0123456789".find(ch)
          match d {
            Some(v) => {
              seen = true
              if seen_dot {
                div = div * 10.0
                frac = frac + v.to_double() / div
              } else {
                int_part = int_part * 10.0 + v.to_double()
              }
              j = j + 1
            }
            None => break
          }
        }
      }
      if !seen {
        return (jerr(errors, "json: 非法数字"), s.length())
      }
      let v = if neg {
        -(int_part + frac)
      } else {
        int_part + frac
      }
      (Json::Num(v), j)
    }
  }
}

///|
/// 重复 key 策略：后者覆盖，保留首次出现的顺序位置（主流 JSON 实现一致）。
fn put(items : Array[(String, Json)], k : String, v : Json) -> Array[(String, Json)] {
  let out : Array[(String, Json)] = []
  let mut replaced = false
  for it in items {
    if it.0 == k {
      if !replaced {
        out.push((k, v))
        replaced = true
      }
    } else {
      out.push(it)
    }
  }
  if !replaced {
    out.push((k, v))
  }
  out
}

///|
fn parse_object(s : String, i : Int, errors : Array[String]) -> (Json, Int) {
  let mut i2 = skip_ws(s, i + 1)
  let mut items : Array[(String, Json)] = []
  if i2 < s.length() && s.substring(start=i2, end=i2 + 1) == "}" {
    return (Json::Obj(items), i2 + 1)
  }
  let mut cont = true
  while cont {
    i2 = skip_ws(s, i2)
    if i2 >= s.length() || s.substring(start=i2, end=i2 + 1) != "\"" {
      return (jerr(errors, "json: 对象键必须是字符串"), s.length())
    }
    let (k, ni) = parse_string_lit(s, i2, errors)
    i2 = skip_ws(s, ni)
    if i2 >= s.length() || s.substring(start=i2, end=i2 + 1) != ":" {
      return (jerr(errors, "json: 键 \{k} 后缺 ':'"), s.length())
    }
    let (v, ni2) = parse_value(s, i2 + 1, errors)
    i2 = ni2
    items = put(items, k, v)
    i2 = skip_ws(s, i2)
    let c = if i2 < s.length() {
      s.substring(start=i2, end=i2 + 1)
    } else {
      ""
    }
    if c == "," {
      i2 = skip_ws(s, i2 + 1)
      if i2 < s.length() && s.substring(start=i2, end=i2 + 1) == "}" {
        cont = false // 尾逗号宽容
      }
      continue
    }
    if c == "}" {
      cont = false
      continue
    }
    return (jerr(errors, "json: 对象缺 ',' 或 '}'"), s.length())
  }
  (Json::Obj(items), i2 + 1)
}

///|
fn parse_array(s : String, i : Int, errors : Array[String]) -> (Json, Int) {
  let mut i2 = skip_ws(s, i + 1)
  let items : Array[Json] = []
  if i2 < s.length() && s.substring(start=i2, end=i2 + 1) == "]" {
    return (Json::Arr(items), i2 + 1)
  }
  let mut cont = true
  while cont {
    let (v, ni) = parse_value(s, i2, errors)
    i2 = ni
    items.push(v)
    i2 = skip_ws(s, i2)
    let c = if i2 < s.length() {
      s.substring(start=i2, end=i2 + 1)
    } else {
      ""
    }
    if c == "," {
      i2 = skip_ws(s, i2 + 1)
      if i2 < s.length() && s.substring(start=i2, end=i2 + 1) == "]" {
        cont = false // 尾逗号宽容
      }
      continue
    }
    if c == "]" {
      cont = false
      continue
    }
    return (jerr(errors, "json: 数组缺 ',' 或 ']'"), s.length())
  }
  (Json::Arr(items), i2 + 1)
}

///|
/// 解析 JSON 文本。成功返回 Some(value)，失败返回 None 且 errors 非空。
pub fn parse_text(text : String) -> (Json?, Array[String]) {
  let errors : Array[String] = []
  let i = skip_ws(text, 0)
  let (v, ni) = parse_value(text, i, errors)
  let tail = skip_ws(text, ni)
  if errors.length() > 0 {
    return (None, errors)
  }
  if tail < text.length() {
    errors.push("json: 尾随垃圾字符 @\{tail}")
    return (None, errors)
  }
  (Some(v), errors)
}

// ---------------- 取值辅助（带路径，供错误信息定位）----------------

///|
pub fn json_get(obj : Json, key : String) -> Json? {
  match obj {
    Json::Obj(items) => {
      for it in items {
        if it.0 == key {
          return Some(it.1)
        }
      }
      None
    }
    _ => None
  }
}

///|
pub fn json_as_num(v : Json) -> Double? {
  match v {
    Json::Num(n) => Some(n)
    _ => None
  }
}

///|
pub fn json_as_str(v : Json) -> String? {
  match v {
    Json::Str(s) => Some(s)
    _ => None
  }
}

///|
pub fn json_as_arr(v : Json) -> Array[Json]? {
  match v {
    Json::Arr(items) => Some(items)
    _ => None
  }
}

///|
pub fn json_as_bool(v : Json) -> Bool? {
  match v {
    Json::Bool(b) => Some(b)
    _ => None
  }
}