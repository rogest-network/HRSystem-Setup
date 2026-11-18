// Logic test for qa-stub.js in a minimal fake window (node test-stub.mjs).
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
import assert from 'node:assert/strict'

const SUPA = 'https://pqgjbnzzzcgsehhglcrs.supabase.co'
const code = readFileSync(new URL('./qa-stub.js', import.meta.url), 'utf8')

function makeWindow(search = '') {
  const store = new Map()
  const localStorage = { getItem: (k) => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, String(v)), removeItem: (k) => store.delete(k) }
  let realCalls = 0
  const win = {
    location: { href: 'http://localhost:4391/portal' + search, search, pathname: '/portal', hash: '' },
    history: { state: null, replaceState() {} },
    localStorage, navigator: {}, console: { info() {}, warn() {}, error: console.error, log: console.log },
    fetch: async () => { realCalls++; return new Response('real') },
    XMLHttpRequest: function () {}, WebSocket: function () { throw new Error('real WS used') },
    URL, URLSearchParams, Request, Response, Headers, Blob, EventTarget, Event, btoa, atob, crypto, setTimeout, escape, unescape, encodeURIComponent, decodeURIComponent, Promise, JSON, Math, Date, Object, Array, String, Number, Set, Map, RegExp, Error
  }
  win.XMLHttpRequest.prototype.open = function () {}
  win.window = win
  win.localStorage.setItem('qa_delay', '0')
  vm.createContext(win)
  vm.runInContext(code, win)
  return { win, realCalls: () => realCalls }
}

const auth = (win) => { const s = JSON.parse(win.localStorage.getItem('hrsystem_session')); return { apikey: 'x', Authorization: `Bearer ${s.access_token}`, 'Content-Type': 'application/json' } }
const get = async (win, path) => { const r = await win.fetch(`${SUPA}${path}`, { headers: auth(win) }); return [r.status, await r.json()] }

