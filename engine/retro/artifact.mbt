// artifact —— retro 资源的文本工件导出（SVG / PPM / CHR hexdump）
//
// 为什么是"文本工件"而不是二进制：blueprint §6.0「资产即参数，参数即文本」，
// agent 要能 diff、review、粘贴给外部工具。SVG 能直接在浏览器/编辑器里看，
// PPM 能喂任何像素工具，CHR hexdump 能贴进 ROM 制作流程。
//
// 放大绘制（nearest neighbor，scale: int）：这是"看得清"与"像素工整"的保证——
// FC 美术本来就是低分辨率，放大显示不该引入插值模糊。

///|
/// RGB → #RRGGBB
///
/// 注意 `#` 前缀只加一次：早先的实现让每个通道各自加 `#`，
/// 拼出 `#A6#27#21` 这种非法颜色——SVG 在浏览器里会静默渲染失败。
/// 所以这里拆成 nibble 转换 + 一次性前缀两步。
fn hexc(c : (Int, Int, Int)) -> String {
  let digits = "0123456789ABCDEF"
  let nib = fn(v : Int) -> String {
    let n = if v < 0 {
      0
    } else if v > 255 {
      255
    } else {
      v
    }
    digits.substring(start=n / 16, end=n / 16 + 1) + digits.substring(start=n % 16, end=n % 16 + 1)
  }
  "#" + nib(c.0) + nib(c.1) + nib(c.2)
}

///|
/// 帧 → SVG（按调色板下标上色；index0 = 透明，画成棋盘格）
///
/// scale : 放大倍数（FC 精灵 8x16 建议 scale 8~16 才看得清）
pub fn frame_svg(f : Frame, pal : Array[(Int, Int, Int)], scale : Int) -> String {
  let s = if scale < 1 { 1 } else { scale }
  let w = f.w * s
  let h = f.h * s
  let mut out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
  out = out + "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" + w.to_string() + "\" height=\"" + h.to_string() + "\" viewBox=\"0 0 " + w.to_string() + " " + h.to_string() + "\" shape-rendering=\"crispEdges\">\n"
  // 透明棋盘底（看清轮廓用）
  out = out + "<defs><pattern id=\"ck\" width=\"" + (s * 2).to_string() + "\" height=\"" + (s * 2).to_string() + "\" patternUnits=\"userSpaceOnUse\">"
  out = out + "<rect width=\"" + (s * 2).to_string() + "\" height=\"" + (s * 2).to_string() + "\" fill=\"#202028\"/>"
  out = out + "<rect width=\"" + s.to_string() + "\" height=\"" + s.to_string() + "\" fill=\"#2a2a35\"/>"
  out = out + "<rect x=\"" + s.to_string() + "\" y=\"" + s.to_string() + "\" width=\"" + s.to_string() + "\" height=\"" + s.to_string() + "\" fill=\"#202028\"/>"
  out = out + "</pattern></defs>\n"
  out = out + "<rect width=\"100%\" height=\"100%\" fill=\"url(#ck)\"/>\n"
  // 像素
  let mut y = 0
  while y < f.h {
    let mut x = 0
    while x < f.w {
      let p = f.pix[y * f.w + x]
      if p != 0 {
        let idx = p - 1
        let fill = if idx < pal.length() { hexc(pal[idx]) } else { "#FF00FF" }
        out = out + "<rect x=\"" + (x * s).to_string() + "\" y=\"" + (y * s).to_string() + "\" width=\"" + s.to_string() + "\" height=\"" + s.to_string() + "\" fill=\"" + fill + "\"/>\n"
      }
      x = x + 1
    }
    y = y + 1
  }
  out = out + "</svg>\n"
  out
}

