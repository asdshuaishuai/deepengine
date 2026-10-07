// sprite —— FC/SFC 受约束的程序化精灵生成器（"资源制作能力"的本体）
//
// 设计立场（与 blueprint §6.0「程序化优先」一致，但更硬）：
// **不是"生成真彩色再量化"，而是"在硬件约束内直接生成"。**
//
// 理由：FC 精灵只有 3 色 + 透明。先生成彩色图再量化，会得到
// 抖动/色斑（dithering artifacts）——那是"把彩色图塞进 4 格"，
// 不是"用 4 格画画"。真正的 FC 美术是**一开始就知道只有 3 笔**，
// 用明暗两档 + 强调色去造型。
//
// 因此本生成器：
//   ① 调色板固定 4 项（index0 透明 + 3 实体色），取自 FC 调色板
//   ② 造型靠 **色阶分配**（哪块用亮/中/暗），不是靠颜色渐变
//   ③ 输出带 **调色板下标** 的像素（2bpp 语义），可直接喂 CHR 写入
//   ④ 自带契约门禁：用色数、图块占用、透明像素位置，全部可测
//
// 帧组（clip）：同一角色的多个姿态帧共享调色板——这是 sprite sheet 的
// 硬件前提（8KB CHR 里一套角色只能占有限的图块数）。

///|
/// 一个像素：调色板下标（0 = 透明）
pub(all) type Pix = Int

///|
/// 一帧：宽 × 高的调色板下标，按行主序
pub(all) struct Frame {
  pub w : Int
  pub h : Int
  pub pix : Array[Pix]
}

///|
/// 一组帧 + 共享调色板（= 一个 sprite 的全部资源）
pub(all) struct Clip {
  pub name : String
  pub frames : Array[Frame]
  /// 调色板：index0 = 透明，其余为 FC 调色板颜色
  pub palette : Array[(Int, Int, Int)]
  pub retro : Retro
  /// 生成期诊断（契约违规写这里，不静默）
  pub errors : Array[String]
  pub warnings : Array[String]
}

// ---------------- 基础绘制原语（全部在调色板下标空间） ----------------

///|
fn new_frame(w : Int, h : Int, fill : Pix) -> Frame {
  let pix : Array[Pix] = []
  let mut i = 0
  while i < w * h {
    pix.push(fill)
    i = i + 1
  }
  { w: w, h: h, pix: pix }
}

///|
fn px_at(f : Frame, x : Int, y : Int) -> Pix {
  f.pix[y * f.w + x]
}

///|
fn set_px(f : Frame, x : Int, y : Int, p : Pix) -> Unit {
  if x >= 0 && x < f.w && y >= 0 && y < f.h {
    f.pix[y * f.w + x] = p
  }
}

///|
/// 实心矩形
fn fill_rect(f : Frame, x : Int, y : Int, w : Int, h : Int, p : Pix) -> Unit {
  let mut yy = y
  while yy < y + h {
    let mut xx = x
    while xx < x + w {
      set_px(f, xx, yy, p)
      xx = xx + 1
    }
    yy = yy + 1
  }
}

///|
/// 水平线
fn hline(f : Frame, x : Int, y : Int, w : Int, p : Pix) -> Unit {
  fill_rect(f, x, y, w, 1, p)
}

///|
/// 垂直线
fn vline(f : Frame, x : Int, y : Int, h : Int, p : Pix) -> Unit {
  fill_rect(f, x, y, 1, h, p)
}

///|
/// 1px 描边（沿矩形四周）。FC 美术的主力——用 1px 暗色勾边
/// 是"读得出轮廓"的关键，也是省色（不填第四种色）。
fn outline(f : Frame, x : Int, y : Int, w : Int, h : Int, p : Pix) -> Unit {
  hline(f, x, y, w, p)
  hline(f, x, y + h - 1, w, p)
  vline(f, x, y, h, p)
  vline(f, x + w - 1, y, h, p)
}

