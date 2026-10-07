// retro 白盒测试：FC/SFC 硬件约束 + 调色板量化 + 受约束精灵生成
//
// 核心断言只有一条，但它决定了整个包存在的意义：
//   **生成的 FC 精灵，用色数 ≤ 3（不含透明）。**
// 这条不成立，"程序化优先"就只是"生成彩色图"——不是 FC 时代的美术。

///|
fn dummy_spec() -> HeroSpec {
  {
    cap: (166, 39, 33),
    skin: (255, 224, 178),
    cloth: (11, 83, 215),
    pose: "idle",
  }
}

// ---------------- 硬件约束常量 ----------------

///|
test "retro：FC 精灵有效 3 色（4 色调色板减 index0 透明）" {
  assert_true(sprite_colors(FC) == 3)
  assert_true(sprite_colors(SFC) == 15) // SFC 精灵恒 4bpp=16，减透明
}

///|
test "retro：每扫描线精灵上限（FC 8 / SFC 32）" {
  assert_true(sprites_per_scanline(FC) == 8)
  assert_true(sprites_per_scanline(SFC) == 32)
}

///|
test "retro：精灵尺寸集合（FC 只 8x8/8x16；SFC 到 64x64）" {
  let fc = sprite_sizes(FC)
  assert_true(fc.length() == 2)
  assert_true(fc[0] == (8, 8))
  assert_true(fc[1] == (8, 16))
  let sfc = sprite_sizes(SFC)
  assert_true(sfc.length() == 4)
  assert_true(sfc[3] == (64, 64))
}

///|
test "retro：8x16 精灵占 2 个 8x8 图块（tile 预算约束）" {
  assert_true(tiles_per_sprite(8, 8) == 1)
  assert_true(tiles_per_sprite(8, 16) == 2)
  assert_true(tiles_per_sprite(16, 16) == 4)
}

///|
test "retro：调色板项数与图块预算（FC 单表 256 图块）" {
  assert_true(fc_palette_entries() == 32) // 8 组 x 4 色
  assert_true(tile_budget(FC) == 256)
  assert_true(tile_budget(SFC) == 8192)
}

///|
test "retro：FC 色强调位映射（PPUMASK bit5/6/7）" {
  assert_true(fc_emphasis_bits("none") == 0)
  assert_true(fc_emphasis_bits("red") == 1)
  assert_true(fc_emphasis_bits("green") == 2)
  assert_true(fc_emphasis_bits("blue") == 4)
  assert_true(fc_emphasis_bits("red+green+blue") == 7)
  assert_true(fc_emphasis_bits("bogus") == -1) // 非法名 → -1，不静默
  assert_true(fc_emphasis_variants().length() == 8)
}

///|
test "retro：SFC BGR555 打包/解包往返（5 位精度内无损）" {
  let v = sfc_pack_bgr555(255, 128, 0)
  let (r, g, b) = sfc_unpack_rgb(v)
  assert_true(absi(r - 255) <= 9) // 5 位量化误差 <= 9/255
  assert_true(absi(g - 128) <= 9)
  assert_true(b <= 9)
}

fn absi(a : Int) -> Int {
  if a < 0 { -a } else { a }
}

// ---------------- 调色板与量化 ----------------

///|
test "palette：FC 调色板 64 色" {
  assert_true(fc_palette().length() == 64)
}

///|
test "palette：最近色查找命中自身" {
  let c = fc_palette()[20]
  let idx = nearest_fc_index(c.0, c.1, c.2)
  assert_true(idx == 20)
}

///|
test "palette：纯白/纯黑映射到调色板两端" {
  assert_true(nearest_fc_index(255, 255, 255) == 32) // 第一行第三档起点
  let black = nearest_fc_index(0, 0, 0)
  assert_true(black >= 13) // 落在第一行暗档
}

///|
test "palette：颜色普查（识别的基础）" {
  // 4 个像素：红、红、蓝 → 2 种颜色
  let px = [255, 0, 0, 255, 0, 0, 0, 0, 255]
  let c = census(px)
  assert_true(c.distinct == 2)
  assert_true(c.colors.length() == 2)
  assert_true(c.counts.length() == 2)
  assert_true(c.counts[0] == 2) // 红出现 2 次（首次出现序）
}

