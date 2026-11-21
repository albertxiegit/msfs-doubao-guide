// 持久监听 stdin 命令：FOCUS / DOWN / UP，通过 CDP 后台操作豆包（完全后台）
// 同时轮询朗读状态，输出 SPEAK_START / SPEAK_END 供 PowerShell 控制底噪
import http from 'node:http';
import readline from 'node:readline';

function getPage() {
  return new Promise((resolve, reject) => {
    http.get('http://127.0.0.1:9222/json/list', res => {
      let d = ''; res.on('data', c => d += c); res.on('end', () => {
        resolve(JSON.parse(d).find(p => p.url.includes('doubao') && p.type === 'page'));
      });
    }).on('error', reject);
  });
}
const page = await getPage();
if (!page) { console.error('NO_PAGE'); process.exit(1); }
const ws = new WebSocket(page.webSocketDebuggerUrl);
let id = 0; const pending = new Map();
ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } };
await new Promise(r => ws.onopen = r);
function send(method, params = {}) { return new Promise(res => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); }); }
async function evalJs(expr) { const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true }); return r.result?.result?.value; }

const KEYDOWN = { type: 'keyDown', key: ' ', code: 'Space', windowsVirtualKeyCode: 32, nativeVirtualKeyCode: 32, text: ' ', unmodifiedText: ' ' };
const KEYUP = { type: 'keyUp', key: ' ', code: 'Space', windowsVirtualKeyCode: 32, nativeVirtualKeyCode: 32 };

const rl = readline.createInterface({ input: process.stdin });
rl.on('line', async line => {
  try {
    if (line === 'FOCUS') { await evalJs(`document.querySelector('[contenteditable=true]')?.focus()`); console.log('OK FOCUS'); }
    else if (line === 'DOWN') { await evalJs(`document.querySelector('[contenteditable=true]')?.focus()`); await send('Input.dispatchKeyEvent', KEYDOWN); console.log('OK DOWN'); }
    else if (line === 'UP') { await send('Input.dispatchKeyEvent', KEYUP); console.log('OK UP'); }
    else if (line === 'PING') { console.log('PONG'); }
  } catch (e) { console.log('ERR ' + e.message); }
});

// ---- 轮询朗读状态：写入状态文件供 PowerShell 主循环读取 ----
import { writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
const stateFile = join(dirname(fileURLToPath(import.meta.url)), 'speak-state.txt');
const SPEAK_EXPR = `(()=>[...document.querySelectorAll('[data-testid=audio_play_button]')].some(b=>b.getAttribute('aria-label')==='暂停朗读'))()`;
let speaking = false;
setInterval(async () => {
  try {
    const now = await evalJs(SPEAK_EXPR);
    if (now !== speaking) {
      speaking = now;
      writeFileSync(stateFile, now ? '1' : '0');
      console.log(now ? 'SPEAK_START' : 'SPEAK_END');
    }
  } catch {}
}, 250);