///|
/// 水平镜像（确定性 hflip——blueprint §6.3「永不因朝向重新生成」）
fn flip_h(f : Frame) -> Frame {
  let out = new_frame(f.w, f.h, 0)
  let mut y = 0
  while y < f.h {
    let mut x = 0
    while x < f.w {
      out.pix[y * out.w + x] = f.pix[y * f.w + (f.w - 1 - x)]
      x = x + 1
    }
    y = y + 1
  }
  out
}

///|
/// 把帧垂直拼接到另一帧下方（同宽）
fn vstack(top : Frame, bottom : Frame) -> Frame {
  let out = new_frame(top.w, top.h + bottom.h, 0)
  let mut y = 0
  while y < top.h {
    let mut x = 0
    while x < top.w {
      out.pix[y * out.w + x] = top.pix[y * top.w + x]
      x = x + 1
    }
    y = y + 1
  }
  let mut y2 = 0
  while y2 < bottom.h {
    let mut x = 0
    while x < bottom.w {
      out.pix[(top.h + y2) * out.w + x] = bottom.pix[y2 * bottom.w + x]
      x = x + 1
    }
    y2 = y2 + 1
  }
  out
}

///|
/// 8×8 图块切分（FC CHR 语义：8 字节/图块）。
/// 返回切出的图块数组（行优先）——这是"资源识别"的反向操作：
/// 引擎既能生成 CHR，也能把 CHR 读回来认。
pub fn slice_tiles(f : Frame, tile_w : Int, tile_h : Int) -> Array[Frame] {
  let out : Array[Frame] = []
  let mut ty = 0
  while ty + tile_h <= f.h {
    let mut tx = 0
    while tx + tile_w <= f.w {
      let t = new_frame(tile_w, tile_h, 0)
      let mut y = 0
      while y < tile_h {
        let mut x = 0
        while x < tile_w {
          t.pix[y * tile_w + x] = f.pix[(ty + y) * f.w + (tx + x)]
          x = x + 1
        }
        y = y + 1
      }
      out.push(t)
      tx = tx + tile_w
    }
    ty = ty + tile_h
  }
  out
}

///|
/// 图块 → FC CHR 字节流（2bpp planar：低平面 8 字节 + 高平面 8 字节）
///
/// 这是"资源制作"的关键一步：生成器产出可以直接喂给真实 FC 的 CHR 数据。
///
/// 2bpp planar 的正确语义（写错会得到全反的图）：
///   bit0（平面0）= 下标的低位  = `p & 1`      → 下标 1、3 置位
///   bit1（平面1）= 下标的高位  = `(p >> 1) & 1` → 下标 2、3 置位
///   调色板下标    = 平面0 | (平面1 << 1)
/// 字节内 bit 顺序：**从左到右对应 x=0..7**（bit0 = 最左像素）。
///
/// **按图块序列导出**（FC 精灵 8x16 = 2 个 8x8 图块，各 16 字节；
/// SFC 16x16 = 4 个图块）。这是真实 CHR 的组织方式——不是一整块。
/// 图块顺序：行优先（先横排，再往下）。
pub fn to_chr(t : Frame) -> Array[Int] {
  let out : Array[Int] = []
  let tiles_across = (t.w + 7) / 8
  let tiles_down = (t.h + 7) / 8
  let mut ty = 0
  while ty < tiles_down {
    let mut tx = 0
    while tx < tiles_across {
      // 平面 0：下标低位（下标 1 / 3）
      let mut y = 0
      while y < 8 {
        let mut bits = 0
        let mut x = 0
        while x < 8 {
          let sy = ty * 8 + y
          let sx = tx * 8 + x
          if sy < t.h && sx < t.w {
            if (px_at(t, sx, sy) & 1) == 1 {
              bits = bits | (1 << x)
            }
          }
          x = x + 1
        }
        out.push(bits)
        y = y + 1
      }
      // 平面 1：下标高位（下标 2 / 3）
      let mut y2 = 0
      while y2 < 8 {
        let mut bits = 0
        let mut x = 0
        while x < 8 {
          let sy = ty * 8 + y2
          let sx = tx * 8 + x
          if sy < t.h && sx < t.w {
            if ((px_at(t, sx, sy) >> 1) & 1) == 1 {
              bits = bits | (1 << x)
            }
          }
          x = x + 1
        }
        out.push(bits)
        y2 = y2 + 1
      }
      tx = tx + 1
    }
    ty = ty + 1
  }
  out
}