///|
test "palette：量化到 3 色预算内不报错" {
  // 3 种颜色 → 恰好在预算内
  let px = [255, 0, 0, 0, 255, 0, 0, 0, 255]
  let q = quantize_fc(px, 3)
  assert_true(q.errors.length() == 0)
  assert_true(q.unique.length() == 3)
}

///|
test "palette：超预算报错（不静默——真机上会显示错）" {
  // 5 种明显不同的颜色，预算 3
  let px = [
    255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0, 128, 128, 128,
  ]
  let q = quantize_fc(px, 3)
  assert_true(q.errors.length() > 0)
}

///|
test "palette：FC 精灵调色板恰好 3 色" {
  let p = fc_sprite_palette((74, 158, 255), (255, 224, 178), (200, 60, 60))
  assert_true(p.length() == 3)
}

///|
test "palette：语义色冲突时补齐到 3 色（不返回 2 色）" {
  // 三个语义色几乎相同 → 去重后不足 3 → 必须补齐
  let p = fc_sprite_palette((100, 100, 100), (101, 101, 101), (102, 102, 102))
  assert_true(p.length() == 3)
}

///|
test "palette：调色板文本工件可 diff（含颜色 hex）" {
  let t = palette_to_text([(255, 0, 0), (0, 255, 0)], "hero")
  assert_true(t.find("#FF0000") is Some(_)) // 大写 hex
  assert_true(t.find("hero") is Some(_))
}

// ---------------- 受约束精灵生成（核心） ----------------

///|
test "sprite：FC 8x16 精灵生成正确尺寸" {
  let f = hero_frame(dummy_spec(), 8, 16)
  assert_true(f.w == 8)
  assert_true(f.h == 16)
  assert_true(f.pix.length() == 128)
}

///|
test "sprite：FC 精灵用色 ≤ 3（不含透明）——本包的核心断言" {
  let f = hero_frame(dummy_spec(), 8, 16)
  let used = distinct_indices([f])
  assert_true(used <= sprite_colors(FC)) // ≤3
  assert_true(used >= 1) // 不能是空图
}

///|
test "sprite：所有姿态都用色 ≤ 3（姿态变化不靠加色）" {
  let poses = ["idle", "walk1", "walk2", "jump", "fall", "duck"]
  for p in poses {
    let f = hero_frame(spec_with_pose(dummy_spec(), p), 8, 16)
    let used = distinct_indices([f])
    assert_true(used <= 3) // pose \{p} 用了 \{used} 色"
  }
}

///|
test "sprite：透明像素存在（轮廓靠透明，不靠第四色）" {
  let f = hero_frame(dummy_spec(), 8, 16)
  let mut transparent = 0
  for p in f.pix {
    if p == 0 {
      transparent = transparent + 1
    }
  }
  assert_true(transparent > 0) // 四角/边缘留空
}

///|
test "sprite：姿态产生不同像素（不是同一个图重复）" {
  let fa = hero_frame(spec_with_pose(dummy_spec(), "idle"), 8, 16)
  let fb = hero_frame(spec_with_pose(dummy_spec(), "duck"), 8, 16)
  let mut same = true
  let mut k = 0
  while k < fa.pix.length() {
    if fa.pix[k] != fb.pix[k] {
      same = false
      break
    }
    k = k + 1
  }
  assert_true(!same) // idle 与 duck 必须不同
}

///|
test "sprite：确定性——同参数必同结果（无随机源）" {
  let a = hero_frame(dummy_spec(), 8, 16)
  let b = hero_frame(dummy_spec(), 8, 16)
  let mut i = 0
  let mut all_same = true
  while i < a.pix.length() {
    if a.pix[i] != b.pix[i] {
      all_same = false
      break
    }
    i = i + 1
  }
  assert_true(all_same)
}

///|
test "sprite：clip 多姿态共享一套调色板（sprite sheet 硬件前提）" {
  let c = hero_clip("hero", dummy_spec(), FC, ["idle", "walk1", "walk2"])
  assert_true(c.frames.length() == 3)
  assert_true(c.palette.length() == 3) // 全部帧共用
  assert_true(c.errors.length() == 0)
}

///|
test "sprite：clip 空帧组报错" {
  let c = hero_clip("empty", dummy_spec(), FC, [])
  assert_true(c.errors.length() > 0)
}

