// scene —— .mbg.md 事实源解析（blueprint L1）。
//
// 约定与 demo/scene.mbg.md 一脉相承：markdown 里 ```mbg fence 内的 ops 被解析，
// prose 全部忽略——同一份文件既是文档又是程序。
//
// ops（gravity_side MVP 集）：
//   canvas <w> <h> [bg:#rrggbb]
//   physics gravity:<G> jump:<J> speed:<S>
//   player x:<x> y:<y> w:<w> h:<h> [color:#rrggbb]
//   platform x: y: w: h: [color:#rrggbb]
//   coin x: y: [w:] [color:]
//   spike x: y: w: [h:]
//   goal x: y: w: h:
//   probe <name> script:"..." expect:"..."
