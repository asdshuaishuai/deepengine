// wasm 面烟测：逻辑全链在 Node（Electron-as-node, V8 支持 js-string）验证。
// 用法: ELECTRON_RUN_AS_NODE=1 /Applications/ZCode.app/Contents/MacOS/ZCode smoke_web.mjs
import { readFile } from 'node:fs/promises';

const WASM = new URL('../_build/wasm-gc/debug/build/web/web.wasm', import.meta.url);
const bytes = await readFile(WASM);

const module = new WebAssembly.Module(bytes, {
  builtins: ['js-string'],
  importedStringConstants: '_',
});
const w = new WebAssembly.Instance(module, {}).exports;

console.log('[1] version_info:', w.version_info());

// ---- platformer（physics 族）----
const platformer = await readFile(new URL('../../examples/platformer/game.mbg.md', import.meta.url), 'utf8');
let r = JSON.parse(w.web_load(platformer));
console.log('[2] load platformer:', JSON.stringify(r));
if (!r.ok) process.exit(1);

// 步进 30 帧 hold right
let f = null;
for (let i = 0; i < 30; i++) f = JSON.parse(w.web_step(0, 1, 0));
console.log('[3] after 30f right: x =', f.player.x, 'state =', f.state, 'frame =', f.frame);
if (!(f.player.x > 80)) { console.log('FAIL: player 未移动'); process.exit(1); }

// 跑首个声明探针脚本路线（beat_the_game 的前半段验手感）
for (let i = 0; i < 60; i++) f = JSON.parse(w.web_step(0, 1, 0)); // 模拟 right:60（已走30）
console.log('[4] x after 90f total:', f.player.x);

// verify（内核层，不扰动对局）
const rep = JSON.parse(w.web_verify());
console.log('[5] verify platformer: reward =', rep.reward, `(${rep.passed}/${rep.total})`, 'evidence_basis:', rep.evidence_basis.length, '条');
if (rep.reward !== 1) { console.log('FAIL: reward != 1'); process.exit(1); }
// verify 后对局未受扰动
f = JSON.parse(w.web_frame());
console.log('[6] verify 后对局仍在: frame =', f.frame, 'x =', f.player.x);

// reset
r = JSON.parse(w.web_reset());
f = JSON.parse(w.web_frame());
console.log('[7] reset 后: frame =', f.frame, 'x =', f.player.x);
if (f.frame !== 0 || f.player.x !== 80) { console.log('FAIL: reset 未回到初始'); process.exit(1); }

// ---- boxpush（grid 族）----
const boxpush = await readFile(new URL('../../examples/boxpush/game.mbg.md', import.meta.url), 'utf8');
r = JSON.parse(w.web_load(boxpush));
console.log('[8] load boxpush:', JSON.stringify(r));
if (!r.ok || r.mode !== 'grid') process.exit(1);

// 新版双箱顺序谜题：跑完整 32 步解法（与 CLI beat_the_puzzle 探针同路线）
const route = "up:1, right:7, down:3, left:1, down:2, right:1, up:5, left:1, down:4, right:1, down:1, left:2, up:1, left:1, down:1";
for (const tok of route.split(",")) {
  const [dir, n] = tok.trim().split(":");
  for (let i = 0; i < parseInt(n, 10); i++) f = JSON.parse(w.web_grid_move(dir));
}
console.log('[9] 32 步解法: state =', f.state, 'boxes_on =', f.boxes_on, '/', f.boxes_total, 'moves =', f.moves);
if (f.state !== 'won') { console.log('FAIL: 应 won'); process.exit(1); }

const rep2 = JSON.parse(w.web_verify());
console.log('[10] verify boxpush: reward =', rep2.reward, `(${rep2.passed}/${rep2.total})`);
if (rep2.reward !== 1) process.exit(1);

// ---- 确定性：同一源两次 load+同脚本序列，帧状态一致 ----
w.web_load(platformer);
let a = '';
for (let i = 0; i < 45; i++) a = w.web_step(0, 1, i === 10 ? 1 : 0);
w.web_load(platformer);
let b = '';
for (let i = 0; i < 45; i++) b = w.web_step(0, 1, i === 10 ? 1 : 0);
console.log('[11] 确定性双跑一致:', a === b ? 'YES' : 'NO');
if (a !== b) process.exit(1);

// ---- 运行时衍生 API（v1.2）----
w.web_load(await readFile('../../examples/platformer/game.mbg.md', 'utf8'));
const sid = w.web_spawn_coin(300, 465, 20);
console.log('[12] spawn_coin id =', sid, '(应为 3——关卡原有 3 枚)');
if (sid !== 3) { console.log('FAIL'); process.exit(1); }
let sf = null;
for (let i = 0; i < 60; i++) sf = JSON.parse(w.web_step(0, 1, 0));
console.log('[13] 走过去收集衍生金币: coins =', sf.coins_taken, '/', sf.coins_total);
if (sf.coins_total !== 4 || sf.coins_taken < 1) { console.log('FAIL'); process.exit(1); }

w.web_load(await readFile('../../examples/boxpush/game.mbg.md', 'utf8'));
const br = w.web_grid_spawn_box(3, 1);
console.log('[14] grid spawn_box(3,1) =', br);
let bf = JSON.parse(w.web_frame());
console.log('[15] 衍生后 boxes =', bf.boxes_total, '(应为 3)');
if (br !== 1 || bf.boxes_total !== 3) { console.log('FAIL'); process.exit(1); }

console.log('\n✅ wasm 面烟测全部通过（physics/grid/verify/reset/determinism/spawn）');
