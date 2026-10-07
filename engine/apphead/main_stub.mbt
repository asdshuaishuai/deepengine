// 非 native 目标的占位 main：本包（stub 链接的 native 可执行）只在 native 构建，
// wasm-gc 构建模块时由此占位满足 is-main 约束（moonviz cli 同款做法）。
fn main {
  ignore(0)
}
