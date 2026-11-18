# Builds the single catch-up script for EXISTING databases from DatabaseSchema.sql:
# every table (CREATE TABLE IF NOT EXISTS, with its keys), every column (ADD COLUMN IF NOT EXISTS),
# every index (ADD [UNIQUE] INDEX IF NOT EXISTS), plus the data steps the app no longer does itself
# (old manager permissions -> today's keys). Safe to run more than once. Only for databases older than V2.5 (history).
# usage: python catchup_sql.py <version> <output.sql>   (reads ../Source/DatabaseSchema.sql)
# Regenerate it whenever DatabaseSchema.sql changes; ship it in Setup/Versions/V<x>/.
import re, sys, os
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Claude Studio', 'Source')
schema = open(os.path.join(SRC, 'DatabaseSchema.sql'), encoding='utf-8').read()
version = sys.argv[1]
out_path = sys.argv[2]

# today's permission keys, straight from the server config
cfg = open(os.path.join(SRC, 'server', 'core', 'config.mjs'), encoding='utf-8').read()
m = re.search(r'export const MANAGER_PERMISSION_KEYS = \[(.*?)\];', cfg, re.S)
keys = re.findall(r"'([a-z_]+)'", m.group(1))
LEGACY = {
    'employees_manage': ['employees_add', 'employees_edit', 'employees_toggle'],
    'attendance_manage': ['attendance_add', 'attendance_edit'],
    'evidence_manage': ['evidence_add'],
    'balances_manage': ['balances_add', 'balances_edit'],
    'requests_manage': ['requests_edit'],
    'leaves_manage': ['leaves_add', 'leaves_edit'],
    'shift_swaps_manage': ['shift_swaps_edit'],
    'remarks_manage': ['remarks_add', 'remarks_edit'],
    'announcements_manage': ['announcements_add', 'announcements_edit'],
}

tables = {}
for t, body in re.findall(r'CREATE TABLE `([a-z_]+)` \((.*?)\n\) ENGINE', schema, re.S):
    cols, inline_keys = [], []
    for line in body.strip().split('\n'):
        line = line.strip().rstrip(',')
        cm = re.match(r'`([a-z_0-9]+)` (.+)$', line)
        if cm:
            cols.append((cm.group(1), cm.group(2)))
        elif re.match(r'(PRIMARY KEY|UNIQUE KEY|KEY) ', line):
            # Keys written inside CREATE TABLE (V3.0.0: schema_migrations, audit_log with AUTO_INCREMENT).
            inline_keys.append(line)
    tables[t] = {'cols': cols, 'keys': inline_keys}
for t, block in re.findall(r'ALTER TABLE `([a-z_]+)`\n((?:  ADD .*\n?)+)', schema):
    for line in block.strip().split('\n'):
        line = line.strip().rstrip(',;')
        if t in tables:
            tables[t]['keys'].append(line[len('ADD '):])
engine = 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'

L = []
w = L.append
w(f'-- Regina.HR {version} | ONE-TIME SQL (catch-up) | old databases only')
w('-- For an EXISTING database of ANY earlier version. Run it ONCE, BEFORE uploading the new zip:')
w('--   phpMyAdmin -> click the database (NOT information_schema) -> SQL -> paste -> Go.')
w('-- It replaces every earlier one-time script (Pajisjet, V1.4, V2, V2.1, V2.2): from this version on the')
w('-- app no longer works around a database that misses them, so this one brings it to today\'s schema.')
w('-- Safe to run again and again (IF NOT EXISTS); it never deletes data. A NEW install uses DatabaseSchema.sql.')
w('--   1. missing tables are created, 2. missing columns added, 3. missing indexes added,')
w('--   4. manager permissions are written in today\'s form (the same rights as before, see the end).')
w('')
w('SET NAMES utf8mb4;')
w('')
w('-- 1. Tables')
for t, spec in tables.items():
    defs = [f'  `{c}` {d}' for c, d in spec['cols']] + [f'  {k}' for k in spec['keys']]
    w(f'CREATE TABLE IF NOT EXISTS `{t}` (\n' + ',\n'.join(defs) + f'\n) {engine};')
w('')
w('-- 2. Columns')
for t, spec in tables.items():
    for c, d in spec['cols']:
        w(f'ALTER TABLE `{t}` ADD COLUMN IF NOT EXISTS `{c}` {d};')
w('')
w('-- 3. Indexes')
for t, spec in tables.items():
    for k in spec['keys']:
        km = re.match(r'(UNIQUE KEY|KEY) `([a-z_0-9]+)` (\(.*\))$', k)
        if km:
            kind = 'UNIQUE INDEX' if km.group(1) == 'UNIQUE KEY' else 'INDEX'
            w(f'ALTER TABLE `{t}` ADD {kind} IF NOT EXISTS `{km.group(2)}` {km.group(3)};')
w('')
w('-- Company name on the resignation letter (only when still empty; can be changed at /developer).')
w("INSERT INTO `hrsystem_developer_settings` (`setting_key`, `setting_value`) VALUES ('company_name', 'Regina Center SH.P.K.')")
w("ON DUPLICATE KEY UPDATE `setting_value` = IF(`setting_value` = '', VALUES(`setting_value`), `setting_value`);")
w('')
w('-- 4. Manager permissions: a JSON list of today\'s keys. Earlier versions also read')
w('--    * an empty value as "every permission" (managers from before permissions existed),')
w('--    * a {"key": true} object, and old keys such as "employees_manage".')
w('--    These become the same rights written the new way.')
full = '[' + ','.join(f'"{k}"' for k in keys) + ']'
w(f"UPDATE `users` SET `manager_permissions` = '{full}'")
w("  WHERE `role` = 'menaxheri' AND (`manager_permissions` IS NULL OR TRIM(`manager_permissions`) = '');")
all_keys = keys + list(LEGACY)
parts = ', '.join(f"IF(JSON_VALUE(`manager_permissions`, '$.{k}') = 'true', '\"{k}\"', NULL)" for k in all_keys)
w("UPDATE `users` SET `manager_permissions` = CONCAT('[', CONCAT_WS(',', " + parts + "), ']')")
w("  WHERE `role` = 'menaxheri' AND JSON_VALID(`manager_permissions`) AND JSON_TYPE(`manager_permissions`) = 'OBJECT';")
for old, new in LEGACY.items():
    repl = ','.join(f'"{k}"' for k in new)
    w(f"UPDATE `users` SET `manager_permissions` = REPLACE(`manager_permissions`, '\"{old}\"', '{repl}') WHERE `manager_permissions` LIKE '%\"{old}\"%';")
open(out_path, 'w', encoding='utf-8', newline='\n').write('\n'.join(L) + '\n')
print(len(tables), 'tables,', sum(len(s['cols']) for s in tables.values()), 'columns,', sum(len(s['keys']) for s in tables.values()), 'keys,', len(keys), 'permission keys')
