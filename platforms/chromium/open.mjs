#!/usr/bin/env node
// Plain-browser floor: serve a built web dir the way WebUI hosts do (no
// COOP/COEP, no special headers), open it in headless Chromium, and print one
// JSON observation: console, page errors, timings, an optional eval result.
//
//   node open.mjs <dir|url> [--mobile] [--wait-ms N] [--eval 'js expr']
//                 [--screenshot out.png] [--headers coop]
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { execSync } from 'node:child_process';
import path from 'node:path';

const require = createRequire(import.meta.url);
let pw;
try { pw = require('playwright'); } catch {
  pw = require(path.join(execSync('npm root -g').toString().trim(), 'playwright'));
}

const args = process.argv.slice(2);
const flag = (n) => args.includes(n);
const opt = (n, d) => (args.includes(n) ? args[args.indexOf(n) + 1] : d);
const target = args[0];
if (!target) { console.error('usage: open.mjs <dir|url> [...]'); process.exit(2); }

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.wasm': 'application/wasm', '.json': 'application/json', '.css': 'text/css',
  '.png': 'image/png', '.svg': 'image/svg+xml', '.ttf': 'font/ttf', '.otf': 'font/otf' };

let url = target, server;
if (!/^https?:/.test(target)) {
  const root = path.resolve(target);
  const extra = opt('--headers') === 'coop'
    ? { 'Cross-Origin-Opener-Policy': 'same-origin', 'Cross-Origin-Embedder-Policy': 'require-corp' } : {};
  server = createServer(async (req, res) => {
    let p = path.join(root, decodeURIComponent(new URL(req.url, 'http://x').pathname));
    if (!p.startsWith(root)) { res.writeHead(403).end(); return; }
    try { if ((await stat(p)).isDirectory()) p = path.join(p, 'index.html');
      res.writeHead(200, { 'Content-Type': MIME[path.extname(p)] ?? 'application/octet-stream', ...extra });
      res.end(await readFile(p));
    } catch { res.writeHead(404).end(); }
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  url = `http://127.0.0.1:${server.address().port}/`;
}

const browser = await pw.chromium.launch();
const ctx = await browser.newContext({
  locale: 'en-US', // Flutter web throws "Incorrect locale" headless without it
  ...(flag('--mobile') ? { viewport: { width: 412, height: 915 }, deviceScaleFactor: 2.625, isMobile: true, hasTouch: true } : {}),
});
const page = await ctx.newPage();
const consoleLines = [], errors = [];
page.on('console', (m) => consoleLines.push(`${m.type()}: ${m.text()}`));
page.on('pageerror', (e) => errors.push(String(e)));
const t0 = Date.now();
await page.goto(url, { waitUntil: 'load' });
const loadMs = Date.now() - t0;
await page.waitForTimeout(Number(opt('--wait-ms', 3000)));
const out = {
  platform: 'chromium-headless', browser: browser.version(), date: new Date().toISOString().slice(0, 10),
  url, loadMs, crossOriginIsolated: await page.evaluate(() => self.crossOriginIsolated),
  console: consoleLines, errors,
};
if (opt('--eval')) {
  try { out.eval = await page.evaluate(opt('--eval')); } catch (e) { out.eval = { error: String(e) }; }
}
if (opt('--screenshot')) await page.screenshot({ path: opt('--screenshot') });
console.log(JSON.stringify(out, null, 1));
await browser.close();
server?.close();
