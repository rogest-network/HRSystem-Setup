// Panel of the test space (C:\HRTest): lists the companies, shows whether each runs, opens it, starts/stops/updates it.
// Local only (127.0.0.1:3600); it never touches the real install. Started by `test-env.bat panel`.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';

const here = path.dirname(fileURLToPath(import.meta.url));
const registry = 'C:\\HRTest\\companies.json';
const PORT = 3600;
const script = path.join(here, 'test-env.ps1');

const companies = () => {
  try { return JSON.parse(fs.readFileSync(registry, 'utf8').replace(/^\uFEFF/, '')); } catch { return []; }
};
const version = (name) => {
  try { return fs.readFileSync(`C:\\HRTest\\${name}\\current.txt`, 'utf8').trim(); } catch { return '?'; }
};
const alive = (port) => new Promise((resolve) => {
  const req = http.get({ host: '127.0.0.1', port, path: '/api/health', timeout: 1500 }, (res) => {
    let body = '';
    res.on('data', (d) => { body += d; });
    res.on('end', () => resolve(/"ok":true/.test(body)));
  });
  req.on('error', () => resolve(false));
  req.on('timeout', () => { req.destroy(); resolve(false); });
});
const busy = new Map();
const run = (action, name) => {
  if (busy.has(name)) return;
  const child = spawn('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script, action, name], { windowsHide: true, stdio: 'ignore' });
  busy.set(name, action);
  child.on('exit', () => busy.delete(name));
};

const PAGE_FILE = path.join(here, 'test-env-panel.html');

http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  if (req.method === 'GET' && url.pathname === '/') { res.writeHead(200, { 'content-type': 'text/html; charset=utf-8' }); return res.end(fs.readFileSync(PAGE_FILE)); }
  if (req.method === 'GET' && url.pathname === '/api/list') {
    const list = await Promise.all(companies().map(async (c) => ({ name: c.name, port: c.port, version: version(c.name), up: await alive(c.port), busy: busy.get(c.name) || '' })));
    res.writeHead(200, { 'content-type': 'application/json' });
    return res.end(JSON.stringify(list));
  }
  const m = req.method === 'POST' && url.pathname.match(/^\/api\/(start|stop|update|seed)\/([a-z][a-z0-9]{1,15})$/);
  if (m && companies().some((c) => c.name === m[2])) { run(m[1], m[2]); res.writeHead(202); return res.end('{}'); }
  res.writeHead(404); res.end();
}).listen(PORT, '127.0.0.1', () => console.log(`Hapesira e testit: http://localhost:${PORT}`));