///|
/// CHR 字节流 → 帧（2bpp planar 解码，按图块序列读回）
///
/// 这是"资源识别"的逆操作：喂进 CHR 字节，读回像素。
/// 与 to_chr 严格互逆——这是可机械核对的不变量。
pub fn from_chr(bytes : Array[Int], w : Int, h : Int) -> Frame {
  let f = new_frame(w, h, 0)
  let tiles_across = (w + 7) / 8
  let tiles_down = (h + 7) / 8
  let mut ty = 0
  while ty < tiles_down {
    let mut tx = 0
    while tx < tiles_across {
      let base = (ty * tiles_across + tx) * 16 // 每图块 16 字节，行优先
      let mut y = 0
      while y < 8 {
        let sy = ty * 8 + y
        let lo = if base + y < bytes.length() { bytes[base + y] } else { 0 }
        let hi = if base + 8 + y < bytes.length() { bytes[base + 8 + y] } else { 0 }
        if sy < h {
          let mut x = 0
          while x < 8 {
            let sx = tx * 8 + x
            if sx < w {
              let l = (lo >> x) & 1
              let hbit = (hi >> x) & 1
              f.pix[sy * w + sx] = l | (hbit << 1)
            }
            x = x + 1
          }
        }
        y = y + 1
      }
      tx = tx + 1
    }
    ty = ty + 1
  }
  f
}

// ---------------- 造型：受约束的角色生成 ----------------

///|
/// 角色造型参数（全部是"美术决策"而非"随机数"——同 seed 必同结果）
///
/// 配色槽对应 FC 精灵的 3 个实体色（index0 透明）：
///   1 = cap   帽子（Nintendo/Mario 式的关键识别特征——帽子是 FC 人物的"签名"）
///   2 = skin  脸/手（皮肤色）
///   3 = cloth 衣服 + 裤 + 鞋（共用一色：FC 只有 3 色，硬要分衣服裤子就得放弃脸）
///
/// 为什么只有 3 色：FC 精灵调色板 4 项、index0 恒透明 → 有效 3 色。
/// 真实 FC 人物正是这样用色的：帽子/皮肤/衣服，描边靠透明像素。
pub(all) struct HeroSpec {
  cap : (Int, Int, Int) // 帽子色（也用作头发）
  skin : (Int, Int, Int) // 皮肤色
  cloth : (Int, Int, Int) // 衣服/裤/鞋
  mut pose : String // idle | walk1 | walk2 | jump | fall | duck
}

///|
/// 按姿态派生一份 spec
pub fn spec_with_pose(base : HeroSpec, pose : String) -> HeroSpec {
  { cap: base.cap, skin: base.skin, cloth: base.cloth, pose: pose }
}

///|
/// 经典配色（FC 时代最有辨识度的几组）
///
/// 命名用"看得见的特征"而不是通用词——blueprint §6.3「name it, do not
/// hand-describe it」：具名 IP 点名，原创角色才手工描述。
pub fn preset_by_name(name : String) -> HeroSpec {
  let (cap, skin, cloth) = match name {
    "plumber" => ((166, 39, 33), (255, 224, 178), (11, 83, 215))
    "green_cap" => ((12, 133, 0), (255, 224, 178), (11, 83, 215))
    "tan_hero" => ((134, 67, 0), (255, 224, 178), (45, 122, 0))
    "ninja" => ((0, 0, 0), (255, 224, 178), (88, 88, 88))
    "ice" => ((181, 217, 254), (255, 224, 178), (128, 132, 254))
    "fire" => ((225, 147, 33), (255, 224, 178), (166, 39, 33))
    _ => ((11, 83, 215), (255, 224, 178), (0, 127, 42))
  }
  { cap: cap, skin: skin, cloth: cloth, pose: "idle" }
}

