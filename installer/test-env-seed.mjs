// Invented data for a company of the test space (C:\HRTest\<name>): 520+ employees with attendance, absences, leave, requests ...
// Usage: node test-env-seed.mjs <name>   (the company's database is emptied first; test data only, never the real install)
// Everyone gets the password "testtest123"; owner "pronari", managers "menaxher1..", cashiers "arkatar1..", staff "punonjes0001..".
import { createRequire } from 'node:module';
import { pathToFileURL } from 'node:url';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const name = process.argv[2];
if (!/^[a-z][a-z0-9]{1,15}$/.test(name || '')) throw new Error('usage: node test-env-seed.mjs <name>');
const root = `C:\\HRTest\\${name}`;
const env = Object.fromEntries(fs.readFileSync(path.join(root, '.env'), 'utf8').split(/\r?\n/).filter((l) => l.includes('=') && !l.startsWith('#')).map((l) => [l.slice(0, l.indexOf('=')).trim(), l.slice(l.indexOf('=') + 1)]));
const release = fs.readFileSync(path.join(root, 'current.txt'), 'utf8').trim();
const releaseDir = path.join(root, 'releases', release);
const require = createRequire(path.join(releaseDir, 'package.json'));
const mysql = require('mysql2/promise');
const { MANAGER_PERMISSION_KEYS } = await import(pathToFileURL(path.join(releaseDir, 'server', 'core', 'config.mjs')).href);

// Same data every time for the same company.
let seedState = [...name].reduce((a, c) => (a * 31 + c.charCodeAt(0)) >>> 0, 7);
const rnd = () => ((seedState = (Math.imul(seedState, 1664525) + 1013904223) >>> 0) / 4294967296);
const pick = (arr) => arr[Math.floor(rnd() * arr.length)];
const chance = (p) => rnd() < p;
const uid = () => crypto.randomBytes(12).toString('hex');
const pad = (n, w = 2) => String(n).padStart(w, '0');
const day = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const time = (min) => `${pad(Math.floor(min / 60))}:${pad(min % 60)}:00`;
const SHARED = '000000000000000000000001';

const FIRST_M = ['Arben', 'Blerim', 'Dardan', 'Driton', 'Edon', 'Fatmir', 'Gezim', 'Granit', 'Ilir', 'Jeton', 'Kreshnik', 'Liridon', 'Mentor', 'Nderim', 'Orges', 'Petrit', 'Qendrim', 'Rinor', 'Shpend', 'Taulant', 'Valon', 'Visar', 'Altin', 'Besnik', 'Burim', 'Fitim', 'Genc', 'Labinot', 'Lirim', 'Muhamet'];
const FIRST_F = ['Arta', 'Blerta', 'Diellza', 'Drita', 'Elira', 'Fjolla', 'Gentiana', 'Hana', 'Ilirjana', 'Jeta', 'Kaltrina', 'Lindita', 'Mimoza', 'Nora', 'Orjeta', 'Pranvera', 'Qëndresa', 'Rozafa', 'Shqipe', 'Teuta', 'Vjosa', 'Yllka', 'Albulena', 'Besarta', 'Donika', 'Flutura', 'Gresa', 'Lule', 'Rita', 'Valbona'];
const LAST = ['Berisha', 'Krasniqi', 'Gashi', 'Morina', 'Hoxha', 'Shala', 'Kelmendi', 'Rama', 'Bytyqi', 'Hasani', 'Ahmeti', 'Rexhepi', 'Mustafa', 'Dervishi', 'Kastrati', 'Haliti', 'Zeqiri', 'Selimi', 'Brahimi', 'Mehmeti', 'Latifi', 'Osmani', 'Salihu', 'Bajrami', 'Thaçi', 'Maloku', 'Sylejmani', 'Ibrahimi', 'Gjoka', 'Dreshaj'];
const PLACES = { regina: ['Prishtinë - Qendra', 'Prishtinë - Ulpiana', 'Prizren', 'Pejë', 'Gjakovë', 'Ferizaj', 'Gjilan', 'Mitrovicë', 'Podujevë', 'Vushtrri'], template: ['Pika 1', 'Pika 2', 'Pika 3', 'Pika 4', 'Pika 5', 'Pika 6', 'Pika 7', 'Pika 8'] };
const places = PLACES[name] || PLACES.template;
const STAFF = 520;

