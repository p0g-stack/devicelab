#!/usr/bin/env node
// Evaluate JS in an Android WebView over Chrome DevTools, via adb.
//   node driver/webview.mjs list
//   node driver/webview.mjs eval '<expr>' [--match <url substring>]
// The expression may return a Promise; the resolved value is printed as JSON.
//   --preload '<js>' [--wait-ms N]: install <js> to run before page scripts,
//   reload, wait, then evaluate (e.g. to catch flutter-first-frame).
// Needs the app's WebView debugging on (setWebContentsDebuggingEnabled).
import { execFileSync } from 'node:child_process';

const adb = (...a) => execFileSync(process.env.ADB ?? 'adb', a, { encoding: 'utf8' });
const [cmd, expr] = process.argv.slice(2);
const opt = (n, d) => (process.argv.includes(n) ? process.argv[process.argv.indexOf(n) + 1] : d);
const match = opt('--match', '');

const sockets = [...adb('shell', 'cat', '/proc/net/unix').matchAll(/@(\S*devtools_remote\S*)/g)].map((m) => m[1]);
const targets = [];
for (const [i, s] of [...new Set(sockets)].entries()) {
  const port = 9300 + i;
  adb('forward', `tcp:${port}`, `localabstract:${s}`);
  try {
    const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
    for (const t of list) targets.push({ socket: s, port, ...t });
  } catch (e) { targets.push({ socket: s, port, error: String(e) }); }
}
if (cmd === 'list') { console.log(JSON.stringify(targets, null, 1)); process.exit(0); }

const t = targets.find((x) => x.type === 'page' && x.webSocketDebuggerUrl && (x.url ?? '').includes(match));
if (!t) { console.log(JSON.stringify({ error: 'no page target', sockets, targets })); process.exit(1); }
const ws = new WebSocket(t.webSocketDebuggerUrl.replace(/ws:\/\/[^/]+/, `ws://127.0.0.1:${t.port}`));
await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
let nextId = 1;
const pending = new Map();
ws.onmessage = (m) => { const d = JSON.parse(m.data); pending.get(d.id)?.(d); };
const call = (method, params = {}) => new Promise((r) => { const id = nextId++; pending.set(id, r); ws.send(JSON.stringify({ id, method, params })); });
if (opt('--preload')) {
  await call('Page.enable');
  await call('Page.addScriptToEvaluateOnNewDocument', { source: opt('--preload') });
  await call('Page.reload', { ignoreCache: true });
  await new Promise((r) => setTimeout(r, Number(opt('--wait-ms', 10000))));
}
const reply = await call('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true, timeout: 20000 });
ws.close();
const res = reply.result ?? {};
console.log(JSON.stringify({ url: t.url, socket: t.socket,
  value: res.result?.value, exception: res.exceptionDetails?.exception?.description ?? res.exceptionDetails?.text }));