///|
test "sprite：SFC 精灵 16x16，用色仍 ≤ 预算" {
  let c = hero_clip("hero_sfc", dummy_spec(), SFC, ["idle", "walk1"])
  assert_true(c.frames[0].w == 16)
  let used = distinct_indices(c.frames)
  assert_true(used <= sprite_colors(SFC)) // 15
}

// ---------------- 图块切分与 CHR 导出（制作 → 可用数据） ----------------

///|
test "sprite：8x8 图块切分" {
  let f = hero_frame(dummy_spec(), 8, 16)
  let tiles = slice_tiles(f, 8, 8)
  assert_true(tiles.length() == 2) // 8x16 → 上下两个 8x8
  assert_true(tiles[0].w == 8)
  assert_true(tiles[0].h == 8)
}

///|
test "sprite：图块切分可逆（拼回去等于原图）" {
  let f = hero_frame(dummy_spec(), 16, 16)
  let tiles = slice_tiles(f, 8, 8)
  assert_true(tiles.length() == 4) // 2x2
  // 逐块比对
  let mut i = 0
  let mut ok = true
  for t in tiles {
    let tx = (i % 2) * 8
    let ty = (i / 2) * 8
    let mut y = 0
    while y < 8 {
      let mut x = 0
      while x < 8 {
        if t.pix[y * 8 + x] != f.pix[(ty + y) * f.w + (tx + x)] {
          ok = false
        }
        x = x + 1
      }
      y = y + 1
    }
    i = i + 1
  }
  assert_true(ok)
}

///|
test "sprite：CHR 导出 16 字节（2bpp：低平面8 + 高平面8）" {
  let f = hero_frame(dummy_spec(), 8, 8)
  let chr = to_chr(f)
  assert_true(chr.length() == 16)
}

///|
test "sprite：CHR 位平面语义（下标1→平面0，下标2→平面1，下标3→两平面）" {
  let f = hero_frame(dummy_spec(), 8, 8)
  let mut i = 0
  while i < f.pix.length() {
    f.pix[i] = 0
    i = i + 1
  }
  let cases = [0, 1, 2, 3]
  for v in cases {
    let mut k = 0
    while k < f.pix.length() {
      f.pix[k] = v
      k = k + 1
    }
    let chr = to_chr(f)
    let want_lo = if (v & 1) == 1 { 255 } else { 0 }
    let want_hi = if ((v >> 1) & 1) == 1 { 255 } else { 0 }
    assert_true(chr[0] == want_lo) // 下标 \{v} 的平面0
    assert_true(chr[8] == want_hi) // 下标 \{v} 的平面1
  }
}

///|
test "sprite：CHR 导出对 8x16 按 2 个图块导出（32 字节）" {
  // FC 的 8x16 精灵 = 2 个 8x8 图块，各 16 字节。这是真实 CHR 的组织方式。
  let f = hero_frame(dummy_spec(), 8, 16)
  let chr = to_chr(f)
  assert_true(chr.length() == 32)
  assert_true(tiles_per_sprite(8, 16) * 16 == chr.length())
}

///|
test "sprite：CHR 往返无损 —— 8x16 精灵（制作→识别可逆）" {
  // "资源制作"与"资源识别"共用同一编码的可核对证据：
  // 生成器产出 → CHR 字节 → 读回 → 必须与原帧逐像素一致。
  let f = hero_frame(dummy_spec(), 8, 16)
  let chr = to_chr(f)
  let back = from_chr(chr, 8, 16)
  assert_true(back.w == 8)
  assert_true(back.h == 16)
  let mut i = 0
  let mut ok = true
  while i < f.pix.length() {
    if back.pix[i] != f.pix[i] {
      ok = false
      break
    }
    i = i + 1
  }
  assert_true(ok)
}

///|
test "sprite：CHR 往返无损 —— 8x8 图块" {
  let f = hero_frame(dummy_spec(), 8, 8)
  let chr = to_chr(f)
  let back = from_chr(chr, 8, 8)
  let mut i = 0
  let mut ok = true
  while i < f.pix.length() {
    if back.pix[i] != f.pix[i] {
      ok = false
      break
    }
    i = i + 1
  }
  assert_true(ok)
}