// client mode
{
  const { win, realCalls } = makeWindow('?qa=client')
  const s = JSON.parse(win.localStorage.getItem('hrsystem_session'))
  const payload = JSON.parse(Buffer.from(s.access_token.split('.')[1], 'base64url').toString())
  assert.equal(payload.sub, win.__qa.ids.client); assert.ok(payload.exp > Date.now() / 1000 + 86400 * 365)
  assert.equal(s.user.id, win.__qa.ids.client)
  let [st, rows] = await get(win, `/rest/v1/profiles?id=eq.${encodeURIComponent(win.__qa.ids.client)}&select=*`)
  assert.equal(st, 200); assert.equal(rows.length, 1); assert.equal(rows[0].full_name, 'Arben Krasniqi'); assert.equal(rows[0].status, 'active')
  const cid = rows[0].company_id;
  [st, rows] = await get(win, `/rest/v1/systems?company_id=eq.${cid}&select=*&order=created_at.desc&limit=1`)
  assert.equal(rows.length, 1); assert.equal(rows[0].company_id, cid);
  [st, rows] = await get(win, `/rest/v1/companies?id=eq.${cid}&select=*`); assert.equal(rows[0].name, 'Regina Center SHPK');
  [st, rows] = await get(win, `/rest/v1/support_messages?select=id&is_read=eq.false&sender_role=eq.admin`); assert.equal(rows.length, 1); assert.deepEqual(Object.keys(rows[0]), ['id']);
  [st, rows] = await get(win, `/rest/v1/company_updates?company_id=eq.${cid}&is_published=eq.true&select=*&order=published_at.desc`); assert.equal(rows.length, 4); assert.ok(rows[0].published_at > rows[1].published_at);
  [st, rows] = await get(win, `/rest/v1/billing_items?company_id=eq.${cid}&select=*&order=created_at.asc`); assert.equal(rows.length, 4);
  [st, rows] = await get(win, `/rest/v1/profiles?select=*`); assert.equal(rows.length, 1, 'client sees only own profile');
  // POST message + RPC + function
  let r = await win.fetch(`${SUPA}/rest/v1/support_messages`, { method: 'POST', headers: { ...auth(win), Prefer: 'return=minimal' }, body: JSON.stringify({ conversation_id: 'f0000000-0000-4000-a000-000000000001', sender_id: win.__qa.ids.client, message: 'test' }) })
  assert.equal(r.status, 201); assert.equal(await r.text(), '')
  r = await win.fetch(`${SUPA}/rest/v1/rpc/mark_conversation_read`, { method: 'POST', headers: auth(win), body: JSON.stringify({ conv: 'f0000000-0000-4000-a000-000000000001' }) }); assert.equal(await r.json(), 1)
  r = await win.fetch(`${SUPA}/functions/v1/client-account`, { method: 'POST', headers: auth(win), body: '{"action":"update_self","phone":"+383 44 000 000"}' }); assert.equal((await r.json()).ok, true)
  r = await win.fetch(`${SUPA}/auth/v1/token?grant_type=refresh_token`, { method: 'POST', body: JSON.stringify({ refresh_token: s.refresh_token }) }); assert.equal((await r.json()).user.id, win.__qa.ids.client)
  r = await win.fetch(`${SUPA}/storage/v1/object/authenticated/hrsystem-backups/x.zip`, { headers: auth(win) }); assert.equal(r.status, 200)
  // non-Supabase passes through, Supabase never does
  await win.fetch('https://cdn.example.com/x.js'); assert.equal(realCalls(), 1)
  const ws = new win.WebSocket('wss://pqgjbnzzzcgsehhglcrs.supabase.co/realtime/v1/websocket?apikey=x'); assert.equal(ws.readyState, 0)
  console.log('client mode OK')
}
// admin mode
{
  const { win } = makeWindow('?qa=admin')
  assert.equal(win.localStorage.getItem('hrsystem_role'), 'admin')
  const counts = {}
  for (const [t, q] of [['profiles', 'select=*&order=created_at.desc'], ['companies', 'select=*&order=created_at.desc'], ['systems', 'select=*&order=created_at.desc'], ['lead_submissions', 'select=*&order=created_at.desc'], ['company_updates', 'select=*&order=published_at.desc'], ['support_conversations', 'select=*&order=last_message_at.desc.nullslast'], ['system_versions', 'select=*&order=created_at.desc'], ['admin_audit_log', 'select=*&order=created_at.desc&limit=100'], ['billing_items', 'select=*&order=created_at.asc'], ['billing_payments', 'select=*&order=paid_on.desc,created_at.desc'], ['support_messages', 'select=conversation_id&is_read=eq.false&sender_role=eq.client']]) {
    const [st, rows] = await get(win, `/rest/v1/${t}?${q}`); assert.equal(st, 200); counts[t] = rows.length
  }
  assert.deepEqual(counts, { profiles: 9, companies: 4, systems: 4, lead_submissions: 6, company_updates: 7, support_conversations: 4, system_versions: 5, admin_audit_log: 12, billing_items: 9, billing_payments: 4, support_messages: 1 })
  const r = await win.fetch(`${SUPA}/functions/v1/admin-manage-client`, { method: 'POST', headers: auth(win), body: JSON.stringify({ action: 'activate_client', user_id: win.__qa.ids.pending, company_id: '', company_name: 'Market Dardania', system: { status: 'active', version: '1.0.8' } }) })
  assert.equal((await r.json()).ok, true)
  const [, p] = await get(win, `/rest/v1/profiles?id=eq.${win.__qa.ids.pending}&select=*`); assert.equal(p[0].status, 'active')
  console.log('admin mode OK', counts)
}
// pending mode
{
  const { win } = makeWindow('?qa=pending')
  const [, p] = await get(win, `/rest/v1/profiles?id=eq.${win.__qa.ids.pending}&select=*`); assert.equal(p[0].status, 'pending')
  const [, c] = await get(win, `/rest/v1/support_conversations?prospect_profile_id=eq.${win.__qa.ids.pending}&select=id&limit=1`); assert.equal(c.length, 1)
  console.log('pending mode OK')
}
