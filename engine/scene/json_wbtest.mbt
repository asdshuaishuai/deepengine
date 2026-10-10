// json 白盒测试：零依赖 JSON 解析器
//
// 重点覆盖：标量、嵌套、转义、重复 key 策略、错误定位。
// 解析器是内容源的地基——它错了，level.json 全错，且错误会以
// "关卡数据莫名为空" 的形式伪装成别的问题。

///|
fn jparse(s : String) -> Json {
  let (v, errs) = parse_text(s)
  if errs.length() > 0 {
    panic()
  }
  match v {
    Some(x) => x
    None => panic()
  }
}

///|
fn jfail(s : String) -> Array[String] {
  let (v, errs) = parse_text(s)
  match v {
    Some(_) => []
    None => errs
  }
}

///|
test "json：标量（数字/字符串/布尔/null）" {
  match jparse("42") {
    Json::Num(n) => assert_true(n == 42.0)
    _ => abort("expected Num")
  }
  match jparse("-3.5") {
    Json::Num(n) => assert_true(n == -3.5)
    _ => abort("expected Num")
  }
  match jparse("\"hi\"") {
    Json::Str(s) => assert_true(s == "hi")
    _ => abort("expected Str")
  }
  match jparse("true") {
    Json::Bool(b) => assert_true(b)
    _ => abort("expected Bool")
  }
  match jparse("null") {
    Json::Null => ()
    _ => abort("expected Null")
  }
}

///|
test "json：对象与数组" {
  let v = jparse("{\"a\":1,\"b\":[1,2,3]}")
  match json_get(v, "a") {
    Some(x) => match json_as_num(x) {
      Some(n) => assert_true(n == 1.0)
      None => abort("a not num")
    }
    None => abort("no a")
  }
  match json_get(v, "b") {
    Some(x) =>
      match json_as_arr(x) {
        Some(items) => {
          assert_true(items.length() == 3)
          match json_as_num(items[2]) {
            Some(n) => assert_true(n == 3.0)
            None => abort("b[2] not num")
          }
        }
        None => abort("b not arr")
      }
    None => abort("no b")
  }
}

///|
test "json：空容器" {
  match jparse("{}") {
    Json::Obj(items) => assert_true(items.length() == 0)
    _ => abort("expected Obj")
  }
  match jparse("[]") {
    Json::Arr(items) => assert_true(items.length() == 0)
    _ => abort("expected Arr")
  }
}

///|
test "json：转义（换行 制表 反斜杠 引号）" {
  match jparse("\"a\\nb\"") {
    Json::Str(s) => assert_true(s == "a\nb")
    _ => abort("expected Str")
  }
  match jparse("\"a\\tb\"") {
    Json::Str(s) => assert_true(s == "a\tb")
    _ => abort("expected Str")
  }
  match jparse("\"a\\\\b\"") {
    Json::Str(s) => assert_true(s == "a\\b")
    _ => abort("expected Str")
  }
  match jparse("\"say \\\"hi\\\"\"") {
    Json::Str(s) => assert_true(s == "say \"hi\"")
    _ => abort("expected Str")
  }
}

///|
test "json：重复 key 后者覆盖、保留首次位置" {
  match jparse("{\"a\":1,\"b\":2,\"a\":9}") {
    Json::Obj(items) => {
      assert_true(items.length() == 2) // a 只出现一次
      assert_true(items[0].0 == "a") // 位置保持首次
      match json_as_num(items[0].1) {
        Some(n) => assert_true(n == 9.0) // 值取后者
        None => abort("a not num")
      }
    }
    _ => abort("expected Obj")
  }
}

///|
test "json：尾逗号宽容" {
  match jparse("{\"a\":1,}") {
    Json::Obj(items) => assert_true(items.length() == 1)
    _ => abort("expected Obj")
  }
  match jparse("[1,2,]") {
    Json::Arr(items) => assert_true(items.length() == 2)
    _ => abort("expected Arr")
  }
}

///|
test "json：嵌套深度" {
  let v = jparse("{\"level\":{\"cols\":12,\"rows_map\":[\"ab\",\"cd\"]}}")
  match json_get(v, "level") {
    Some(lv) => {
      match json_get(lv, "cols") {
        Some(c) =>
          match json_as_num(c) {
            Some(n) => assert_true(n == 12.0)
            None => abort("cols not num")
          }
        None => abort("no cols")
      }
      match json_get(lv, "rows_map") {
        Some(rm) =>
          match json_as_arr(rm) {
            Some(items) => {
              assert_true(items.length() == 2)
              match json_as_str(items[1]) {
                Some(s) => assert_true(s == "cd")
                None => abort("rows_map[1] not str")
              }
            }
            None => abort("rows_map not arr")
          }
        None => abort("no rows_map")
      }
    }
    None => abort("no level")
  }
}

///|
test "json：空白容忍（换行/多空格）" {
  let v = jparse("  {\n  \"a\"  :  1 ,\n  \"b\":2\n}  ")
  match json_get(v, "a") {
    Some(_) => ()
    None => abort("no a")
  }
  match json_get(v, "b") {
    Some(_) => ()
    None => abort("no b")
  }
}

// ---------------- 失败路径（不崩谓词：收集错误，不抛） ----------------

///|
test "json：未闭合对象报错" {
  assert_true(jfail("{\"a\":1").length() > 0)
}

///|
test "json：键缺冒号报错" {
  assert_true(jfail("{\"a\" 1}").length() > 0)
}

///|
test "json：数组缺右括号报错" {
  assert_true(jfail("[1,2").length() > 0)
}

///|
test "json：字符串未闭合报错" {
  assert_true(jfail("\"abc").length() > 0)
}

///|
test "json：尾随垃圾报错" {
  assert_true(jfail("{\"a\":1} junk").length() > 0)
}

///|
test "json：空输入报错" {
  assert_true(jfail("").length() > 0)
}

///|
test "json：非法数字报错" {
  assert_true(jfail("{\"a\":tru}").length() > 0)
}

///|
test "json：\\u 基本转义（ASCII）" {
  // 台账/工具产物常转义非 ASCII（Python json.dump 默认行为）——读不回来审计就断了
  let v = jparse("\"\\u0041\\u0042\"")
  assert_true(json_as_str(v) == Some("AB"))
}

///|
test "json：\\u 中文转义解出原字符" {
  let v = jparse("\"\\u4e2d\\u6587\"")
  assert_true(json_as_str(v) == Some("中文"))
}

///|
test "json：\\u 代理对拼成一个码点（emoji）" {
  let v = jparse("\"\\ud83d\\ude00\"")
  match json_as_str(v) {
    Some(s) => {
      // 一个 emoji = 两个 UTF-16 码元（String 以码元计长）
      assert_true(s.length() == 2)
      assert_true(s != "\\ud83d\\ude00")
    }
    None => assert_true(false)
  }
}

///|
test "json：\\u 位数不足或非十六进制报错（不静默丢弃）" {
  assert_true(jfail("\"\\u00\"").length() > 0)
  assert_true(jfail("\"\\uZZZZ\"").length() > 0)
}

///|
test "json：大小写十六进制都接受" {
  let v = jparse("\"\\u00e9\\u00E9\"")
  assert_true(json_as_str(v) == Some("éé"))
}