const db = await mysql.createConnection({ host: env.DB_HOST, port: Number(env.DB_PORT), user: env.DB_USER, password: env.DB_PASSWORD, database: env.DB_NAME, dateStrings: true, multipleStatements: true });
const q = (sql, params) => db.query(sql, params);
const bulk = async (table, cols, rows) => {
  for (let i = 0; i < rows.length; i += 1000) await q(`INSERT INTO \`${table}\`(${cols.map((c) => `\`${c}\``).join(',')}) VALUES ?`, [rows.slice(i, i + 1000)]);
};

// 1. empty the data tables (the shared settings stay)
await q('SET FOREIGN_KEY_CHECKS=0');
for (const t of ['attendance', 'absences', 'late_arrivals', 'early_departures', 'overtime', 'balances', 'remarks', 'requests', 'leave_requests', 'shift_swaps', 'announcements', 'device_damages', 'devices', 'audit_log', 'users', 'locations', 'employee_groups']) await q(`DELETE FROM \`${t}\``);
await q("DELETE FROM employee_positions WHERE name <> 'Arkatar'");
await q('SET FOREIGN_KEY_CHECKS=1');

// 2. structure: stores, groups, positions, shifts
const locations = places.map((p, i) => ({ id: uid(), name: p, address: `Rr. ${pick(LAST)} ${i + 1}`, active: 1 }));
await bulk('locations', ['id', 'name', 'address', 'active'], locations.map((l) => [l.id, l.name, l.address, l.active]));
const [shifts] = await q('SELECT id,name FROM shift_schedules');
for (const s of shifts) await q('UPDATE shift_schedules SET start_time=?,end_time=? WHERE id=?', [s.name === 'Para-Dite' ? '07:00' : '14:00', s.name === 'Para-Dite' ? '15:00' : '22:00', s.id]);
const shiftBy = Object.fromEntries(shifts.map((s) => [s.name, s.id]));
await q("UPDATE company_info SET workday_start='07:00',workday_end='22:00',sunday_works=0,attendance_enabled=1,pause_minutes=30,late_grace_minutes=5");
const groups = [['Grupi A', 'static', 'Para-Dite', null], ['Grupi B', 'static', 'Pas-Dite', null], ['Grupi C', 'rotation', null, 'Para-Dite'], ['Grupi D', 'rotation', null, 'Pas-Dite']].map(([n, m, v, r]) => ({ id: uid(), name: n, mode: m, value: v, rot: r }));
await bulk('employee_groups', ['id', 'name', 'shift_mode', 'shift_value', 'rotation_start', 'location'], groups.map((g) => [g.id, g.name, g.mode, g.value, g.rot, SHARED]));
const [[arkatar]] = await q("SELECT id FROM employee_positions WHERE name='Arkatar'");
const positions = ['Shitës', 'Magazinier', 'Pastrues', 'Sigurim', 'Ndihmës-shitës'].map((n) => ({ id: uid(), name: n }));
await bulk('employee_positions', ['id', 'name', 'location'], positions.map((p) => [p.id, p.name, SHARED]));

// 3. people
const hash = 'scrypt$0123456789abcdef0123456789abcdef$' + crypto.scryptSync('testtest123', '0123456789abcdef0123456789abcdef', 64).toString('hex');
const people = [];
const used = new Set();
const person = (role, username, loc, group, pos, perms) => {
  let full;
  do { const f = chance(0.5) ? pick(FIRST_M) : pick(FIRST_F); full = `${f} ${pick(LAST)}`; } while (used.has(full) && used.size < 800 && chance(0.9));
  used.add(full);
  const p = { id: uid(), username, name: full, role, loc, group, pos, perms, active: 1, start: `${2019 + Math.floor(rnd() * 7)}-${pad(1 + Math.floor(rnd() * 12))}-${pad(1 + Math.floor(rnd() * 28))} 00:00:00` };
  people.push(p);
  return p;
};
person('pronari', 'pronari', null, null, null, null);
person('pronari', 'pronari2', null, null, null, null);
locations.forEach((l, i) => { person('menaxheri', `menaxher${i + 1}`, l.id, null, null, JSON.stringify(MANAGER_PERMISSION_KEYS)); person('menaxheri', `menaxher${i + 1}b`, l.id, null, null, JSON.stringify(MANAGER_PERMISSION_KEYS.filter((k) => k.endsWith('_view') || k.startsWith('attendance') || k.startsWith('leaves')))); });
const staff = [];
for (let i = 1; i <= STAFF; i++) {
  const loc = locations[i % locations.length];
  const cashier = i % 9 === 0;
  const p = person(cashier ? 'arkatar' : 'punonjes', cashier ? `arkatar${i}` : `punonjes${pad(i, 4)}`, loc.id, groups[i % groups.length].id, cashier ? arkatar.id : positions[i % positions.length].id, null);
  p.active = i % 53 === 0 ? 0 : 1;
  staff.push(p);
}
await bulk('users', ['id', 'username', 'password_hash', 'name', 'role', 'location', 'employee_group', 'position', 'manager_permissions', 'active', 'rest_day', 'start_date'],
  people.map((p) => [p.id, p.username, hash, p.name, p.role, p.loc, p.group, p.pos, p.perms, p.active, 'E diel', p.start]));

