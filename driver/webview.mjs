#!/usr/bin/env node
// Evaluate JS in an Android WebView over Chrome DevTools, via adb.
//   node driver/webview.mjs list
//   node driver/webview.mjs eval '<expr>' [--match <url substring>]
// The expression may return a Promise; the resolved value is printed as JSON.
// Needs the app's WebView debugging on (setWebContentsDebuggingEnabled).
import { execFileSync } from 'node:child_process';

const adb = (...a) => execFileSync(process.env.ADB ?? 'adb', a, { encoding: 'utf8' });
const [cmd, expr] = process.argv.slice(2);
const match = process.argv.includes('--match') ? process.argv[process.argv.indexOf('--match') + 1] : '';

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
ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate',
  params: { expression: expr, awaitPromise: true, returnByValue: true, timeout: 20000 } }));
const reply = await new Promise((r) => { ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id === 1) r(d); }; });
ws.close();
const res = reply.result ?? {};
console.log(JSON.stringify({ url: t.url, socket: t.socket,
  value: res.result?.value, exception: res.exceptionDetails?.exception?.description ?? res.exceptionDetails?.text }));
