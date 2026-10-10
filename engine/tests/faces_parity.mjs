// faces_parity.mjs —— 四面同源核对：CLI `trace` 与 wasm `web_trace` 的体验度量
// 必须**逐字段相同**（同一个 scene.run_experience，两条宿主路径）。
//
// 用法（由 tests/faces_parity.sh 调用）:
//   ELECTRON_RUN_AS_NODE=1 <electron> faces_parity.mjs <game-id> <native-trace.json>
//
// 为什么这条比"两边都能跑"更强：断言的是**数字相同**，不是"都没崩"。
// 若哪天有人给 wasm 面另写一份策略执行（两套评估路径），这条立刻红。
import { readFile } from 'node:fs/promises';

const [gameId, nativePath] = process.argv.slice(2);
if (!gameId || !nativePath) {
  console.log('FAIL: 用法 faces_parity.mjs <game-id> <native-trace.json>');
  process.exit(1);
}

const wasmBytes = await readFile(new URL('../_build/wasm-gc/debug/build/web/web.wasm', import.meta.url));
const module = new WebAssembly.Module(wasmBytes, { builtins: ['js-string'], importedStringConstants: '_' });
const w = new WebAssembly.Instance(module, {}).exports;

// 宿主注册内容源（wasm 面无文件 IO）：与 CLI 读的是同一批文件
const srcDir = new URL(`../../examples/${gameId}/`, import.meta.url);
const guide = await readFile(new URL('game.guide.md', srcDir), 'utf8');
const declared = [...guide.matchAll(/path\s+"([^"]+)"/g)].map((m) => m[1]);
if (declared.length === 0) {
  console.log('FAIL: 指引里没解析出任何 source path');
  process.exit(1);
}
for (const rel of declared) {
  w.web_put_source(rel, await readFile(new URL(rel, srcDir), 'utf8'));
}
const lr = JSON.parse(w.web_load_guide(guide));
if (!lr.ok) {
  console.log('FAIL: wasm 指引入口装配失败:', JSON.stringify(lr));
  process.exit(1);
}

const native = JSON.parse(await readFile(nativePath, 'utf8'));
const wasm = JSON.parse(w.web_trace());

const a = JSON.stringify(native.experience);
const b = JSON.stringify(wasm.experience);
if (a !== b) {
  console.log('FAIL: CLI 与 wasm 的体验度量不一致——四面同源被破坏');
  console.log('  CLI :', a);
  console.log('  wasm:', b);
  process.exit(1);
}
if (JSON.stringify(native.criteria) !== JSON.stringify(wasm.criteria)) {
  console.log('FAIL: 标准裁决结果不一致');
  console.log('  CLI :', JSON.stringify(native.criteria));
  console.log('  wasm:', JSON.stringify(wasm.criteria));
  process.exit(1);
}
console.log('OK:', a);