///|
/// 按造型参数生成一帧 FC 人物精灵（8×16）
///
/// 布局（真 FC 人物的构造，Mario 式）：
///
///   y=0   . . . . . . . .   帽顶留 1px 透明
///   y=1-2 C C C C C C C .   帽子（signature）
///   y=3   C C C C C C C C   帽檐 + 脸开始
///   y=4   . S S S S S S .   脸
///   y=5   . S E E S S S .   眼（accent = 帽色，1-2px）
///   y=6   . S S S S S S .   脸 / 胡子
///   y=7   . L L L L L L .   肩（衣服）
///   y=8-10 L L L L L L L   躯干
///   y=11  . . L L L . . .   手 + 胯
///   y=12-14. L L L L L L   双腿
///   y=15  . . B B B B .   鞋（最重的一行，读得出"站住了"）
///
/// 造型纪律：
///   - 绝不引入第 4 色（帽/脸/衣 3 槽）
///   - 轮廓靠透明像素，不靠黑色描边（黑色也是 1 个色位）
///   - 姿态差异体现在**行的占用**（idle 立直、duck 压扁、jump 收腿）
pub fn hero_frame(spec : HeroSpec, w : Int, h : Int) -> Frame {
  let cap = 1
  let skin = 2
  let cloth = 3
  let f = new_frame(w, h, 0) // 0 = 透明
  let pose = spec.pose

  if w >= 8 && h >= 16 {
    hero_frame_standing(f, pose, cap, skin, cloth)
    f
  } else if w >= 8 && h >= 8 {
    hero_frame_8x8(f, pose, cap, skin, cloth)
    f
  } else {
    // 非 FC 尺寸：退化成一个色块，至少不是空图
    fill_rect(f, 0, 0, w, h, cloth)
    f
  }
}