///|
test "sprite：CHR 往返无损 —— SFC 16x16（4 个图块）" {
  let f = hero_frame(dummy_spec(), 16, 16)
  let chr = to_chr(f)
  // 16 宽 = 2 图块横排，16 高 = 2 图块竖排 = 4 图块
  assert_true(chr.length() == 64)
  let back = from_chr(chr, 16, 16)
  let mut i = 0
  let mut ok = true
  while i < f.pix.length() {
    if back.pix[i] != f.pix[i] {
      ok = false
      break
    }
    i = i + 1
  }
  assert_true(ok)
}

///|
test "sprite：CHR 单行位序正确（bit0 = 最左像素）" {
  let f = hero_frame(dummy_spec(), 8, 8)
  let mut i = 0
  while i < f.pix.length() {
    f.pix[i] = 0
    i = i + 1
  }
  // 只把第 3 列设为下标 1 → 平面0 第0行 = 0b00001000 = 8
  f.pix[3] = 1
  let chr = to_chr(f)
  assert_true(chr[0] == 8)
  assert_true(chr[8] == 0)
}

///|
test "sprite：CHR 导出长度恒等于 图块数 × 16" {
  // 2bpp 图块 = 16 字节；FC 8x16 = 2 图块；SFC 16x16 = 4 图块
  let f8 = hero_frame(dummy_spec(), 8, 8)
  assert_true(to_chr(f8).length() == 16)
  let f16 = hero_frame(dummy_spec(), 8, 16)
  assert_true(to_chr(f16).length() == 32)
  let sfc = hero_frame(dummy_spec(), 16, 16)
  assert_true(to_chr(sfc).length() == 64)
}

///|
test "sprite：水平镜像（朝向覆盖优先于帧数）" {
  let f = hero_frame(dummy_spec(), 8, 16)
  let m = flip_h(f)
  assert_true(m.w == 8)
  assert_true(m.h == 16)
  // 逐行左右交换
  let mut y = 0
  let mut ok = true
  while y < f.h {
    let mut x = 0
    while x < f.w {
      if m.pix[y * m.w + x] != f.pix[y * f.w + (f.w - 1 - x)] {
        ok = false
      }
      x = x + 1
    }
    y = y + 1
  }
  assert_true(ok)
}

///|
test "sprite：垂直拼接" {
  let a = hero_frame(dummy_spec(), 8, 8)
  let b = hero_frame(dummy_spec(), 8, 8)
  let s = vstack(a, b)
  assert_true(s.h == 16)
  assert_true(s.w == 8)
  assert_true(s.pix.length() == 128)
}

///|
test "sprite：clip 报告可读（含预算与是否超限）" {
  let c = hero_clip("hero", dummy_spec(), FC, ["idle", "walk1"])
  let r = clip_report(c)
  assert_true(r.find("hero") is Some(_))
  assert_true(r.find("budget") is Some(_))
  assert_true(r.find("scanline") is Some(_))
}

// ---------------- 识别闭环：透明必须被剔除 ----------------

///|
test "sprite：透明标记不是第 4 色（剔除前后颜色数不同）" {
  // 这是识别能力最容易犯的错：把 frame_to_rgb 的洋红标记算成实体色，
  // FC 精灵就会误报成 4 色超预算。
  let f = hero_frame(dummy_spec(), 8, 16)
  let pal = fc_sprite_palette(dummy_spec().cap, dummy_spec().skin, dummy_spec().cloth)
  let with_alpha = frame_to_rgb(f, pal)
  let opaque = frame_to_rgb_opaque(f, pal)
  let c_all = census(with_alpha)
  let c_op = census(opaque)
  assert_true(c_all.distinct == c_op.distinct + 1) // 洋红多算一种
  assert_true(c_op.distinct <= 3) // 剔除后合规
}

///|
test "sprite：剔除透明后 FC 精灵量化不超预算" {
  let f = hero_frame(dummy_spec(), 8, 16)
  let pal = fc_sprite_palette(dummy_spec().cap, dummy_spec().skin, dummy_spec().cloth)
  let q = quantize_fc(frame_to_rgb_opaque(f, pal), sprite_colors(FC))
  assert_true(q.errors.length() == 0) // 不该超预算
  assert_true(q.unique.length() <= 3)
}

