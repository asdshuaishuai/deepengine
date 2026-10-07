// bridge —— FFI 声明（blueprint B 层）。
//
// 纪律：只声明，不实现——stub.c 随 app 包编译链接（C 符号在最终链接时解析）。
// 字符串参数一律 #borrow（MoonBit String 是 UTF-16，stub 内转 UTF-8）。

///|
// raylib 键码（KeyboardKey 枚举值）
pub const KEY_ESCAPE : Int = 256

///|
pub const KEY_SPACE : Int = 32

///|
pub const KEY_LEFT : Int = 263

///|
pub const KEY_RIGHT : Int = 262

///|
pub const KEY_R : Int = 82

///|
pub const KEY_UP : Int = 265

///|
pub const KEY_DOWN : Int = 264

///|
#borrow(title)
pub extern "c" fn mbg_init(title : String, w : Int, h : Int, hidden : Int) = "mbg_init"

pub extern "c" fn mbg_close() = "mbg_close"
pub extern "c" fn mbg_should_close() -> Int = "mbg_should_close"
pub extern "c" fn mbg_begin_frame() = "mbg_begin_frame"
pub extern "c" fn mbg_end_frame() = "mbg_end_frame"
pub extern "c" fn mbg_clear(r : Int, g : Int, b : Int) = "mbg_clear"
pub extern "c" fn mbg_rect(
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  r : Int,
  g : Int,
  b : Int
) = "mbg_rect"
pub extern "c" fn mbg_circle(
  cx : Double,
  cy : Double,
  radius : Double,
  r : Int,
  g : Int,
  b : Int
) = "mbg_circle"

///|
#borrow(text)
pub extern "c" fn mbg_text(
  text : String,
  x : Double,
  y : Double,
  size : Double,
  r : Int,
  g : Int,
  b : Int
) -> Double = "mbg_text"
pub extern "c" fn mbg_key_down(key : Int) -> Int = "mbg_key_down"
pub extern "c" fn mbg_set_fps(n : Int) = "mbg_set_fps"

///|
#borrow(path)
pub extern "c" fn mbg_screenshot(path : String) = "mbg_screenshot"

///|
#borrow(path)
pub extern "c" fn mbg_read_file(path : String) -> String = "mbg_read_file"

///|
#borrow(path)
pub extern "c" fn mbg_file_exists(path : String) -> Int = "mbg_file_exists"
pub extern "c" fn exit(code : Int) -> Unit = "exit"
pub extern "c" fn mbg_audio_init() = "mbg_audio_init"

///|
#borrow(name)
pub extern "c" fn mbg_sfx(name : String) = "mbg_sfx"

///|
/// 警告输出通道：走 stderr，保证 stdout 的 JSON 协议纯净
#borrow(msg)
pub extern "c" fn mbg_warn(msg : String) = "mbg_warn"
