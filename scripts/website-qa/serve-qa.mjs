// LOCAL QA server for the HRSystem website (never shipped, no dependencies).
// Serves the BUILT site (dist/) and injects /__qa/qa-stub.js into every HTML page, so the portal and the
// admin panel run on invented data and never reach the live Supabase project.
//   node serve-qa.mjs [distPath]        PORT env (default 4391)
//   open http://localhost:4391/portal?qa=client   or   http://localhost:4391/admin?qa=admin
import http from 'node:http'
import { readFile, stat } from 'node:fs/promises'
import { extname, join, normalize, resolve, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const root = resolve(process.argv[2] || 'C:/Users/Pc/Desktop/HRSystem/HRSystem Website/website/dist')
const stubFile = join(here, 'qa-stub.js')
const port = Number(process.env.PORT || 4391)
const mime = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.mjs': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.webmanifest': 'application/manifest+json', '.txt': 'text/plain; charset=utf-8', '.xml': 'application/xml',
  '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.webp': 'image/webp', '.gif': 'image/gif', '.avif': 'image/avif',
  '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf', '.pdf': 'application/pdf', '.zip': 'application/zip', '.map': 'application/json'
}
const TAG = '<script src="/__qa/qa-stub.js"></script>'
const inject = (html) => /<head[^>]*>/i.test(html) ? html.replace(/<head[^>]*>/i, (m) => m + TAG) : TAG + html

async function isFile(p) { try { return (await stat(p)).isFile() } catch { return false } }
async function resolveFile(pathname) {
  const rel = decodeURIComponent(pathname).replace(/^\/+/, '')
  let file = normalize(join(root, rel || 'index.html'))
  if (!file.startsWith(normalize(root))) return null
  try { if ((await stat(file)).isDirectory()) file = join(file, 'index.html') } catch {}
  if (await isFile(file)) return file
  // SPA fallback (like serve.mjs / vercel.json): /en -> en/index.html, /demo... -> demo/index.html, else index.html
  if (/\.[a-z0-9]+$/i.test(pathname) && !pathname.endsWith('.html')) return undefined // a missing asset: real 404
  const p = pathname.replace(/\/$/, '')
  if (p === '/en' || p.startsWith('/en/')) return join(root, 'en', 'index.html')
  if (p === '/demo' || p.startsWith('/demo/')) return join(root, 'demo', 'index.html')
  return join(root, 'index.html')
}

http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`)
    if (url.pathname === '/__qa/qa-stub.js') {
      res.writeHead(200, { 'Content-Type': mime['.js'], 'Cache-Control': 'no-store' })
      res.end(await readFile(stubFile)); return
    }
    const file = await resolveFile(url.pathname)
    if (file === null) { res.writeHead(400, { 'Content-Type': 'text/plain' }); res.end('bad path'); return }
    if (file === undefined) { res.writeHead(404, { 'Content-Type': 'text/plain' }); res.end('not found'); return }
    const ext = extname(file).toLowerCase()
    let data = await readFile(file)
    if (ext === '.html') data = Buffer.from(inject(data.toString('utf8')), 'utf8')
    res.writeHead(200, { 'Content-Type': mime[ext] || 'application/octet-stream', 'Cache-Control': 'no-store' })
    res.end(req.method === 'HEAD' ? undefined : data)
  } catch (error) {
    res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' })
    res.end(String(error))
  }
}).listen(port, '127.0.0.1', () => console.log(`HRSystem QA (dist: ${root}) -> http://localhost:${port}  (stub: ${stubFile})`))