///|
test "sprite：透明像素计数（轮廓预算）" {
  let f = hero_frame(dummy_spec(), 8, 16)
  let t = transparent_count(f)
  assert_true(t > 0)
  assert_true(t < f.pix.length()) // 不能全透明也不能全不透明
}

///|
test "sprite：产出资源整体合规（生成→CHR→读回→普查 全链路）" {
  // 端到端契约：agent 用 CLI 造出来的资源，必须同时满足
  //   用色 ≤ 预算、CHR 往返无损、量化不超预算
  for r in [FC, SFC] {
    let c = hero_clip("hero", dummy_spec(), r, ["idle", "walk1", "duck"])
    assert_true(c.errors.length() == 0) // 用色在预算内
    let f = c.frames[0]
    let pal = c.palette
    // CHR 往返
    let chr = to_chr(f)
    let back = from_chr(chr, f.w, f.h)
    let mut i = 0
    while i < f.pix.length() {
      assert_true(back.pix[i] == f.pix[i])
      i = i + 1
    }
    // 量化（剔除透明）
    let q = quantize_fc(frame_to_rgb_opaque(f, pal), sprite_colors(r))
    assert_true(q.errors.length() == 0)
  }
}

///|
test "sprite：ASCII 预览可读（识别形状用）" {
  let f = hero_frame(dummy_spec(), 8, 8)
  let a = frame_ascii(f)
  assert_true(a.find("\n") is Some(_))
  assert_true(a.length() > 8) // 至少一行
}

///|
test "sprite：SVG 工件含像素与棋盘底（视觉自检）" {
  let f = hero_frame(dummy_spec(), 8, 16)
  let pal = fc_sprite_palette(dummy_spec().cap, dummy_spec().skin, dummy_spec().cloth)
  let s = frame_svg(f, pal, 8)
  assert_true(s.find("<svg") is Some(_))
  assert_true(s.find("crispEdges") is Some(_)) // 像素不模糊
  assert_true(s.find("url(#ck)") is Some(_)) // 透明棋盘底
}

///|
test "sprite：clip SVG 横排全部姿态 + 调色板色条" {
  let c = hero_clip("hero", dummy_spec(), FC, ["idle", "walk1", "walk2"])
  let s = clip_svg(c, 6)
  assert_true(s.find("#0") is Some(_)) // 帧号标签
  assert_true(s.find("transparent") is Some(_)) // idx0 标注
}

///|
test "sprite：SVG 颜色是合法 #RRGGBB（回归防护）" {
  // 曾经的 bug：hexc 让每个通道各自加 "#"，拼出 `#A6#27#21` 这种非法颜色。
  // SVG 在浏览器里会**静默渲染失败**——不报错，图就是空白的。
  // 所以必须逐个校验所有 fill 值的格式。
  let c = hero_clip("hero", dummy_spec(), FC, ["idle", "walk1"])
  let s = clip_svg(c, 6)
  let f = hero_frame(dummy_spec(), 8, 16)
  let pal = fc_sprite_palette(dummy_spec().cap, dummy_spec().skin, dummy_spec().cloth)
  let s2 = frame_svg(f, pal, 8)
  for doc in [s, s2] {
    // 逐个检查 fill="#..." 的值：必须是 7 字符（# + 6 位 hex）
    let mut i = 0
    while i + 7 <= doc.length() {
      if doc.substring(start=i, end=i + 7) == "fill=\"" {
        let rest = doc.substring(start=i + 6)
        if rest.length() >= 7 {
          let hex = rest.substring(start=0, end=7)
          assert_true(hex.length() == 7) // 颜色值不是 7 字符：'\{hex}'"
          assert_true(hex.substring(start=0, end=1) == "#")
          // 后 6 位必须是 hex 字符，且不含 '#'
          let body = hex.substring(start=1, end=7)
          assert_true(body.find("#") is None) // 颜色值里有第二个 #：'\{hex}'"
          let digits = "0123456789ABCDEFabcdef"
          let mut k = 0
          while k < 6 {
            let ch = body.substring(start=k, end=k + 1)
            assert_true(digits.find(ch) is Some(_)) // 非 hex 字符 '\{ch}' 于 '\{hex}'"
            k = k + 1
          }
        }
        i = i + 7
        continue
      }
      i = i + 1
    }
  }
}