///|
/// 8×16 人物（FC 标准人物精灵尺寸）
///
/// 行规划（站立，行号写死——8×16 只有 16 行，规划比算法可靠）：
///
///   y=0   ········   留空
///   y=1   .111111.   帽顶
///   y=2   .1111111   帽檐（向右伸出 = 朝向）
///   y=3   ..22211.   脸 + 鬓角
///   y=4   ..22222.   脸
///   y=5   ..22333.   眼（帽色）+ 胡子（衣色）
///   y=6   .333333.   肩
///   y=7-9 .333333.   躯干
///   y=10-13 ..33.33. 胯 → 双腿（中间 1px 透明 = 腿缝）
///   y=14  .333.333   鞋面
///   y=15  .3333333   鞋底（最宽的一行 = "站住了"）
///
/// 造型纪律：
///   - 绝不引入第 4 色（帽 / 脸 / 衣 三槽），眼和胡子借用另两色
///   - 轮廓靠透明像素，不靠黑色描边（黑色也是 1 个色位）
///   - 姿态差异只动**下半身与手臂**，上半身（帽子+脸）逐帧不变——
///     这是 FC 人物动画的通用做法：头部稳定，身体做动作
fn hero_frame_standing(f : Frame, pose : String, cap : Pix, skin : Pix, cloth : Pix) -> Unit {
  let b = body_box(f.w)
  let x0 = b.x
  let wide = b.w
  let x1 = b.x + b.w - 1 // 右边界（含）
  let mid = b.x + b.w / 2 // 身体中线
  // 腿宽：身体均分两半，中间留 1px 缝（缝就是腿缝）
  let leg_w = (b.w - 1) / 2
  let leg_l = b.x // 左腿左边界
  let leg_r = b.x + b.w - leg_w // 右腿左边界
  // duck 唯一例外：上半身整体下移 4 行（压扁的核心）
  let d = if pose == "duck" { 4 } else { 0 }
  // ---- 上半身（头部稳定是 FC 动画的基本手法）----
  hero_torso(f, x0, x1, wide, 1 + d, cap, skin, cloth, true)
  // ---- 下半身：按姿态分支（横向坐标全部由 BodyBox 推导）----
  match pose {
    "duck" => {
      fill_rect(f, x0, 10, wide, 5, cloth) // 加厚的躯干
      fill_rect(f, leg_l, 14, leg_w, 1, cloth) // 腿只剩 1 行
      fill_rect(f, leg_r, 14, leg_w, 1, cloth)
      hline(f, x0, 15, wide, cloth) // 鞋底踩满
    }
    "jump" => {
      // 收腿起跳：手臂上举但**接在躯干上**（悬空的手臂会读成"散架"）
      set_px(f, x0, 10, skin)
      set_px(f, x1, 10, skin)
      set_px(f, x0, 11, skin)
      set_px(f, x1, 11, skin)
      fill_rect(f, mid, 12, wide / 2, 2, cloth) // 蜷起的腿（并拢）
      hline(f, x0 + 1, 14, wide, cloth) // 并拢的鞋
    }
    "fall" => {
      // 张臂下落：手臂外张下压，同样贴躯干
      set_px(f, x0, 10, skin)
      set_px(f, x1, 10, skin)
      set_px(f, x0 - 1, 11, skin) // 下端外张
      set_px(f, x1 + 1, 11, skin)
      fill_rect(f, leg_l, 12, leg_w, 2, cloth) // 两腿分开
      fill_rect(f, leg_r, 12, leg_w, 2, cloth)
      hline(f, x0 - 1, 14, leg_w, cloth) // 鞋外张
      hline(f, x1 - leg_w + 2, 14, leg_w, cloth)
    }
    "walk1" => {
      // 走路 A：右脚在前踩实（宽鞋），左脚在后抬脚跟（窄鞋）
      //   腿   y=10..12: 后脚（窄）
      //        y=13:     前脚（宽，落地）
      //   鞋面 y=14: 后脚 x=[leg_l-1, leg_l-1+leg_w) ；前脚 x=[leg_r, leg_r+leg_w+1)
      //   鞋底 y=15: 同上（后脚略短 → 离地感）
      fill_rect(f, leg_l, 10, leg_w, 3, cloth)
      fill_rect(f, leg_r, 10, leg_w, 4, cloth)
      hline(f, leg_l - 1, 14, leg_w, cloth) // 后脚鞋面
      hline(f, leg_r, 14, leg_w + 1, cloth) // 前脚鞋面
      hline(f, leg_l - 1, 15, leg_w, cloth) // 后脚鞋底（离地感）
      hline(f, leg_r, 15, leg_w + 1, cloth) // 前脚鞋底（踩实）
    }
    "walk2" => {
      // 走路 B：walk1 的**精确左右镜像**（整段镜像 x → w-1-x）。
      // mx(l, n) 把区间 [l, l+n-1] 镜像到 [w-n-l, w-1-l]，
      // 宽度 n 保持不变——这是镜像的关键（只翻位置，不翻宽度）。
      let mx = fn(l : Int, n : Int) -> Int {
        f.w - 1 - l - (n - 1)
      }
      fill_rect(f, mx(leg_l, leg_w), 10, leg_w, 3, cloth) // 后脚（窄）
      fill_rect(f, mx(leg_r, leg_w), 10, leg_w, 4, cloth) // 前脚（宽）
      hline(f, mx(leg_l - 1, leg_w), 14, leg_w, cloth) // 后鞋在右
      hline(f, mx(leg_r, leg_w + 1), 14, leg_w + 1, cloth) // 前鞋在左
      hline(f, mx(leg_l - 1, leg_w), 15, leg_w, cloth) // 后鞋底在右
      hline(f, mx(leg_r, leg_w + 1), 15, leg_w + 1, cloth) // 前鞋底在左
    }
    _ => {
      // idle：站立，双腿等长，双鞋对称
      fill_rect(f, leg_l, 10, leg_w, 4, cloth)
      fill_rect(f, leg_r, 10, leg_w, 4, cloth)
      hline(f, leg_l - 1, 14, leg_w, cloth)
      hline(f, leg_r, 14, leg_w, cloth)
      hline(f, x0, 15, wide, cloth) // 鞋底踩满
    }
  }
}

///|
/// 人物的身体框：把"人在帧里占哪块"从坐标里抽出来。
///
/// 为什么必须抽：早先的 8x16 造型把所有下半身坐标写成绝对值
/// （`fill_rect(f, 3, 12, ...)` / `hline(f, 1, 14, 7, ...)`），
/// 于是 SFC 的 16x16 帧里人物只占左侧 8px、右半全空——
/// **SFC 支持名义上存在，实际上走了退化分支**。
///
/// 抽成框之后，所有坐标按框推导，8 宽（FC）与 16 宽（SFC）共用同一套造型逻辑。
pub(all) struct BodyBox {
  x : Int // 左边界
  w : Int // 身体宽度（不含左右留白）
}

