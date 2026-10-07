// skin 白盒测试：确定性 / 差异化 / SVG 结构

///|
test "skin：同种子同角色（确定性）" {
  assert_true(skin_svg(42) == skin_svg(42))
  assert_true(skin_summary(42) == skin_summary(42))
}

///|
test "skin：异种子异角色" {
  // 100 个种子里至少 90 个摘要不同（碰撞允许少量）
  let mut distinct = 0
  let mut i = 1
  while i < 100 {
    if skin_summary(i) != skin_summary(i + 1) {
      distinct = distinct + 1
    }
    i = i + 1
  }
  assert_true(distinct > 88)
}

///|
test "skin：seed 0 = 经典蓝" {
  let s = skin_of(0)
  assert_true(s.body_rgb == (74, 158, 255))
  assert_true(s.ear_style == 0)
  assert_true(s.eye_style == 0)
}

///|
test "skin：SVG 结构（部件 id 齐全，可动画）" {
  let svg = skin_svg(7)
  assert_true(svg.contains("<svg"))
  assert_true(svg.contains("</svg>"))
  assert_true(svg.contains("id=\"legL\""))
  assert_true(svg.contains("id=\"legR\""))
  assert_true(svg.contains("id=\"armL\""))
  assert_true(svg.contains("id=\"armR\""))
  assert_true(svg.contains("id=\"body\""))
  assert_true(svg.contains("id=\"head\""))
  assert_true(svg.contains("id=\"char\""))
}

///|
test "skin：HSL→RGB 基准值" {
  // 红：h=0 s=1 l=0.5
  assert_true(hsl_to_rgb(0.0, 1.0, 0.5) == (255, 0, 0))
  // 绿：h=120
  assert_true(hsl_to_rgb(120.0, 1.0, 0.5) == (0, 255, 0))
  // 蓝：h=240
  assert_true(hsl_to_rgb(240.0, 1.0, 0.5) == (0, 0, 255))
}

///|
test "skin：hex 编码" {
  assert_true(hex((255, 0, 16)) == "#ff0010")
  assert_true(hex((0, 0, 0)) == "#000000")
}