///|
test "sprite：CHR hexdump 是 16 进制可读文本" {
  let f = hero_frame(dummy_spec(), 8, 8)
  let h = chr_hexdump(to_chr(f), 8)
  assert_true(h.find("\n") is Some(_))
  // 每字节两位 hex + 空格
  assert_true(h.find("00") is Some(_))
}

// ---------------- 人物造型的结构性质（FC 人物该有的样子） ----------------

///|
fn count_row(f : Frame, y : Int, p : Pix) -> Int {
  let mut n = 0
  let mut x = 0
  while x < f.w {
    if f.pix[y * f.w + x] == p {
      n = n + 1
    }
    x = x + 1
  }
  n
}

///|
test "sprite：人物有帽子（FC 人物的签名特征）" {
  // 帽子是 FC 人物最重要的识别特征——没有帽子的 8x16 精灵读不出"人"
  let f = hero_frame(dummy_spec(), 8, 16)
  assert_true(count_row(f, 1, 1) >= 4) // 帽顶一行至少 4px 帽色
  assert_true(count_row(f, 2, 1) >= 4) // 帽檐
}

///|
test "sprite：人物有脸（皮肤色在头部区域出现）" {
  let f = hero_frame(dummy_spec(), 8, 16)
  let mut skin_px = 0
  let mut y = 3
  while y < 5 {
    skin_px = skin_px + count_row(f, y, 2)
    y = y + 1
  }
  assert_true(skin_px >= 4)
}

///|
test "sprite：人物有鞋（最底一行踩实）" {
  // FC 人物读得出"站住"靠鞋：最底一行必须是实体色，不能空
  let f = hero_frame(dummy_spec(), 8, 16)
  assert_true(count_row(f, 15, 3) >= 4) // idle 的鞋底踩满
}

///|
test "sprite：walk1 与 walk2 是不同的步态帧（不是同一帧重复）" {
  // 回归防护：早期实现里 walk1/walk2 完全相同——动画等于没做
  let a = hero_frame(spec_with_pose(dummy_spec(), "walk1"), 8, 16)
  let b = hero_frame(spec_with_pose(dummy_spec(), "walk2"), 8, 16)
  let mut same = true
  let mut i = 0
  while i < a.pix.length() {
    if a.pix[i] != b.pix[i] {
      same = false
      break
    }
    i = i + 1
  }
  assert_true(!same) // 两个步态帧必须不同
}

///|
test "sprite：walk2 的下半身是 walk1 的左右镜像（步态循环闭合）" {
  // FC 走路动画的标准做法：两帧下半身互为镜像，形成完整步态。
  // 上半身不能比——帽檐向右伸出表示朝向，镜像会把朝向翻掉（那是另一件事）。
  let a = hero_frame(spec_with_pose(dummy_spec(), "walk1"), 8, 16)
  let b = hero_frame(spec_with_pose(dummy_spec(), "walk2"), 8, 16)
  let mut y = 10 // 下半身起点（腿）
  while y < 16 {
    let mut x = 0
    while x < a.w {
      let mirrored = a.pix[y * a.w + (a.w - 1 - x)]
      assert_true(b.pix[y * b.w + x] == mirrored) // 下半身 row \{y} col \{x} 不是镜像"
      x = x + 1
    }
    y = y + 1
  }
}

///|
test "sprite：duck 比 idle 矮（上半身下移）" {
  // 压扁姿态的核心：整体高度变小
  let idle = hero_frame(spec_with_pose(dummy_spec(), "idle"), 8, 16)
  let duck = hero_frame(spec_with_pose(dummy_spec(), "duck"), 8, 16)
  assert_true(count_row(idle, 1, 1) > 0)
  assert_true(count_row(duck, 1, 1) == 0) // duck 顶部留空
  assert_true(count_row(duck, 5, 1) > 0) // duck 的帽子在 y=5
}

///|
test "sprite：jump 的脚离地（最底行空）" {
  let f = hero_frame(spec_with_pose(dummy_spec(), "jump"), 8, 16)
  assert_true(count_row(f, 15, 3) == 0) // 鞋底不踩地
  assert_true(count_row(f, 14, 3) > 0) // 鞋在 y=14 悬空
}

