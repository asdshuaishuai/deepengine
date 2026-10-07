// palette —— FC/SFC 调色板与颜色量化（"资源制作"与"资源识别"的共用底座）
//
// **为什么不用权威 hex 表**：调研已确认 NES PPU 输出 64 个模拟电压，
// 不存在官方 hex 列表；社区流通的 64 色表（Bisqit/Nestopia 系）是渲染近似。
// 所以本包把那份表当作**风格锚点**而非真值，并在文件里注明来源与性质。
//
// 两条能力共用这里的量化器：
//   制作：给定语义色（body/skin/accent）→ 在 FC 调色板里找最合适的 3+1
//   识别：给定一段像素 → 提取主色、量化、报告实际用色数
//
// 关键约束（来自核实过的硬件数字）：
//   FC 精灵 = 3 色 + 透明；FC 背景 metatile = 4 色；SFC 精灵 = 15 色 + 透明。

///|
/// FC 64 色调色板（社区流通的 2C02 NTSC 近似值，4 行 × 16 列）
///
/// 性质：**近似**。PPU 实际输出模拟电压，任何 hex 表都是显示器侧的近似。
/// 作为生成器的风格锚点够用；不要当"真值"引用。
///
/// 用函数而非顶层常量返回：MoonBit 的 `const` 不接受数组字面量，
/// 而每次重建 64 元组数组没有意义（MoonBit 值语义，共享只读数组是安全的）。
pub fn fc_palette() -> Array[(Int, Int, Int)] {
  [
    (88, 88, 88), (0, 35, 124), (13, 16, 153), (48, 0, 146), (79, 0, 108), (96, 0, 53), (92, 5, 0), (70, 24, 0),
    (39, 45, 0), (9, 62, 0), (0, 69, 0), (0, 65, 6), (0, 53, 69), (0, 0, 0), (0, 0, 0), (0, 0, 0),
    (161, 161, 161), (11, 83, 215), (51, 55, 254), (102, 33, 247), (149, 21, 190), (172, 22, 110), (166, 39, 33), (134, 67, 0),
    (89, 98, 0), (45, 122, 0), (12, 133, 0), (0, 127, 42), (0, 109, 133), (0, 0, 0), (0, 0, 0), (0, 0, 0),
    (255, 255, 255), (81, 165, 254), (128, 132, 254), (188, 106, 254), (241, 91, 254), (254, 94, 196), (254, 114, 105), (225, 147, 33),
    (173, 182, 0), (121, 211, 0), (81, 223, 33), (58, 217, 116), (57, 195, 223), (66, 66, 66), (0, 0, 0), (0, 0, 0),
    (181, 217, 254), (202, 202, 254), (227, 190, 254), (249, 184, 254), (254, 186, 231), (254, 195, 188), (244, 209, 153), (222, 224, 134),
    (198, 236, 135), (178, 242, 157), (167, 240, 195), (168, 231, 240), (172, 172, 172), (0, 0, 0), (0, 0, 0), (0, 0, 0),
  ]
}

///|
/// SFC 最小亮度阶梯量化（BGR555 的 5 位亮度级，≈ 8.23/255）
pub fn sfc_quantize_channel(v : Int) -> Int {
  if v <= 0 {
    0
  } else if v >= 255 {
    31
  } else {
    v * 31 / 255
  }
}

///|
/// RGB → BGR555 打包值（15 位：0BBBBBGGGGGRRRRR）
pub fn sfc_pack_bgr555(r : Int, g : Int, b : Int) -> Int {
  (sfc_quantize_channel(b) << 10) | (sfc_quantize_channel(g) << 5) | sfc_quantize_channel(r)
}

///|
/// BGR555 → RGB（回读，供 host 预览）
pub fn sfc_unpack_rgb(v : Int) -> (Int, Int, Int) {
  let r5 = v & 31
  let g5 = (v >> 5) & 31
  let b5 = (v >> 10) & 31
  (r5 * 255 / 31, g5 * 255 / 31, b5 * 255 / 31)
}

///|
fn absd(a : Int, b : Int) -> Int {
  if a > b {
    a - b
  } else {
    b - a
  }
}

///|
/// 感知加权距离（绿 > 红 > 蓝——人眼亮度敏感度差异）。
///
/// 用欧氏距离会在深蓝/深绿上判错：FC 调色板里这类色很多，
/// 但它们在画面上的明度差比 RGB 数值差更明显。
pub fn color_dist2(
  r1 : Int,
  g1 : Int,
  b1 : Int,
  r2 : Int,
  g2 : Int,
  b2 : Int
) -> Int {
  let dr = absd(r1, r2)
  let dg = absd(g1, g2)
  let db = absd(b1, b2)
  dr * dr * 3 + dg * dg * 4 + db * db * 2
}

///|
/// 最近 FC 调色板颜色下标（-1 = 调色板为空）
pub fn nearest_fc_index(r : Int, g : Int, b : Int) -> Int {
  // 局部取一次调色板：nearest 是热点（每像素调一次），
  // 循环内反复调用 fc_palette() 会重建 64 元组数组。
  let pal = fc_palette()
  let mut best = -1
  let mut best_d = 0
  let mut i = 0
  for c in pal {
    let d = color_dist2(r, g, b, c.0, c.1, c.2)
    if best == -1 || d < best_d {
      best = i
      best_d = d
    }
    i = i + 1
  }
  best
}