///|
/// 按帧宽推导身体框。
///
/// 留白规则：左右各留 1px 透明做轮廓。人物宽度 = 帧宽 - 2，
/// 所以 FC 的 8 宽 → 6px 身体，SFC 的 16 宽 → 14px 身体。
fn body_box(fw : Int) -> BodyBox {
  let bw = fw - 2 // 左右各 1px 留白
  { x: 1, w: bw }
}

///|
/// 人物上半身（帽 + 脸 + 躯干），所有姿态共用，只允许整体上下移。
///
/// 行规划（头顶 y=top）：
///   y=top    帽顶     cap   x0..x1
///   y=top+1  帽檐     cap   x0..x1+1（向右伸出 = 朝向）
///   y=top+2  脸       skin  内缩 1px（两侧留鬓角）
///   y=top+3  眼       cap   2px（眼在脸上半部，靠右 = 朝向）
///   y=top+4  胡子/嘴  cloth 3px（在下巴，不是脸颊）
///   y=top+5  肩       cloth
///   y=top+6..8 躯干   cloth
///
/// 所有横向量按 `wide` 推导——FC（6px 身体）与 SFC（14px 身体）共用。
fn hero_torso(
  f : Frame,
  x0 : Int,
  x1 : Int,
  wide : Int,
  top : Int,
  cap : Pix,
  skin : Pix,
  cloth : Pix,
  with_body : Bool
) -> Unit {
  let face_x = x0 + 1 // 脸内缩 1px
  let face_w = wide - 2 // 脸比身体窄 2px（左右各留鬓角）
  hline(f, x0, top, wide, cap) // 帽顶
  hline(f, x0, top + 1, wide, cap) // 帽檐
  set_px(f, x1 + 1, top + 1, cap) // 帽檐向右伸出 = 朝向
  fill_rect(f, face_x, top + 2, face_w, 2, skin) // 脸（2 行）
  set_px(f, face_x, top + 2, cap) // 左鬓角（帽色）
  set_px(f, x1 - 1, top + 2, cap) // 眼（帽色，1px，靠右）
  hline(f, x1 - 2, top + 4, 3, cloth) // 胡子/嘴（衣色，在下巴）
  if with_body {
    fill_rect(f, x0, top + 5, wide, 4, cloth) // 躯干 y=top+5..8
  }
}

///|
/// 8×8 人物（FC 小精灵尺寸——只能用最少的笔画）
fn hero_frame_8x8(f : Frame, pose : String, cap : Pix, skin : Pix, cloth : Pix) -> Unit {
  // 8x8 放不下帽子+脸+衣服，只能取"帽子 + 脸"两行结构
  let top = if pose == "duck" { 2 } else { 0 }
  hline(f, 1, top, 6, cap) // 帽子
  hline(f, 1, top + 1, 6, cap) // 帽檐
  fill_rect(f, 1, top + 2, 6, 2, skin) // 脸
  set_px(f, 5, top + 2, cap) // 眼
  fill_rect(f, 1, top + 4, 6, 4, cloth) // 躯干
  if pose == "walk1" {
    set_px(f, 6, 7, cap) // 错步
  }
}

///|
/// 生成完整 clip（多姿态帧 + 共享调色板）。
///
/// 同参数必同结果（无随机——形态由 pose 名与配色决定）。
pub fn hero_clip(name : String, spec : HeroSpec, retro : Retro, poses : Array[String]) -> Clip {
  let (w, h) = match retro {
    FC => (8, 16)
    SFC => (16, 16)
  }
  let frames : Array[Frame] = []
  let mut i = 0
  while i < poses.length() {
    frames.push(hero_frame(spec_with_pose(spec, poses[i]), w, h))
    i = i + 1
  }
  let pal = fc_sprite_palette(spec.cap, spec.skin, spec.cloth)
  let errors : Array[String] = []
  let warnings : Array[String] = []
  // 契约自检：用色数 / 图块占用
  let budget = sprite_colors(retro)
  let used = distinct_indices(frames)
  if used > budget {
    errors.push("hero_clip '\{name}': 用色 \{used} 超出 \{retro_name(retro)} 精灵预算 \{budget}")
  }
  if poses.length() == 0 {
    errors.push("hero_clip '\{name}': 没有姿态帧")
  }
  { name: name, frames: frames, palette: pal, retro: retro, errors: errors, warnings: warnings }
}

