/* HRSystem website — LOCAL QA stub (never shipped).
 * Loaded as a classic <script> BEFORE app.js by serve-qa.mjs.
 * - Every request to *.supabase.co / *.supabase.in is answered here from an in-memory, invented database.
 *   Nothing is ever sent to the live Supabase project (fetch, XHR, WebSocket and sendBeacon are all guarded).
 * - Modes: ?qa=client (default) | ?qa=admin | ?qa=pending | ?qa=out (signed out). Stored in localStorage.qa_mode.
 * - Debug handle: window.__qa ({ db, mode, setMode(m), reset(), log }).
 */
(function () {
  'use strict'

  const SUPA_URL = 'https://pqgjbnzzzcgsehhglcrs.supabase.co'
  const isSupaHost = (h) => /(^|\.)supabase\.(co|in)$/i.test(String(h || ''))
  const isSupaUrl = (u) => { try { return isSupaHost(new URL(String(u), location.href).hostname) } catch { return false } }

  // ---------- fixed QA user ids ----------
  const IDS = {
    admin: '00000000-0000-4000-a000-000000000001',
    client: '00000000-0000-4000-a000-000000000101', // Arben Krasniqi, Regina Center SHPK, active
    pending: '00000000-0000-4000-a000-000000000201' // Dren Kelmendi, pending registration
  }
  const MODES = ['client', 'admin', 'pending', 'out']

  // ---------- mode ----------
  let forced = false
  try {
    const q = new URLSearchParams(location.search).get('qa')
    if (q && MODES.includes(q)) { localStorage.setItem('qa_mode', q); forced = true }
  } catch {}
  let mode = 'client'
  try { const m = localStorage.getItem('qa_mode'); if (MODES.includes(m)) mode = m } catch {}

  // ---------- fake JWT + session ----------
  const b64url = (s) => btoa(unescape(encodeURIComponent(s))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
  const EXP = Math.floor(Date.now() / 1000) + 10 * 365 * 86400
  function makeToken(uid, email) {
    return `${b64url(JSON.stringify({ alg: 'none', typ: 'JWT' }))}.${b64url(JSON.stringify({ sub: uid, email, role: 'authenticated', aud: 'authenticated', exp: EXP, iat: Math.floor(Date.now() / 1000), qa: true }))}.qa-signature`
  }
  function tokenPayload(t) { try { return JSON.parse(decodeURIComponent(escape(atob(String(t).split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))))) } catch { return {} } }

  // ---------- dates relative to now ----------
  const NOW = Date.now()
  const ago = (days, hours = 0, mins = 0) => new Date(NOW - days * 864e5 - hours * 36e5 - mins * 6e4).toISOString()
  const pad = (n) => String(n).padStart(2, '0')
  const dayOff = (n) => { const d = new Date(NOW + n * 864e5); return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}` }
  const uuid = () => (crypto.randomUUID ? crypto.randomUUID() : 'qa-' + Math.random().toString(16).slice(2) + Date.now().toString(16))

  // ---------- invented data (no real people; emails @example.com) ----------
  const C = { regina: 'c0000000-0000-4000-a000-000000000001', urban: 'c0000000-0000-4000-a000-000000000002', teuta: 'c0000000-0000-4000-a000-000000000003', fresh: 'c0000000-0000-4000-a000-000000000004' }
  const S = { regina: 'd0000000-0000-4000-a000-000000000001', urban: 'd0000000-0000-4000-a000-000000000002', teuta: 'd0000000-0000-4000-a000-000000000003', fresh: 'd0000000-0000-4000-a000-000000000004' }
  const P = {
    admin: IDS.admin, arben: IDS.client, vjosa: '00000000-0000-4000-a000-000000000102', liridon: '00000000-0000-4000-a000-000000000103',
    teuta: '00000000-0000-4000-a000-000000000104', besnik: '00000000-0000-4000-a000-000000000105', mimoza: '00000000-0000-4000-a000-000000000106',
    dren: IDS.pending, elira: '00000000-0000-4000-a000-000000000202'
  }
  const V = (n) => `e0000000-0000-4000-a000-00000000000${n}`
  const CONV = { regina: 'f0000000-0000-4000-a000-000000000001', urban: 'f0000000-0000-4000-a000-000000000002', teuta: 'f0000000-0000-4000-a000-000000000003', dren: 'f0000000-0000-4000-a000-000000000004' }
  const BI = (n) => `b0000000-0000-4000-a000-0000000000${pad(n)}`

  function seed() {
    const profile = (id, o) => Object.assign({ id, role: 'client', status: 'active', full_name: '', username: '', email: '', phone: '', company_id: null, requested_company_name: null, requested_hosting_type: null, requested_description: null, created_at: ago(120), updated_at: ago(10) }, o)
    const profiles = [
      profile(P.admin, { role: 'admin', full_name: 'Ardit Leka', username: 'admin', email: 'admin@example.com', phone: '+383 49 000 001', created_at: ago(400) }),
      profile(P.arben, { full_name: 'Arben Krasniqi', username: 'arben', email: 'arben@example.com', phone: '+383 44 123 456', company_id: C.regina, requested_company_name: 'Regina Center SHPK', requested_hosting_type: 'Local (Windows server)', created_at: ago(310) }),
      profile(P.vjosa, { full_name: 'Vjosa Berisha', username: 'vjosa', email: 'vjosa@example.com', phone: '+383 45 222 333', company_id: C.regina, created_at: ago(200) }),
      profile(P.liridon, { full_name: 'Liridon Gashi', username: 'liridon', email: 'liridon@example.com', phone: '+383 44 555 010', company_id: C.urban, requested_company_name: 'Urban Market', requested_hosting_type: 'Hosting (Cloud)', created_at: ago(150) }),
      profile(P.mimoza, { full_name: 'Mimoza Shala', username: 'mimoza', email: 'mimoza@example.com', phone: '', company_id: C.urban, created_at: ago(90) }),
      profile(P.teuta, { full_name: 'Teuta Hoxha', username: 'teuta', email: 'teuta@example.com', phone: '+383 49 777 120', company_id: C.teuta, requested_company_name: 'Dyqani Teuta', requested_hosting_type: 'Local (Windows PC)', created_at: ago(60) }),
      profile(P.besnik, { status: 'suspended', full_name: 'Besnik Morina', username: 'besnik', email: 'besnik@example.com', phone: '+383 43 300 400', company_id: C.fresh, requested_company_name: 'Fresh Point', requested_hosting_type: 'Hosting (Cloud)', created_at: ago(240) }),
      profile(P.dren, { status: 'pending', full_name: 'Dren Kelmendi', username: 'dren', email: 'dren@example.com', phone: '+383 44 909 808', requested_company_name: 'Market Dardania', requested_hosting_type: 'Local (Windows PC)', requested_description: 'Kemi 3 pika dhe rreth 40 punonjës. Duam hyrje/dalje me QR dhe plan turnesh. A mund ta instaloni në PC-në tonë në zyrë?', created_at: ago(1, 3) }),
      profile(P.elira, { status: 'pending', full_name: 'Elira Rexhepi', username: 'elira', email: 'elira@example.com', phone: '+383 45 616 717', requested_company_name: 'Farmacia Iliria', requested_hosting_type: 'Hosting (Cloud)', requested_description: 'Dy farmaci, 12 punonjës me turne. Na intereson edhe moduli i pushimeve.', created_at: ago(0, 5) })
    ]
    const company = (id, name, slug, o) => Object.assign({ id, name, slug, status: 'active', contact_email: '', contact_phone: '', created_at: ago(200) }, o)
    const companies = [
      company(C.regina, 'Regina Center SHPK', 'regina-center', { contact_email: 'regina@example.com', contact_phone: '+383 44 123 456', created_at: ago(305) }),
      company(C.urban, 'Urban Market', 'urban-market', { contact_email: 'urban@example.com', contact_phone: '+383 44 555 010', created_at: ago(148) }),
      company(C.teuta, 'Dyqani Teuta', 'dyqani-teuta', { contact_email: 'teuta@example.com', contact_phone: '+383 49 777 120', created_at: ago(58) }),
      company(C.fresh, 'Fresh Point', 'fresh-point', { status: 'suspended', contact_email: 'fresh@example.com', contact_phone: '+383 43 300 400', created_at: ago(238) })
    ]
    const system = (id, company_id, o) => Object.assign({ id, company_id, name: 'HRSystem', status: 'active', status_note: null, status_changed_at: ago(30), version: '1.0.8', deployment_url: '', environment: 'production', hosting: 'Hostinger', database_provider: 'MySQL', plan: 'HRSystem', support_note: '', created_at: ago(200), updated_at: ago(3) }, o)
    const systems = [
      system(S.regina, C.regina, { version: '1.0.8', deployment_url: 'https://hr.regina.example.com', hosting: 'Local (Windows server)', support_note: 'Backup-i automatik çdo natë në 02:00. Për ndryshime në turne na shkruaj në chat.', created_at: ago(300) }),
      system(S.urban, C.urban, { status: 'maintenance', status_note: 'Mirëmbajtje e planifikuar — kthehet online rreth orës 14:00.', status_changed_at: ago(0, 2), version: '1.0.7', deployment_url: 'https://hr.urban.example.com', hosting: 'Hostinger', created_at: ago(146) }),
      system(S.teuta, C.teuta, { status: 'in_progress', status_note: 'Po importojmë listën e punonjësve.', status_changed_at: ago(1), version: '1.0.8', deployment_url: '', hosting: 'Local (Windows PC)', created_at: ago(57) }),
      system(S.fresh, C.fresh, { status: 'suspended', status_note: 'Qasja u pezullua deri në rregullimin e pagesës.', status_changed_at: ago(12), version: '1.0.6', deployment_url: 'https://hr.freshpoint.example.com', hosting: 'Hostinger', created_at: ago(236) })
    ]
    const version = (n, sys, comp, o) => Object.assign({ id: V(n), system_id: sys, company_id: comp, version: '', release_type: 'release', release_notes: '', file_path: `${comp}/${V(n)}.zip`, original_name: '', file_size: 1310645, mime_type: 'application/zip', sha256: 'qa' + String(n).repeat(62), is_current: false, created_by: P.admin, created_at: ago(10) }, o)
    const system_versions = [
      version(1, S.regina, C.regina, { version: '1.0.8', original_name: 'HRSystem-1.0.8.zip', file_size: 1310645, is_current: true, release_notes: 'Evidencë automatike, kërkesat e reja dhe ngjyrat e turneve.', created_at: ago(2) }),
      version(2, S.regina, C.regina, { version: '1.0.7', original_name: 'HRSystem-1.0.7.zip', file_size: 1284906, release_notes: '“Raporto një gabim” dhe pa zoom në telefon.', created_at: ago(9) }),
      version(3, S.regina, C.regina, { version: 'backup-' + dayOff(-5), release_type: 'backup', original_name: 'regina-db-backup.sql.gz', file_size: 48231904, mime_type: 'application/gzip', release_notes: 'Backup i databazës para update-it.', created_at: ago(5) }),
      version(4, S.urban, C.urban, { version: '1.0.7', original_name: 'HRSystem-1.0.7.zip', file_size: 1284906, is_current: true, created_at: ago(9) }),
      version(5, S.teuta, C.teuta, { version: '1.0.8', original_name: 'HRSystem-1.0.8.zip', file_size: 1310645, is_current: true, release_notes: 'Instalimi i parë.', created_at: ago(1, 6) })
    ]
    const upd = (n, comp, kind, title, body, days, o) => Object.assign({ id: `a0000000-0000-4000-a000-00000000000${n}`, company_id: comp, kind, title, body, is_published: true, published_at: ago(days), created_at: ago(days), created_by: P.admin }, o)
    const company_updates = [
      upd(1, C.regina, 'update', 'Versioni 1.0.8 u instalua', 'Evidenca automatike e vonesave dhe mungesave, tri lloje të reja kërkesash dhe ngjyra fikse për turnet në kalendar.', 2),
      upd(2, C.regina, 'maintenance', 'Mirëmbajtje e serverit të shtunën', 'Të shtunën nga 22:00 deri në 23:00 sistemi mund të jetë i ngadaltë. Nuk kërkohet asnjë veprim nga ju.', 6),
      upd(3, C.regina, 'info', 'Udhëzuesi i ri për menaxherët', 'Te Ndihmë gjeni udhëzues të shkurtër për planin e turneve dhe aprovimin e pushimeve.', 14),
      upd(4, C.regina, 'billing', 'Rikujtim: pagesa e domain-it', 'Afati i pagesës vjetore për domain-in ka kaluar. Ju lutem kryeni pagesën që adresa të mos ndërpritet.', 18),
      upd(5, C.urban, 'maintenance', 'Mirëmbajtje sot', 'Sistemi do të jetë jashtë funksionit për rreth një orë gjatë mirëmbajtjes.', 0.1),
      upd(6, C.teuta, 'info', 'Mirë se erdhët në HRSystem', 'Konfigurimi po përfundon. Do t’ju njoftojmë kur stafi të mund të hyjë.', 1),
      upd(7, C.regina, 'update', 'Draft: Raportet e reja mujore', 'Ende nuk është publikuar.', 0.5, { is_published: false })
    ]
    const conv = (id, o) => Object.assign({ id, company_id: null, prospect_profile_id: null, subject: 'HRSystem Support', status: 'open', last_message_at: null, created_at: ago(30) }, o)
    const support_conversations = [
      conv(CONV.regina, { company_id: C.regina, created_at: ago(40), last_message_at: ago(0, 1, 20) }),
      conv(CONV.urban, { company_id: C.urban, created_at: ago(20), last_message_at: ago(0, 0, 35) }),
      conv(CONV.teuta, { company_id: C.teuta, status: 'closed', created_at: ago(10), last_message_at: ago(3) }),
      conv(CONV.dren, { prospect_profile_id: P.dren, subject: 'Kërkesë: Market Dardania', created_at: ago(1, 2), last_message_at: ago(0, 20) })
    ]
    let mi = 0
    const msg = (conversation_id, sender_id, sender_role, message, at, is_read = true) => ({ id: `90000000-0000-4000-a000-0000000000${pad(++mi)}`, conversation_id, sender_id, sender_role, message, is_read, created_at: at })
    const support_messages = [
      msg(CONV.regina, P.arben, 'client', 'Përshëndetje! Një punonjëse nuk po mund ta skanojë QR-në në pikën e dytë.', ago(1, 4)),
      msg(CONV.regina, P.admin, 'admin', 'Përshëndetje Arben. A mund të na dërgoni emrin e pikës dhe orën kur ndodhi?', ago(1, 3, 40)),
      msg(CONV.regina, P.arben, 'client', 'Pika “Qendra”, sot rreth orës 08:05.', ago(1, 3, 20)),
      msg(CONV.regina, P.admin, 'admin', 'E rregulluam: QR-ja ishte rigjeneruar. Printojeni kodin e ri nga Cilësimet e Hyrje/Daljeve.', ago(0, 1, 20), false),
      msg(CONV.urban, P.liridon, 'client', 'Sa zgjat mirëmbajtja sot? Kemi ndërrimin e pasdites në 14:00.', ago(0, 0, 35), false),
      msg(CONV.teuta, P.teuta, 'client', 'Faleminderit për instalimin!', ago(3, 2)),
      msg(CONV.teuta, P.admin, 'admin', 'Me kënaqësi. Na shkruani për çdo pyetje.', ago(3)),
      msg(CONV.dren, P.dren, 'client', 'A ka mundësi të shohim një demonstrim para se ta aktivizoni llogarinë?', ago(0, 22)),
      msg(CONV.dren, P.admin, 'admin', 'Sigurisht. Ju telefonojmë nesër paradite për një takim të shkurtër.', ago(0, 20), false)
    ]
    const lead = (n, o) => Object.assign({ id: `70000000-0000-4000-a000-00000000000${n}`, name: '', company_name: '', email: '', phone: '', hosting_type: '', interest: 'HRSystem', message: '', status: 'new', source: 'showcase', created_at: ago(1) }, o)
    const lead_submissions = [
      lead(1, { name: 'Albana Dervishi', company_name: 'Boutique Albana', email: 'albana@example.com', phone: '+383 44 101 202', hosting_type: 'Hosting (Cloud)', message: 'Kemi 2 dyqane dhe 9 punonjës. Sa kushton?', status: 'new', created_at: ago(0, 3) }),
      lead(2, { name: 'Faton Bajrami', company_name: 'Auto Servis Bajrami', email: 'faton@example.com', phone: '+383 45 303 404', hosting_type: 'Local (Windows PC)', message: 'Na duhet vetëm hyrje/dalje me QR.', status: 'new', created_at: ago(1, 2) }),
      lead(3, { name: 'Genta Kastrati', company_name: 'Kafe Genta', email: 'genta@example.com', phone: '', hosting_type: 'Hosting (Cloud)', message: 'A funksionon në telefon pa instalim?', status: 'contacted', created_at: ago(4) }),
      lead(4, { name: 'Ilir Musliu', company_name: 'Market Musliu', email: 'ilir@example.com', phone: '+383 49 505 606', hosting_type: 'Local (Windows server)', message: '5 pika, rreth 60 punonjës, turne me rotacion.', status: 'qualified', created_at: ago(8) }),
      lead(5, { name: 'Lule Avdiu', company_name: '', email: 'lule@example.com', phone: '', hosting_type: '', message: 'Vetëm po shikoj.', status: 'closed', created_at: ago(21) }),
      lead(6, { name: 'test test', company_name: 'asdf', email: 'spam@example.com', phone: '', hosting_type: '', message: 'http://spam.example.com', status: 'spam', created_at: ago(26) })
    ]
    let ai = 0
    const aud = (action, target_type, target_id, details, at) => ({ id: `60000000-0000-4000-a000-0000000000${pad(++ai)}`, actor_id: P.admin, action, target_type, target_id, details, created_at: at })
    const admin_audit_log = [
      aud('version_uploaded', 'system_version', V(1), { version: '1.0.8' }, ago(2, 1)),
      aud('version_set_current', 'system_version', V(1), { version: '1.0.8' }, ago(2)),
      aud('system_updated', 'system', S.urban, { name: 'Urban Market' }, ago(0, 2)),
      aud('payment_recorded', 'billing_payment', BI(41), { name: 'Regina Center SHPK' }, ago(21)),
      aud('billing_updated', 'company', C.regina, { name: 'Regina Center SHPK' }, ago(30)),
      aud('client_activated', 'profile', P.teuta, { email: 'teuta@example.com' }, ago(58)),
      aud('update_user', 'profile', P.besnik, { email: 'besnik@example.com' }, ago(12)),
      aud('delete_lead', 'lead', 'lead-old-1', { name: 'Kërkesë e vjetër' }, ago(15)),
      aud('version_uploaded', 'system_version', V(5), { version: '1.0.8' }, ago(1, 6)),
      aud('delete_version', 'system_version', 'v-old-2', { version: '1.0.5' }, ago(16)),
      aud('account_updated', 'profile', P.arben, { email: 'arben@example.com' }, ago(40)),
      aud('delete_message', 'support_message', 'm-old-3', {}, ago(44))
    ]
    const item = (n, company_id, kind, amount, billing_interval, next_due_on, o) => Object.assign({ id: BI(n), company_id, kind, label: '', amount, currency: 'EUR', billing_interval, next_due_on, is_active: true, created_at: ago(300 - n) }, o)
    const billing_items = [
      // Regina: hosting paid, domain OVERDUE, maintenance due in 9 days, setup paid in full
      item(1, C.regina, 'setup', 999, 'one_time', null),
      item(2, C.regina, 'hosting', 180, 'yearly', dayOff(120)),
      item(3, C.regina, 'domain', 25, 'yearly', dayOff(-18), { label: 'regina.example.com' }),
      item(4, C.regina, 'maintenance', 49, 'monthly', dayOff(9)),
      // Urban: setup partly paid (300 € left), hosting scheduled
      item(5, C.urban, 'setup', 999, 'one_time', null),
      item(6, C.urban, 'hosting', 180, 'yearly', dayOff(200)),
      // Teuta: management monthly + other yearly
      item(7, C.teuta, 'management', 89, 'monthly', dayOff(20)),
      item(8, C.teuta, 'other', 60, 'yearly', dayOff(300), { label: 'Trajnim vjetor i stafit' }),
      // Fresh Point: hosting inactive (suspended client)
      item(9, C.fresh, 'hosting', 180, 'yearly', dayOff(-40), { is_active: false })
    ]
    const pay = (n, company_id, item_id, amount, daysAgo, method, note = '') => ({ id: BI(40 + n), company_id, item_id, amount, currency: 'EUR', paid_on: dayOff(-daysAgo), method, note, created_at: ago(daysAgo) })
    const billing_payments = [
      pay(1, C.regina, BI(4), 49, 21, 'Bankë', 'Mirëmbajtja e muajit'),
      pay(2, C.regina, BI(2), 180, 245, 'Bankë', 'Fatura nr. 12'),
      pay(3, C.regina, BI(1), 999, 300, 'Bankë', 'Setup'),
      pay(4, C.urban, BI(5), 699, 140, 'Cash', 'Kësti i parë')
    ]
    return { profiles, companies, systems, system_versions, company_updates, support_conversations, support_messages, lead_submissions, admin_audit_log, billing_items, billing_payments }
  }

  let db = seed()

  // ---------- session handling ----------
  const profileById = (id) => db.profiles.find((p) => p.id === id)
  function makeSession(uid) {
    const p = profileById(uid) || { id: uid, email: 'qa@example.com' }
    return { access_token: makeToken(p.id, p.email), refresh_token: `qa-refresh.${p.id}`, expires_in: 10 * 365 * 86400, expires_at: EXP, token_type: 'bearer', user: { id: p.id, email: p.email, aud: 'authenticated', role: 'authenticated' } }
  }
  function currentUid() {
    try { const s = JSON.parse(localStorage.getItem('hrsystem_session') || 'null'); const pl = tokenPayload(s?.access_token); if (pl.qa && pl.sub) return pl.sub } catch {}
    return null
  }
  function applyMode(m, force) {
    try {
      if (m === 'out') { if (force) { localStorage.removeItem('hrsystem_session'); localStorage.removeItem('hrsystem_role') } return }
      const existing = currentUid()
      if (!force && existing && profileById(existing)) return // keep a QA login (e.g. signed in as another seeded user)
      const uid = IDS[m] || IDS.client
      localStorage.setItem('hrsystem_session', JSON.stringify(makeSession(uid)))
      localStorage.setItem('hrsystem_role', m === 'admin' ? 'admin' : 'client')
    } catch {}
  }
  // A real (non-QA) token is always replaced; ?qa=... forces the mode's user.
  try { const s = JSON.parse(localStorage.getItem('hrsystem_session') || 'null'); if (s && !tokenPayload(s.access_token).qa) forced = true } catch {}
  applyMode(mode, forced)
  if (forced) { try { const u = new URL(location.href); if (u.searchParams.has('qa')) { u.searchParams.delete('qa'); history.replaceState(history.state, '', u.pathname + u.search + u.hash) } } catch {} }

  function me(headers) {
    let tok = ''
    try { const h = headers instanceof Headers ? headers : new Headers(headers || {}); tok = (h.get('Authorization') || '').replace(/^Bearer\s+/i, '') } catch {}
    const pl = tok ? tokenPayload(tok) : {}
    return pl.sub ? profileById(pl.sub) || null : null
  }

  // ---------- PostgREST emulation ----------
  const coerce = (v) => v === 'true' ? true : v === 'false' ? false : v === 'null' ? null : v
  function matchFilter(row, col, expr) {
    const i = expr.indexOf('.')
    const op = i < 0 ? 'eq' : expr.slice(0, i)
    const raw = i < 0 ? expr : expr.slice(i + 1)
    const val = row[col]
    if (op === 'not') return !matchFilter(row, col, raw)
    switch (op) {
      case 'eq': { const c = coerce(raw); return typeof c === 'boolean' || c === null ? val === c : String(val) === c }
      case 'neq': return String(val) !== raw
      case 'is': { const c = coerce(raw); return c === null ? val == null : val === c }
      case 'in': { const list = raw.replace(/^\(|\)$/g, '').split(',').map((s) => s.replace(/^"|"$/g, '')); return list.includes(String(val)) }
      case 'gt': return val != null && String(val) > raw
      case 'gte': return val != null && String(val) >= raw
      case 'lt': return val != null && String(val) < raw
      case 'lte': return val != null && String(val) <= raw
      case 'like': case 'ilike': { const re = new RegExp('^' + raw.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*').replace(/%/g, '.*') + '$', op === 'ilike' ? 'i' : ''); return re.test(String(val ?? '')) }
      default: return true
    }
  }
  const RESERVED = new Set(['select', 'order', 'limit', 'offset', 'on_conflict', 'columns'])
  function parseQuery(search) {
    const sp = new URLSearchParams(search)
    const filters = []
    for (const [k, v] of sp) if (!RESERVED.has(k)) filters.push([k, v])
    return { filters, select: sp.get('select') || '*', order: sp.get('order'), limit: sp.has('limit') ? Number(sp.get('limit')) : null, offset: Number(sp.get('offset') || 0) }
  }
  function sortRows(rows, order) {
    if (!order) return rows
    const keys = order.split(',').map((part) => { const [col, ...mods] = part.split('.'); const desc = mods.includes('desc'); const nullsLast = mods.includes('nullslast') ? true : mods.includes('nullsfirst') ? false : !desc; return { col, desc, nullsLast } })
    return rows.slice().sort((a, b) => {
      for (const k of keys) {
        const x = a[k.col], y = b[k.col]
        if (x == null && y == null) continue
        if (x == null) return k.nullsLast ? 1 : -1
        if (y == null) return k.nullsLast ? -1 : 1
        const c = typeof x === 'number' && typeof y === 'number' ? x - y : String(x).localeCompare(String(y))
        if (c) return k.desc ? -c : c
      }
      return 0
    })
  }
  function project(rows, select) {
    if (!select || select === '*' || /[()]/.test(select)) return rows
    const cols = select.split(',').map((s) => s.trim()).filter(Boolean)
    return rows.map((r) => Object.fromEntries(cols.map((c) => [c, r[c] ?? null])))
  }
  // Row-level security, roughly as the live policies: clients see only their company / their own rows.
  function visible(table, user) {
    const rows = db[table] || []
    if (user?.role === 'admin') return rows
    if (!user) return [] // anonymous: nothing readable (the homepage lead form only inserts)
    const cid = user.company_id
    const myConvIds = new Set(db.support_conversations.filter((c) => (cid && c.company_id === cid) || c.prospect_profile_id === user.id).map((c) => c.id))
    switch (table) {
      case 'profiles': return rows.filter((p) => p.id === user.id)
      case 'companies': return rows.filter((c) => c.id === cid)
      case 'systems': case 'system_versions': case 'billing_items': case 'billing_payments': return cid && user.status === 'active' ? rows.filter((r) => r.company_id === cid) : []
      case 'company_updates': return cid && user.status === 'active' ? rows.filter((r) => r.company_id === cid && r.is_published) : []
      case 'support_conversations': return rows.filter((c) => myConvIds.has(c.id))
      case 'support_messages': return rows.filter((m) => myConvIds.has(m.conversation_id))
      default: return []
    }
  }
  function defaultsFor(table, row, user) {
    const now = new Date().toISOString()
    const r = Object.assign({ id: uuid(), created_at: now }, row)
    if (table === 'support_messages') {
      r.sender_role = r.sender_role || (user?.role === 'admin' ? 'admin' : 'client'); if (r.is_read == null) r.is_read = false
      const c = db.support_conversations.find((x) => x.id === r.conversation_id); if (c) c.last_message_at = r.created_at
    }
    if (table === 'support_conversations' && !('last_message_at' in r)) r.last_message_at = null
    if (table === 'company_updates') { if (!r.published_at) r.published_at = now; if (r.is_published == null) r.is_published = true }
    if (table === 'lead_submissions' && !r.status) r.status = 'new'
    if (table === 'billing_items' && r.is_active == null) r.is_active = true
    return r
  }
  function restHandler(table, method, search, bodyText, headers) {
    if (!db[table]) db[table] = []
    const user = me(headers)
    const q = parseQuery(search)
    const prefer = (() => { try { return (headers instanceof Headers ? headers : new Headers(headers || {})).get('Prefer') || '' } catch { return '' } })()
    const wantRep = /return=representation/.test(prefer)
    const body = bodyText ? (() => { try { return JSON.parse(bodyText) } catch { return null } })() : null
    const match = (rows) => rows.filter((r) => q.filters.every(([c, e]) => matchFilter(r, c, e)))
    if (method === 'GET' || method === 'HEAD') {
      let rows = sortRows(match(visible(table, user)), q.order)
      if (q.offset) rows = rows.slice(q.offset)
      if (q.limit != null) rows = rows.slice(0, q.limit)
      return [200, project(rows, q.select)]
    }
    if (method === 'POST') {
      if (!user && table !== 'lead_submissions') return [401, { message: 'JWT required (QA stub)' }]
      const list = (Array.isArray(body) ? body : [body || {}]).map((r) => defaultsFor(table, r, user))
      db[table].push(...list)
      return [201, wantRep ? list : null]
    }
    if (method === 'PATCH') {
      if (!user) return [401, { message: 'JWT required (QA stub)' }]
      const rows = match(visible(table, user))
      rows.forEach((r) => Object.assign(r, body || {}, 'updated_at' in r ? { updated_at: new Date().toISOString() } : {}))
      if (table === 'systems' && body && 'status' in body) rows.forEach((r) => { r.status_changed_at = new Date().toISOString() })
      return [200, wantRep ? rows : null]
    }
    if (method === 'DELETE') {
      if (!user) return [401, { message: 'JWT required (QA stub)' }]
      const rows = new Set(match(visible(table, user)))
      db[table] = db[table].filter((r) => !rows.has(r))
      return [200, wantRep ? [...rows] : null]
    }
    return [405, { message: 'Method not allowed (QA stub)' }]
  }
  function rpcHandler(fn, bodyText, headers) {
    const user = me(headers)
    const body = bodyText ? (() => { try { return JSON.parse(bodyText) } catch { return {} } })() : {}
    if (fn === 'mark_conversation_read') {
      const role = user?.role === 'admin' ? 'admin' : 'client'
      let n = 0
      db.support_messages.forEach((m) => { if (m.conversation_id === body.conv && m.sender_role !== role && !m.is_read) { m.is_read = true; n++ } })
      return [200, n]
    }
    return [200, null]
  }

  // ---------- auth / functions / storage ----------
  const findLogin = (ident) => { const v = String(ident || '').trim().toLowerCase(); return db.profiles.find((p) => p.username === v || p.email === v) }
  function authHandler(path, method, search, bodyText, headers) {
    const body = bodyText ? (() => { try { return JSON.parse(bodyText) } catch { return {} } })() : {}
    if (path.startsWith('/auth/v1/token')) {
      const rt = String(body.refresh_token || '')
      const uid = rt.startsWith('qa-refresh.') ? rt.slice('qa-refresh.'.length) : IDS[mode] || IDS.client
      return [200, makeSession(uid)]
    }
    if (path === '/auth/v1/user') {
      const u = me(headers); if (!u) return [401, { message: 'not signed in (QA stub)' }]
      if (method === 'PUT' && body.email) u.email = body.email
      return [200, { id: u.id, email: u.email, aud: 'authenticated', role: 'authenticated' }]
    }
    if (path === '/auth/v1/logout') return [204, null]
    if (path === '/auth/v1/recover') return [200, {}]
    return [200, {}]
  }
  function functionsHandler(name, bodyText, headers) {
    const body = bodyText ? (() => { try { return JSON.parse(bodyText) } catch { return {} } })() : {}
    const user = me(headers)
    if (name === 'username-login') {
      const p = findLogin(body.identifier)
      if (!p) return [400, { error: 'Username/email ose password-i është i gabuar.', code: 'invalid_credentials' }]
      if (p.status === 'suspended') return [403, { error: 'Llogaria është pezulluar.', code: 'suspended' }]
      return [200, makeSession(p.id)]
    }
    if (name === 'client-signup') {
      if (findLogin(body.username)) return [409, { error: 'Ky username është i zënë.', code: 'username_taken' }]
      if (findLogin(body.email)) return [409, { error: 'Ky email është i regjistruar.', code: 'email_taken' }]
      const p = { id: uuid(), role: 'client', status: 'pending', full_name: body.full_name || '', username: body.username || '', email: body.email || '', phone: body.phone || '', company_id: null, requested_company_name: body.company_name || '', requested_hosting_type: body.hosting_type || '', requested_description: body.request_description || '', created_at: new Date().toISOString() }
      db.profiles.push(p)
      return [200, { ok: true, session: makeSession(p.id) }]
    }
    if (name === 'client-account') {
      if (!user) return [401, { error: 'not signed in (QA stub)' }]
      ;['full_name', 'phone', 'email'].forEach((k) => { if (body[k] != null) user[k] = body[k] })
      return [200, { ok: true, email: user.email, reauth: false }]
    }
    if (name === 'admin-manage-client') {
      if (user?.role !== 'admin') return [403, { error: 'admin only (QA stub)' }]
      const a = body.action
      if (a === 'activate_client') {
        const p = profileById(body.user_id); if (!p) return [404, { error: 'not found' }]
        let cid = body.company_id
        if (!cid) { cid = uuid(); db.companies.push({ id: cid, name: body.company_name, slug: body.company_name.toLowerCase().replace(/[^a-z0-9]+/g, '-'), status: 'active', contact_email: p.email, contact_phone: p.phone, created_at: new Date().toISOString() }) }
        if (!db.systems.some((s) => s.company_id === cid)) db.systems.push(Object.assign({ id: uuid(), company_id: cid, created_at: new Date().toISOString(), status_changed_at: new Date().toISOString() }, body.system || {}))
        Object.assign(p, { status: 'active', company_id: cid })
        return [200, { ok: true }]
      }
      if (a === 'update_user') { const p = profileById(body.user_id); if (p) { const { user_id, password, ...rest } = body; delete rest.action; Object.assign(p, rest, rest.company_id === '' ? { company_id: null } : {}) } return [200, { ok: true }] }
      if (a === 'delete_user') { db.profiles = db.profiles.filter((p) => p.id !== body.user_id); return [200, { ok: true }] }
      if (a === 'delete_version') { db.system_versions = db.system_versions.filter((v) => v.id !== body.version_id); return [200, { ok: true }] }
      if (a === 'delete_company') { db.companies = db.companies.filter((c) => c.id !== body.company_id); db.systems = db.systems.filter((s) => s.company_id !== body.company_id); return [200, { ok: true }] }
      if (a === 'delete_conversation') { db.support_conversations = db.support_conversations.filter((c) => c.id !== body.id); db.support_messages = db.support_messages.filter((m) => m.conversation_id !== body.id); return [200, { ok: true }] }
      const tbl = { delete_lead: 'lead_submissions', delete_update: 'company_updates', delete_message: 'support_messages' }[a]
      if (tbl) { db[tbl] = db[tbl].filter((r) => r.id !== body.id); return [200, { ok: true }] }
      return [200, { ok: true }]
    }
    return [200, { ok: true }]
  }

  // ---------- router ----------
  const log = []
  function route(url, method, bodyText, headers) {
    const u = new URL(url, location.href)
    const path = u.pathname
    let m
    if ((m = path.match(/^\/rest\/v1\/rpc\/([^/?]+)/))) return rpcHandler(decodeURIComponent(m[1]), bodyText, headers)
    if ((m = path.match(/^\/rest\/v1\/([^/?]+)/))) return restHandler(decodeURIComponent(m[1]), method, u.search, bodyText, headers)
    if (path.startsWith('/auth/v1/')) return authHandler(path, method, u.search, bodyText, headers)
    if ((m = path.match(/^\/functions\/v1\/([^/?]+)/))) return functionsHandler(decodeURIComponent(m[1]), bodyText, headers)
    if (path.startsWith('/storage/v1/')) {
      if (method === 'GET') return [200, '__blob__']
      return [200, { Key: path.replace(/^\/storage\/v1\/object\//, '') }]
    }
    return [404, { message: 'Not handled by QA stub' }]
  }
  const delay = (() => { try { return Math.max(0, Number(localStorage.getItem('qa_delay') ?? 120)) } catch { return 120 } })()
  const realFetch = window.fetch.bind(window)
  async function readBody(input, init) {
    const b = init && 'body' in init ? init.body : input instanceof Request ? await input.clone().text().catch(() => '') : undefined
    if (b == null) return ''
    if (typeof b === 'string') return b
    if (b instanceof Blob) return b.type && /json|text/.test(b.type) ? await b.text() : '' // file uploads are not stored
    try { return String(b) } catch { return '' }
  }
  window.fetch = async function qaFetch(input, init) {
    const url = input instanceof Request ? input.url : String(input)
    if (!isSupaUrl(url)) return realFetch(input, init)
    const method = String((init && init.method) || (input instanceof Request ? input.method : 'GET')).toUpperCase()
    const headers = (init && init.headers) || (input instanceof Request ? input.headers : {})
    const bodyText = await readBody(input, init)
    let status, data
    try { [status, data] = route(url, method, bodyText, headers) } catch (err) { console.error('[qa] stub error', err); status = 500; data = { message: String(err && err.message || err) } }
    log.push({ t: Date.now(), method, url: url.replace(SUPA_URL, ''), status })
    if (log.length > 300) log.shift()
    if (delay) await new Promise((r) => setTimeout(r, delay))
    if (data === '__blob__') return new Response(new Blob(['HRSystem QA placeholder file\n'], { type: 'application/zip' }), { status: 200, headers: { 'Content-Type': 'application/zip' } })
    const noBody = status === 204 || data == null
    return new Response(noBody ? (status === 204 ? null : '') : JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } })
  }

  // ---------- block every other way to the live project ----------
  const RealWS = window.WebSocket
  class QAWebSocket extends EventTarget {
    constructor(url) {
      super()
      this.url = String(url); this.readyState = 0; this.protocol = ''; this.extensions = ''; this.bufferedAmount = 0; this.binaryType = 'blob'
      this.onopen = this.onclose = this.onerror = this.onmessage = null
      if (!isSupaUrl(this.url)) { console.warn('[qa] WebSocket blocked (QA mode):', this.url) }
      // never connects: stays CONNECTING; supabase-js falls back to the app's polling
    }
    send() {}
    close() { if (this.readyState === 3) return; this.readyState = 3; const ev = new Event('close'); try { ev.code = 1000; ev.wasClean = true } catch {} ; this.dispatchEvent(ev); try { this.onclose && this.onclose(ev) } catch {} }
  }
  QAWebSocket.CONNECTING = 0; QAWebSocket.OPEN = 1; QAWebSocket.CLOSING = 2; QAWebSocket.CLOSED = 3
  // Only Supabase sockets are faked; other sockets (none expected) keep the real implementation.
  window.WebSocket = function (url, protocols) { return isSupaUrl(String(url).replace(/^ws/, 'http')) ? new QAWebSocket(url) : new RealWS(url, protocols) }
  Object.assign(window.WebSocket, { CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3, prototype: QAWebSocket.prototype })
  const realBeacon = navigator.sendBeacon ? navigator.sendBeacon.bind(navigator) : null
  if (realBeacon) navigator.sendBeacon = (url, data) => isSupaUrl(url) ? true : realBeacon(url, data)
  const xhrOpen = XMLHttpRequest.prototype.open
  XMLHttpRequest.prototype.open = function (method, url, ...rest) {
    if (isSupaUrl(url)) { console.warn('[qa] XHR to Supabase blocked:', url); return xhrOpen.call(this, method, 'data:application/json,null', ...rest) }
    return xhrOpen.call(this, method, url, ...rest)
  }
  if (window.EventSource) { const RealES = window.EventSource; window.EventSource = function (url, cfg) { if (isSupaUrl(url)) throw new Error('[qa] EventSource to Supabase blocked'); return new RealES(url, cfg) } }

  // ---------- debug handle ----------
  window.__qa = {
    get db() { return db }, get mode() { return mode }, log, ids: IDS, companies: C,
    setMode(m) { if (!MODES.includes(m)) throw new Error('mode: ' + MODES.join('|')); localStorage.setItem('qa_mode', m); mode = m; applyMode(m, true); location.reload() },
    reset() { db = seed(); location.reload() },
    route // for node tests
  }
  console.info(`[qa] Supabase stub active — mode "${mode}". Switch: ?qa=client|admin|pending|out or __qa.setMode('admin').`)
})()