///|
test "sprite：六个姿态两两不同（动画帧不重复）" {
  let frames = [
    hero_frame(spec_with_pose(dummy_spec(), "idle"), 8, 16),
    hero_frame(spec_with_pose(dummy_spec(), "walk1"), 8, 16),
    hero_frame(spec_with_pose(dummy_spec(), "walk2"), 8, 16),
    hero_frame(spec_with_pose(dummy_spec(), "jump"), 8, 16),
    hero_frame(spec_with_pose(dummy_spec(), "fall"), 8, 16),
    hero_frame(spec_with_pose(dummy_spec(), "duck"), 8, 16),
  ]
  let mut a = 0
  while a < frames.length() {
    let mut b = a + 1
    while b < frames.length() {
      let mut same = true
      let mut i = 0
      while i < frames[a].pix.length() {
        if frames[a].pix[i] != frames[b].pix[i] {
          same = false
          break
        }
        i = i + 1
      }
      assert_true(!same) // 帧 \{a} 与 \{b} 重复了"
      b = b + 1
    }
    a = a + 1
  }
}

///|
test "sprite：除 duck 外所有姿态的上半身一致（头部稳定是 FC 动画手法）" {
  // duck 是唯一压扁姿态（头要下移），其余姿态头部必须逐像素稳定
  let poses = ["idle", "walk1", "walk2", "jump", "fall"]
  let base = hero_frame(spec_with_pose(dummy_spec(), "idle"), 8, 16)
  for p in poses {
    let f = hero_frame(spec_with_pose(dummy_spec(), p), 8, 16)
    // y=1..5（帽子+脸+胡子）必须逐像素相同
    let mut y = 1
    while y < 6 {
      let mut x = 0
      while x < f.w {
        assert_true(f.pix[y * f.w + x] == base.pix[y * base.w + x]) // 姿态 \{p} 的头部 row \{y} 动了"
        x = x + 1
      }
      y = y + 1
    }
  }
}

///|
test "sprite：所有姿态仍 ≤3 色（重做造型不能破预算）" {
  let poses = ["idle", "walk1", "walk2", "jump", "fall", "duck"]
  for p in poses {
    let f = hero_frame(spec_with_pose(dummy_spec(), p), 8, 16)
    assert_true(distinct_indices([f]) <= 3) // 姿态 \{p} 超预算"
  }
}

// ---------------- preset 配色 ----------------

///|
fn pal_of(name : String) -> Array[(Int, Int, Int)] {
  let s = preset_by_name(name)
  fc_sprite_palette(s.cap, s.skin, s.cloth)
}

///|
test "sprite：preset 具名配色可区分（不同 preset 调色板不同）" {
  assert_true(pal_of("plumber") != pal_of("ninja"))
  assert_true(pal_of("ice") != pal_of("fire"))
}

///|
test "sprite：每个 preset 都恰好 3 色且合规" {
  let names = ["plumber", "green_cap", "tan_hero", "ninja", "ice", "fire"]
  for n in names {
    assert_true(pal_of(n).length() == 3) // preset \{n} 的调色板不是 3 色"
    let f = hero_frame(preset_by_name(n), 8, 16)
    assert_true(distinct_indices([f]) <= 3)
  }
}

///|
test "sprite：preset 确定性（同名必同结果）" {
  let a = preset_by_name("plumber")
  let b = preset_by_name("plumber")
  assert_true(a.cap == b.cap)
  assert_true(a.skin == b.skin)
  assert_true(a.cloth == b.cloth)
}

///|
test "sprite：preset 未知名落回默认（不崩）" {
  let s = preset_by_name("不存在的角色名")
  let f = hero_frame(s, 8, 16)
  assert_true(distinct_indices([f]) <= 3)
}

// ---------------- SFC 不是退化分支（回归防护） ----------------

///|
test "sprite：body_box 按帧宽推导（FC 6px 身体 / SFC 14px 身体）" {
  let b8 = body_box(8)
  assert_true(b8.x == 1)
  assert_true(b8.w == 6) // 8 - 2 留白
  let b16 = body_box(16)
  assert_true(b16.x == 1)
  assert_true(b16.w == 14) // 16 - 2 留白
}