///|
/// clip → 一张 SVG（所有姿态横排 + 调色板色条）
///
/// 横排而不是竖排：FC 精灵动画是横排读帧的，这个布局本身就在提醒
/// "这是一条动画序列"。
pub fn clip_svg(c : Clip, scale : Int) -> String {
  let s = if scale < 1 { 1 } else { scale }
  let n = c.frames.length()
  let fw = if n > 0 { c.frames[0].w } else { 8 }
  let fh = if n > 0 { c.frames[0].h } else { 16 }
  let gap = s
  let strip_h = fh * s
  let pal_h = 24
  let total_w = if n > 0 { n * (fw * s + gap) + gap } else { gap * 2 }
  let total_h = gap + strip_h + gap + pal_h + gap
  let mut out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
  out = out + "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"" + total_w.to_string() + "\" height=\"" + total_h.to_string() + "\" shape-rendering=\"crispEdges\">\n"
  out = out + "<rect width=\"100%\" height=\"100%\" fill=\"#14141c\"/>\n"
  // 各帧
  let mut i = 0
  while i < n {
    let f = c.frames[i]
    let ox = gap + i * (fw * s + gap)
    let oy = gap
    let mut y = 0
    while y < f.h {
      let mut x = 0
      while x < f.w {
        let p = f.pix[y * f.w + x]
        if p != 0 {
          let idx = p - 1
          let fill = if idx < c.palette.length() { hexc(c.palette[idx]) } else { "#FF00FF" }
          out = out + "<rect x=\"" + (ox + x * s).to_string() + "\" y=\"" + (oy + y * s).to_string() + "\" width=\"" + s.to_string() + "\" height=\"" + s.to_string() + "\" fill=\"" + fill + "\"/>\n"
        }
        x = x + 1
      }
      y = y + 1
    }
    // 帧号
    out = out + "<text x=\"" + (ox + 2).to_string() + "\" y=\"" + (gap + strip_h + 12).to_string() + "\" fill=\"#6a6a86\" font-family=\"monospace\" font-size=\"10\">#" + i.to_string() + "</text>\n"
    i = i + 1
  }
  // 调色板色条
  let sw = if c.palette.length() > 0 { total_w / (c.palette.length() + 1) } else { 0 }
  if sw > 0 {
    out = out + "<text x=\"" + gap.to_string() + "\" y=\"" + (gap + strip_h + 24).to_string() + "\" fill=\"#8a8aa8\" font-family=\"monospace\" font-size=\"11\">idx0 = transparent</text>\n"
    let mut k = 0
    while k < c.palette.length() {
      out = out + "<rect x=\"" + (gap + (k + 1) * sw).to_string() + "\" y=\"" + (gap + strip_h + 16).to_string() + "\" width=\"" + sw.to_string() + "\" height=\"16\" fill=\"" + hexc(c.palette[k]) + "\"/>\n"
      out = out + "<text x=\"" + (gap + (k + 1) * sw + 3).to_string() + "\" y=\"" + (gap + strip_h + 28).to_string() + "\" fill=\"#6a6a86\" font-family=\"monospace\" font-size=\"10\">" + (k + 1).to_string() + "</text>\n"
      k = k + 1
    }
  }
  out = out + "</svg>\n"
  out
}

///|
/// 帧 → PPM（P6 原始像素，喂任何像素工具）
pub fn frame_ppm(f : Frame, pal : Array[(Int, Int, Int)]) -> String {
  let mut out = "P6\n" + f.w.to_string() + " " + f.h.to_string() + "\n255\n"
  let mut i = 0
  while i < f.pix.length() {
    let p = f.pix[i]
    if p == 0 {
      // 透明在 PPM 里没有表示，用洋红作标记（P6 是二进制，这里输出可读 ASCII hex）
      out = out + "FF00FF"
    } else {
      let idx = p - 1
      if idx < pal.length() {
        let c = pal[idx]
        let r = if c.0 < 16 { "0" + hexdig(c.0) } else { hexdig(c.0) }
        let g = if c.1 < 16 { "0" + hexdig(c.1) } else { hexdig(c.1) }
        let b = if c.2 < 16 { "0" + hexdig(c.2) } else { hexdig(c.2) }
        out = out + r + g + b
      } else {
        out = out + "FF00FF"
      }
    }
    i = i + 1
  }
  out + "\n"
}

///|
fn hexdig(v : Int) -> String {
  let digits = "0123456789ABCDEF"
  let n = if v < 0 {
    0
  } else if v > 15 {
    15
  } else {
    v
  }
  digits.substring(start=n, end=n + 1)
}

///|
/// CHR 字节 → hexdump 文本（贴进 ROM 制作流程 / 人工核对）
pub fn chr_hexdump(bytes : Array[Int], per_line : Int) -> String {
  let n = if per_line < 1 { 16 } else { per_line }
  let mut out = ""
  let mut i = 0
  while i < bytes.length() {
    out = out + hex2(bytes[i]) + " "
    if (i + 1) % n == 0 {
      out = out + "\n"
    }
    i = i + 1
  }
  out
}

///|
fn hex2(v : Int) -> String {
  let n = if v < 0 { 0 } else if v > 255 { 255 } else { v }
  hexdig(n / 16) + hexdig(n % 16)
}

///|
/// 8x8 图块 → 文本 ASCII 预览（终端里直接看形状，最快的自检）
pub fn frame_ascii(f : Frame) -> String {
  let marks = [".", "1", "2", "3", "4", "5", "6", "7", "8"]
  let mut out = ""
  let mut y = 0
  while y < f.h {
    let mut x = 0
    let mut line = ""
    while x < f.w {
      let p = f.pix[y * f.w + x]
      line = line + (if p < marks.length() { marks[p] } else { "?" })
      x = x + 1
    }
    out = out + line + "\n"
    y = y + 1
  }
  out
}