///|
/// 量化结果：调色板下标 + 实际用色数
pub(all) struct Quantized {
  indices : Array[Int] // 每个输入像素 → FC 调色板下标
  unique : Array[Int] // 用到的不同下标（升序）
  max_allowed : Int // 该用途的有效颜色上限（不含透明）
  errors : Array[String]
}

///|
/// 颜色计数（资源识别的第一手数据）
pub(all) struct ColorCensus {
  distinct : Int // 出现的不同颜色数
  counts : Array[Int] // 每种颜色出现次数（下标对应 colors）
  colors : Array[(Int, Int, Int)] // 出现的颜色（去重，保持首次出现顺序）
}

///|
/// 统计一段展平 RGB 像素序列的颜色分布。
/// 这是"识别"的基础能力：拿到一张图/一帧，先知道它到底用了多少色。
///
/// pixels : [r,g,b, r,g,b, ...] 展平数组
pub fn census(pixels : Array[Int]) -> ColorCensus {
  let colors : Array[(Int, Int, Int)] = []
  let counts : Array[Int] = []
  let mut i = 0
  while i + 2 < pixels.length() {
    let c = (pixels[i], pixels[i + 1], pixels[i + 2])
    let mut found = -1
    let mut k = 0
    for existing in colors {
      if existing == c {
        found = k
        break
      }
      k = k + 1
    }
    if found == -1 {
      colors.push(c)
      counts.push(1)
    } else {
      counts[found] = counts[found] + 1
    }
    i = i + 3
  }
  { distinct: colors.length(), counts: counts, colors: colors }
}

///|
/// 把一段展平 RGB 像素量化到 FC 调色板，并报告是否超出该用途的颜色预算。
///
/// max_allowed : 有效颜色数上限（FC 精灵 3 / FC 背景 3 / SFC 精灵 15 …）
/// 超预算 → 写 errors（不静默——超限意味着资源在真机上会显示错误）。
pub fn quantize_fc(pixels : Array[Int], max_allowed : Int) -> Quantized {
  let indices : Array[Int] = []
  let used : Array[Int] = []
  let mut i = 0
  while i + 2 < pixels.length() {
    let idx = nearest_fc_index(pixels[i], pixels[i + 1], pixels[i + 2])
    indices.push(idx)
    let mut seen = false
    for u in used {
      if u == idx {
        seen = true
        break
      }
    }
    if !seen {
      used.push(idx)
    }
    i = i + 3
  }
  used.sort()
  let errors : Array[String] = []
  if used.length() > max_allowed {
    errors.push(
      "quantize: 用色 \{used.length()} 色超出预算 \{max_allowed}（FC 精灵 3 / FC 背景 3 / SFC 精灵 15）",
    )
  }
  { indices: indices, unique: used, max_allowed: max_allowed, errors: errors }
}

///|
/// 为 FC 精灵挑一组实体色（有效 3 色，index0 透明由调用方占位）
///
/// 策略：给定语义色（body / skin / accent），各取最近 FC 色，
/// 去重后不足 3 个则从调色板里补齐——真机上宁可色少也不许超。
pub fn fc_sprite_palette(
  body : (Int, Int, Int),
  skin : (Int, Int, Int),
  accent : (Int, Int, Int)
) -> Array[(Int, Int, Int)] {
  let out : Array[(Int, Int, Int)] = []
  let wants = [body, skin, accent]
  for w in wants {
    let idx = nearest_fc_index(w.0, w.1, w.2)
    let c = fc_palette()[idx]
    let mut seen = false
    for o in out {
      if o == c {
        seen = true
        break
      }
    }
    if !seen && out.length() < 3 {
      out.push(c)
    }
  }
  // 补齐到 3 色（语义色去重冲突时）——按调色板顺序找未用过的
  let mut probe = 0
  while out.length() < 3 && probe < fc_palette().length() {
    let c = fc_palette()[probe]
    let mut seen = false
    for o in out {
      if o == c {
        seen = true
        break
      }
    }
    if !seen {
      out.push(c)
    }
    probe = probe + 1
  }
  out
}

///|
fn hex_digit(v : Int) -> String {
  let digits = "0123456789ABCDEF"
  if v >= 0 && v < 16 {
    digits.substring(start=v, end=v + 1)
  } else {
    "0"
  }
}

///|
fn rgb_to_hex(c : (Int, Int, Int)) -> String {
  "#" +
  hex_digit(c.0 / 16) + hex_digit(c.0 % 16) +
  hex_digit(c.1 / 16) + hex_digit(c.1 % 16) +
  hex_digit(c.2 / 16) + hex_digit(c.2 % 16)
}

///|
/// 调色板 → 文本工件（agent 可保存/diff/喂给 host 预览）
pub fn palette_to_text(pal : Array[(Int, Int, Int)], name : String) -> String {
  let mut s = "# palette " + name + "（FC 量化后，index0 = 透明）\n"
  let mut i = 0
  for c in pal {
    s = s + ".defpal \"" + name + "\", " + i.to_string() + "\n"
    s = s + "  .color " + rgb_to_hex(c) + "\n"
    i = i + 1
  }
  s + "\n"
}

///|
/// 导出 FC 调色板全文（文本工件：可 diff、可喂外部工具）
pub fn fc_palette_text() -> String {
  let mut s = "# FC 64 色调色板（社区近似值，非权威——PPU 输出的是模拟电压）\n"
  let mut i = 0
  for c in fc_palette() {
    if i % 8 == 0 {
      s = s + "\n"
    }
    s = s + rgb_to_hex(c) + " "
    i = i + 1
  }
  s + "\n"
}