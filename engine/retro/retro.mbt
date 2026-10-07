// retro —— FC/SFC 世代的硬件资源约束（数据层，零渲染依赖）
//
// 存在的理由：blueprint §6.0「程序化优先」若不锚定真实硬件约束，
// 生成出来的"像素画"只是普通的彩色方块图，不是 FC/SFC 时代的东西。
// 这里把约束写成**可执行的数据 + 可测的门禁**，让生成器必须遵守。
//
// 所有数字来自 nesdev / famicom.party / wiki.superfamicom.org / SnesLab
// （调研记录见 docs/blueprint.md §6.5）。要点：
//
//  **FC（NES/FC）**
//   - PPU 输出 64 色（模拟电压，非权威 hex 表——任何 hex 列表都是近似）
//   - 精灵：4 色调色板但 index 0 恒透明 → **有效 3 色**
//   - 背景：每个 metatile（2×2 图块）4 色
//   - 调色板 RAM：8 组 × 4 色 = 32 项
//   - 色强调：PPUMASK bit5/6/7 = 红/绿/蓝强调（3 位 → 8 组），
//     另有 bit0 灰度。强调不是「乘一个系数」——它衰减另外两个通道
//   - 精灵：8/扫描线、64/帧；尺寸 8×8 或 8×16（后者占 2 个 8×8 图块）
//   - 图块：8×8；单个 pattern table 256 个不同图块 → 一屏 960 位置
//     最多 256 种不同图块（**必须复用**，这是 tile 预算约束）
//   - $0D 是「禁用色」（NTSC 上会黑化成 $0F），含它的调色板实际只有 3 色
//
//  **SFC（SNES/SFC）**
//   - CGRAM 512 字节 = 256 色 × 2 字节，BGR555（15 位，共 32768 色）
//   - 精灵**恒为 4bpp**（16 色调色板），与 BG 模式无关
//   - BG 层：2bpp(4色) / 4bpp(16色) / 8bpp(256色)，按模式
//   - 任何调色板 index 0 恒透明
//   - 精灵：128 总数、32/扫描线、8×8 / 16×16 / 32×32 / 64×64
//     （同时只有两种尺寸可用，由 $2101 选择）
//   - VRAM 64 KB；BG 字符基址按 8 KB 对齐（(Base << 13)）
//   - Mode 7：256 色单层 + 2D 仿射变换

///|
pub(all) enum Retro {
  FC
  SFC
}

///|
/// 平台名（枚举没有 Show，插值要用字符串）
pub fn retro_name(r : Retro) -> String {
  match r {
    FC => "FC"
    SFC => "SFC"
  }
}

///|
/// 每精灵/每图块的**有效**颜色数（不含恒透明的 index 0）
///
/// 这是「程序化生成必须遵守」的硬约束，也是本包存在的核心。
/// FC 精灵 3 色、FC 背景 4 色、SFC 精灵 15 色（16 减透明）、SFC 背景按 bpp。
pub fn sprite_colors(r : Retro) -> Int {
  match r {
    FC => 3 // 4 项调色板，index 0 透明 → 有效 3
    SFC => 15 // 恒 4bpp = 16 项，index 0 透明 → 有效 15
  }
}

///|
/// 每背景 metatile 的有效颜色数
pub fn bg_colors(r : Retro, bpp : Int) -> Int {
  match r {
    FC => 3 // metatile 4 色，共享底层 backdrop，index 0 常作背景色
    SFC => {
      // 2bpp=4, 4bpp=16, 8bpp=256，各减透明 index 0
      match bpp {
        2 => 3
        4 => 15
        8 => 255
        _ => 3
      }
    }
  }
}

///|
/// 每扫描线精灵数上限（超出 → 精灵闪烁/丢失）
pub fn sprites_per_scanline(r : Retro) -> Int {
  match r {
    FC => 8
    SFC => 32
  }
}

///|
/// 精灵尺寸（像素），FC 只支持 8×8 / 8×16
pub fn sprite_sizes(r : Retro) -> Array[(Int, Int)] {
  match r {
    FC => [(8, 8), (8, 16)]
    SFC => [(8, 8), (16, 16), (32, 32), (64, 64)]
  }
}

///|
/// 一个 8×16 精灵占用的 8×8 图块数（= 高度/8）
pub fn tiles_per_sprite(w : Int, h : Int) -> Int {
  (w + 7) / 8 * ((h + 7) / 8)
}

///|
/// FC 色强调：bit0=红 bit1=绿 bit2=蓝（对应 PPUMASK $2001 bit5/6/7）
///
/// 强调名 → 位掩码（0..7）。返回 -1 = 名字非法。
///
/// 重要：强调是**衰减另外两个通道并压暗**，不是给所有通道乘系数——
/// 当作乘法用会得到错误的颜色（调研已确认这条常被搞错）。
pub fn fc_emphasis_bits(which : String) -> Int {
  match which {
    "none" => 0
    "red" => 1
    "green" => 2
    "red+green" => 3
    "blue" => 4
    "red+blue" => 5
    "green+blue" => 6
    "red+green+blue" => 7
    _ => -1
  }
}

///|
/// FC 色强调变体列表（0..7 全枚举，含灰度开关）
/// 生成器用它决定「一屏用哪组强调」——FC 美术的暗部层次主要靠这个。
pub fn fc_emphasis_variants() -> Array[String] {
  [
    "none",
    "red",
    "green",
    "red+green",
    "blue",
    "red+blue",
    "green+blue",
    "red+green+blue",
  ]
}

///|
/// SFC BG 模式可用层数（每层 bpp 与是否逐图块偏移）
pub fn sfc_bg_mode(m : Int) -> Array[Int] {
  // 返回各层 bpp（0 = 该模式无此层）
  match m {
    0 => [2, 2, 2, 2]
    1 => [4, 4, 2, 0]
    2 => [4, 4, 0, 0]
    3 => [8, 4, 0, 0]
    4 => [8, 2, 0, 0]
    5 => [4, 2, 0, 0] // EXTBG 另加一层 2bpp
    6 => [4, 0, 0, 0]
    7 => [8, 0, 0, 0] // EXTBG 加 128 色层
    _ => [0, 0, 0, 0]
  }
}

///|
/// 一屏分辨率
pub fn screen_size(r : Retro) -> (Int, Int) {
  match r {
    FC => (256, 240)
    SFC => (256, 224)
  }
}

///|
/// 图块预算：单个 pattern table / VRAM 能放的不同图块数
///
/// FC 8KB CHR = 2 pattern table × 256 图块 → 每表 256。
/// 超过就必须复用——这是 tile 预算约束（调研确认：8KB CHR 是典型容量）。
pub fn tile_budget(r : Retro) -> Int {
  match r {
    FC => 256 // 单 pattern table（不 bank）
    SFC => 8192 // 64KB VRAM / 8 字节每图块(2bpp) = 8192
  }
}

///|
/// FC 调色板调色项数（8 组 × 4 色，但 index0 与 backdrop 共享）
pub fn fc_palette_entries() -> Int {
  32
}