// 4. last 52 days of work (the day before "today" is the newest)
const today = new Date(); today.setHours(0, 0, 0, 0);
const days = [];
for (let n = 52; n >= 1; n--) { const d = new Date(today); d.setDate(d.getDate() - n); if (d.getDay() !== 0) days.push(d); }
const active = staff.filter((p) => p.active);
const att = [], late = [], early = [], abs = [], ot = [];
for (const d of days) {
  const ds = `${day(d)} 00:00:00`;
  for (const p of active) {
    const r = rnd();
    if (r < 0.04) { abs.push([uid(), p.id, ds, pick(['Sëmurje', 'Sëmurje', 'Arsye personale', 'Pa arsye']), null, p.loc, `${day(d)} 09:00:00`]); continue; }
    if (r < 0.09) continue; // rest day / off shift
    const second = p.group && (groups.find((g) => g.id === p.group).value === 'Pas-Dite');
    const start = second ? 14 * 60 : 7 * 60;
    const lateBy = chance(0.12) ? 3 + Math.floor(rnd() * 25) : Math.floor(rnd() * 4);
    const entry = start + lateBy - 2;
    const leftEarly = chance(0.04);
    const exit = start + 8 * 60 + (leftEarly ? -(30 + Math.floor(rnd() * 90)) : Math.floor(rnd() * 20));
    att.push([uid(), p.id, ds, time(entry), time(start + 4 * 60), time(start + 4 * 60 + 30), time(exit), p.loc, `${day(d)} ${time(entry)}`]);
    if (lateBy > 5) late.push([uid(), p.id, ds, time(start).slice(0, 5), time(entry).slice(0, 5), lateBy, second ? shiftBy['Pas-Dite'] : shiftBy['Para-Dite'], p.loc, `${day(d)} ${time(entry)}`]);
    if (leftEarly) early.push([uid(), p.id, ds, time(start).slice(0, 5), time(exit).slice(0, 5), exit - entry, second ? shiftBy['Pas-Dite'] : shiftBy['Para-Dite'], p.loc, `${day(d)} ${time(exit)}`]);
    if (chance(0.015)) ot.push([uid(), p.id, ds, 'ore_shtes', 1 + Math.floor(rnd() * 3), p.loc, `${day(d)} 21:00:00`]);
  }
}
await bulk('attendance', ['id', 'employee', 'date', 'entry_time', 'break_start', 'break_end', 'exit_time', 'location', 'created'], att);
await bulk('absences', ['id', 'employee', 'date', 'type', 'description', 'location', 'created'], abs);
await bulk('late_arrivals', ['id', 'employee', 'date', 'shift_start', 'arrival_time', 'minutes_late', 'scheduled_shift', 'location', 'created'], late);
await bulk('early_departures', ['id', 'employee', 'date', 'shift_start', 'departure_time', 'hours_worked', 'scheduled_shift', 'location', 'created'], early);
await bulk('overtime', ['id', 'employee', 'date', 'type', 'hours', 'location', 'created'], ot);