///|
/// 一组帧里用到的不同调色板下标数（不含 0=透明）
pub fn distinct_indices(frames : Array[Frame]) -> Int {
  let used : Array[Pix] = []
  for f in frames {
    for p in f.pix {
      if p != 0 {
        let mut seen = false
        for u in used {
          if u == p {
            seen = true
            break
          }
        }
        if !seen {
          used.push(p)
        }
      }
    }
  }
  used.length()
}

///|
/// 帧 → 展平 RGB（用 clip 调色板上色；下标0=透明用洋红标记便于肉眼识别）
///
/// 这是"识别"的输入端：生成器产出 → 展平像素 → census/quantize 检验。
pub fn frame_to_rgb(f : Frame, pal : Array[(Int, Int, Int)]) -> Array[Int] {
  let out : Array[Int] = []
  for p in f.pix {
    if p == 0 {
      out.push(255)
      out.push(0)
      out.push(255) // 洋红 = 透明标记
    } else {
      let idx = p - 1
      if idx < pal.length() {
        out.push(pal[idx].0)
        out.push(pal[idx].1)
        out.push(pal[idx].2)
      } else {
        out.push(0)
        out.push(0)
        out.push(0)
      }
    }
  }
  out
}

///|
/// 剔除透明像素后的展平 RGB（识别用）
///
/// **透明标记必须在普查前剔除**：洋红不是"第 4 种颜色"，而是"没有颜色"。
/// 直接把 frame_to_rgb 喂给 census 会让 FC 精灵误报成 4 色超预算——
/// 这是识别能力最容易犯的错，也是本函数存在的理由。
pub fn frame_to_rgb_opaque(f : Frame, pal : Array[(Int, Int, Int)]) -> Array[Int] {
  let out : Array[Int] = []
  for p in f.pix {
    if p != 0 {
      let idx = p - 1
      if idx < pal.length() {
        out.push(pal[idx].0)
        out.push(pal[idx].1)
        out.push(pal[idx].2)
      } else {
        out.push(0)
        out.push(0)
        out.push(0)
      }
    }
  }
  out
}

///|
/// 帧的透明像素数（FC 美术的轮廓预算：透明太多 = 精灵读不出形）
pub fn transparent_count(f : Frame) -> Int {
  let mut n = 0
  for p in f.pix {
    if p == 0 {
      n = n + 1
    }
  }
  n
}

///|
/// clip 契约报告（文本工件：agent 直接读，判断资源是否合规）
pub fn clip_report(c : Clip) -> String {
  let (rw, rh) = match c.retro {
    FC => (8, 16)
    SFC => (16, 16)
  }
  let budget = sprite_colors(c.retro)
  let used = distinct_indices(c.frames)
  let tiles_each = tiles_per_sprite(rw, rh)
  let mut s = "clip: \{c.name}  retro:\{retro_name(c.retro)}  frames:\{c.frames.length()}\n"
  s = s + "  size: \{rw}x\{rh}  tiles/frame: \{tiles_each}  total tiles: \{tiles_each * c.frames.length()}\n"
  s = s + "  palette: \{c.palette.length()} colors (idx0=transparent)\n"
  s = s + "  colors used: \{used} / budget \{budget}  \{if used <= budget { "OK" } else { "OVER" }}\n"
  s = s + "  sprite budget: \{sprites_per_scanline(c.retro)}/scanline\n"
  for e in c.errors {
    s = s + "  ERROR: \{e}\n"
  }
  for w in c.warnings {
    s = s + "  WARN: \{w}\n"
  }
  s
}