///|
/// 帧内非透明像素的横向包围盒 (min_x, max_x)
fn bbox(f : Frame) -> (Int, Int) {
  let mut min_x = f.w
  let mut max_x = -1
  let mut y = 0
  while y < f.h {
    let mut x = 0
    while x < f.w {
      if f.pix[y * f.w + x] != 0 {
        if x < min_x {
          min_x = x
        }
        if x > max_x {
          max_x = x
        }
      }
      x = x + 1
    }
    y = y + 1
  }
  (min_x, max_x)
}

///|
test "sprite：SFC 16x16 人物占满帧宽（不再是左侧半边的退化产物）" {
  // 回归防护：曾把下半身坐标写死成 8 宽假设，于是 SFC 的 16 宽帧里
  // 人物只占左边 8px、右半全空——**SFC 支持名义存在，实际是退化分支**。
  // 判据：横向包围盒必须覆盖帧宽的主体（≥ 3/4），而不能只占一半。
  let f = hero_frame(dummy_spec(), 16, 16)
  let (lo, hi) = bbox(f)
  let span = hi - lo + 1
  assert_true(span * 4 >= f.w * 3) // 只占了 \{span}/\{f.w} 宽度"
  // 具体地：SFC 人物必须触达右半区（x ≥ 8）
  assert_true(hi >= 8) // 右边缘只到 \{hi}，没进右半区"
}

///|
test "sprite：SFC 人物左右不留白（帽檐/鞋伸出 = 朝向信号）" {
  // 与 FC 的差别：FC 8 宽时人物是 x=1..6 + 帽檐 x=7；SFC 16 宽时
  // 身体 x=1..14 + 帽檐 x=15 —— 两端都不留白。
  // 帽檐向右伸出 1px 是**故意的朝向信号**（side view 一律朝右，blueprint §6.3），
  // 所以"左右各留 1px"只在身体框层面成立，整帧层面帽檐会触到最后一列。
  let f = hero_frame(dummy_spec(), 16, 16)
  let (_, hi) = bbox(f)
  assert_true(hi == 15) // 右边缘应触到最后一列（帽檐/鞋）"
}

///|
test "sprite：SFC 与 FC 的造型逻辑同源（同一份 BodyBox 驱动）" {
  // 两侧的躯干宽度都应等于 body_box 的宽度（帽檐伸出不算在内）
  let fc = hero_frame(dummy_spec(), 8, 16)
  let sfc = hero_frame(dummy_spec(), 16, 16)
  // 躯干行（y=7）应当正好铺满 body 宽度
  let fc_body = count_row(fc, 7, 3) // cloth
  let sfc_body = count_row(sfc, 7, 3)
  assert_true(fc_body == body_box(8).w) // FC 躯干宽 \{fc_body} ≠ box 宽 \{body_box(8).w}"
  assert_true(sfc_body == body_box(16).w) // SFC 躯干宽 \{sfc_body} ≠ box 宽 \{body_box(16).w}"
}

///|
test "sprite：SFC 六姿态仍 ≤3 色且用满宽度" {
  let poses = ["idle", "walk1", "walk2", "jump", "fall", "duck"]
  for p in poses {
    let f = hero_frame(spec_with_pose(dummy_spec(), p), 16, 16)
    assert_true(distinct_indices([f]) <= 3) // SFC 姿态 \{p} 超色"
    let (lo, hi) = bbox(f)
    assert_true(hi - lo + 1 >= 12) // SFC 姿态 \{p} 只占了 \{hi - lo + 1}px"
  }
}

///|
test "sprite：SFC walk2 下半身仍是 walk1 的镜像" {
  // 镜像不变量必须在两个平台都成立（BodyBox 重构后曾一度破坏）
  let a = hero_frame(spec_with_pose(dummy_spec(), "walk1"), 16, 16)
  let b = hero_frame(spec_with_pose(dummy_spec(), "walk2"), 16, 16)
  let mut y = 10
  while y < 16 {
    let mut x = 0
    while x < a.w {
      assert_true(b.pix[y * b.w + x] == a.pix[y * a.w + (a.w - 1 - x)]) // SFC 镜像失败 row \{y} col \{x}"
      x = x + 1
    }
    y = y + 1
  }
}