// 5. leave (past, current, future), requests, balances, remarks, swaps, announcements, holidays
const leave = [], reqs = [], bal = [], rem = [], swaps = [];
const future = (n) => { const d = new Date(today); d.setDate(d.getDate() + n); return d; };
for (const p of active) {
  if (chance(0.45)) {
    const from = future(Math.floor(rnd() * 70) - 20), len = 1 + Math.floor(rnd() * 8), to = new Date(from); to.setDate(to.getDate() + len);
    leave.push([uid(), p.id, pick(['Pushim Vjetor', 'Pushim Vjetor', 'Pushim Vjetor', 'Pushim Pa-Pages']), `${day(from)} 00:00:00`, `${day(to)} 00:00:00`, chance(0.2) ? 'Arsye familjare' : null, from < today ? 'approved' : pick(['approved', 'approved', 'pending', 'pending', 'rejected']), p.group, p.loc, `${day(today)} 08:00:00`]);
  }
  if (chance(0.12)) reqs.push([uid(), p.id, pick(['Takim', 'Tjetër']), pick(['Takim me menaxherin', 'Kërkesë për dokument', 'Pyetje për orarin']), pick(['pending', 'pending', 'approved', 'rejected']), `${day(future(Math.floor(rnd() * 14)))} 00:00:00`, pick(['09:00', '10:30', '12:00', '16:00']), p.loc, `${day(today)} 09:00:00`]);
  if (chance(0.15)) bal.push([uid(), p.id, pick(['plus', 'plus', 'minus']), (Math.round(rnd() * 400) / 10 + 5).toFixed(2), `${day(future(-Math.floor(rnd() * 40)))} 00:00:00`, pick(['Teprica', 'Shpërblim', 'Avans', 'Zbritje']), p.loc, `${day(today)} 20:00:00`]);
  if (chance(0.05)) rem.push([uid(), p.id, pick(['Vonesë e përsëritur', 'Mungesë pa lajmërim', 'Sjellje me klientin', 'Falënderim nga klienti']), 'active', p.loc, `${day(future(-Math.floor(rnd() * 30)))} 10:00:00`]);
}
for (let i = 0; i < 90; i++) {
  const a = pick(active), b = pick(active.filter((x) => x.loc === a.loc && x.id !== a.id));
  if (b) swaps.push([uid(), a.id, b.id, `${day(future(Math.floor(rnd() * 30) - 10))} 00:00:00`, pick(['approved', 'pending', 'pending']), 'colleague', shiftBy['Para-Dite'], shiftBy['Pas-Dite'], a.loc, `${day(today)} 10:00:00`]);
}
await bulk('leave_requests', ['id', 'employee', 'type', 'start_date', 'end_date', 'description', 'status', 'employee_group', 'location', 'created'], leave);
await bulk('requests', ['id', 'employee', 'type', 'details', 'status', 'req_date', 'req_time', 'location', 'created'], reqs);
await bulk('balances', ['id', 'employee', 'type', 'amount', 'date', 'note', 'location', 'created'], bal);
await bulk('remarks', ['id', 'employee', 'text', 'status', 'location', 'created'], rem);
await bulk('shift_swaps', ['id', 'requester', 'recipient', 'swap_date', 'status', 'mode', 'from_shift', 'to_shift', 'location', 'created'], swaps);
await bulk('announcements', ['id', 'title', 'body', 'is_popup', 'visible', 'location', 'created'], [
  [uid(), 'Orari i festave', 'Gjatë festave orari do të jetë 08:00 - 20:00.', 1, 1, SHARED, `${day(today)} 09:00:00`],
  [uid(), 'Inventari mujor', 'Inventari bëhet të shtunën e fundit të muajit.', 0, 1, SHARED, `${day(future(-3))} 09:00:00`],
  [uid(), 'Uniforma e re', 'Uniformat e reja ndahen te menaxheri i pikës.', 0, 1, SHARED, `${day(future(-9))} 09:00:00`],
  [uid(), 'Njoftim i vjetër', 'Ky njoftim është fshehur.', 0, 0, SHARED, `${day(future(-40))} 09:00:00`],
]);
const [[hol]] = await q('SELECT COUNT(*) n FROM holidays');
if (!hol.n) await bulk('holidays', ['id', 'name', 'date', 'repeat', 'repeat_type', 'holiday_type', 'location', 'created'], [
  [uid(), 'Dita e Pavarësisë', '2026-02-17 00:00:00', 1, 'yearly', 'official', SHARED, '2026-01-01 00:00:00'],
  [uid(), 'Dita e Flamurit', '2026-11-28 00:00:00', 1, 'yearly', 'official', SHARED, '2026-01-01 00:00:00'],
  [uid(), 'Viti i Ri', '2027-01-01 00:00:00', 1, 'yearly', 'official', SHARED, '2026-01-01 00:00:00'],
]);
await db.end();
console.log(`${name}: ${people.length} perdorues (${staff.length} punonjes/arkatare), ${att.length} regjistrime prezence, ${abs.length} mungesa, ${late.length} vonesa, ${leave.length} pushime, ${reqs.length} kerkesa, ${swaps.length} ndrrime turni.`);
