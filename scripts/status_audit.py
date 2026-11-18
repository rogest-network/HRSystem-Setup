"""Status and audit report of the whole project (owner, 2026-10-24). READ ONLY: changes nothing, pushes nothing. Setup only: never copied into any repo.

    python "Setup/Claude Studio/scripts/status_audit.py"

Prints OK / WARN / FAIL lines for:
  1. one version number everywhere (Source/package.json, the lock, README, Versions/README.txt, the app zip inside Versions/V<x>/);
  2. local storage (Setup/Versions/V<x>/ has the app zip, the Setup zip, the Template zip; the one-time SQL when the version has a migration);
  3. GitHub (Regina: every local version has its Release and the asset has the local size; Template: ONE Release with the current number;
     Setup repo: newest Release; Dashboard: the version in manager/server.mjs is the newest commit and has a tag);
  4. Source against the released Regina main (which files are changed and NOT released yet);
  5. code hygiene (files over 800 lines, migrations against the schema list).
Needs `gh` signed in (read-only calls). It is the automatic half of the audit: the manual half is in HANDBOOK.md section 8.
"""
import filecmp, io, json, os, re, subprocess, sys, tarfile, tempfile, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SETUP = os.path.abspath(os.path.join(HERE, '..'))                 # Setup/ (the HRSystem-Setup repo)
STUDIO = os.path.join(SETUP, 'Claude Studio')                      # the Regina clone
ROOT = os.path.abspath(os.path.join(SETUP, '..'))
SRC = os.path.join(STUDIO, 'Source')
VERSIONS = os.path.join(SETUP, 'Versions')
ORG = 'rogest-network'
results = {'OK': 0, 'WARN': 0, 'FAIL': 0}


def say(level, text):
    results[level] += 1
    print(f'{level:<5} {text}')


def sh(*cmd, cwd=None):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding='utf-8')
    return r.returncode, (r.stdout or '').strip()


def gh_json(*args):
    code, out = sh('gh', *args)
    try:
        return json.loads(out) if code == 0 and out else None
    except ValueError:
        return None


def read(path):
    try:
        return open(path, encoding='utf-8', errors='replace').read()
    except OSError:
        return ''


def vkey(v):
    return tuple(int(x) for x in re.findall(r'\d+', v)[:3])


def check_versions():
    print('\n== 1. One version number everywhere')
    ver = json.loads(read(os.path.join(SRC, 'package.json')))['version']
    lock = read(os.path.join(SRC, 'package-lock.json'))
    n = len(re.findall(r'"version": "' + re.escape(ver) + '"', lock[:600]))
    say('OK' if n >= 2 else 'FAIL', f'Source/package.json = {ver}; package-lock.json top has it {n}x (needs 2)')
    for name, path, pat in [('manual/README.md', os.path.join(STUDIO, 'manual', 'README.md'), 'Current release: **V' + ver + '**'),
                            ('manual/VERSIONS.txt', os.path.join(STUDIO, 'manual', 'VERSIONS.txt'), 'V' + ver)]:
        say('OK' if pat in read(path) else 'FAIL', f'{name} names V{ver}')
    vdir = os.path.join(VERSIONS, 'V' + ver)
    zp = os.path.join(vdir, f'HRSystem-{ver}.zip')
    if os.path.exists(zp):
        inside = json.loads(zipfile.ZipFile(zp).read('package.json'))['version']
        say('OK' if inside == ver else 'FAIL', f'{os.path.relpath(zp, ROOT)} contains version {inside}')
    else:
        say('FAIL', f'missing {os.path.relpath(zp, ROOT)}')
    return ver


def check_local(ver):
    print('\n== 2. Local storage (Setup/Versions)')
    folders = sorted([d for d in os.listdir(VERSIONS) if re.fullmatch(r'V\d+\.\d+\.\d+', d)], key=vkey)
    for d in folders:
        v = d[1:]
        base = os.path.join(VERSIONS, d)
        names = set(os.listdir(base))
        app = f'HRSystem-{v}.zip' in names or f'HRSystemV{v}-Hostinger.zip' in names
        setup = f'HRSystemV{v}-Setup.zip' in names
        tpl = os.path.exists(os.path.join(base, 'Template', f'HRSystem-{v}.zip'))
        miss = [t for t, ok in [('app zip', app), ('Setup zip', setup)] if not ok]
        if vkey(v) >= (1, 0, 3) and not tpl:
            miss.append('Template zip')
        say('OK' if not miss else 'WARN', f'{d}: ' + ('complete' if not miss else 'missing ' + ', '.join(miss)))
    cur = os.path.join(VERSIONS, 'V' + ver)
    say('OK' if os.path.exists(os.path.join(cur, 'DatabaseSchema.sql')) else 'WARN', f'V{ver} keeps its DatabaseSchema.sql')


def check_github(ver):
    print('\n== 3. GitHub')
    rel = gh_json('release', 'list', '-R', f'{ORG}/HRSystem-ReginaCenter', '--limit', '50', '--json', 'tagName,isLatest')
    if rel is None:
        say('WARN', 'cannot read the Regina repo (gh not signed in?)')
        return
    tags = {r['tagName']: r for r in rel}
    latest = [r['tagName'] for r in rel if r['isLatest']]
    say('OK' if latest == ['v' + ver] else 'FAIL', f'Regina: Latest Release = {latest}, Source = v{ver}')
    # Since 2026-11-18 (owner) every client repo keeps EVERY Release, never delete one. v1.0.1-v1.0.15 were
    # deleted on 2026-11-07 under the old "last five" rule and exist on this PC only, so the check starts at 1.0.16.
    keep = [d for d in sorted([d for d in os.listdir(VERSIONS) if re.fullmatch(r'V\d+\.\d+\.\d+', d)], key=vkey)
            if vkey(d) >= vkey('V1.0.16')]
    say('OK', f'Regina: {len(tags)} Release(s) on GitHub (the rule: keep every version)')
    for d in keep:
        v = d[1:]
        if 'v' + v not in tags:
            say('WARN', f'Regina: no Release v{v}')
            continue
        info = gh_json('release', 'view', 'v' + v, '-R', f'{ORG}/HRSystem-ReginaCenter', '--json', 'assets')
        sizes = {a['name']: a['size'] for a in (info or {}).get('assets', [])}
        local = [os.path.join(VERSIONS, d, n) for n in (f'HRSystem-{v}.zip', f'HRSystemV{v}-Hostinger.zip')]
        local = next((p for p in local if os.path.exists(p)), None)
        if not local:
            say('WARN', f'Regina v{v}: no local zip to compare')
        elif sizes.get(os.path.basename(local)) == os.path.getsize(local):
            say('OK', f'Regina v{v}: asset {os.path.basename(local)} has the local size')
        else:
            say('FAIL', f'Regina v{v}: asset {sizes} differs from local {os.path.basename(local)} ({os.path.getsize(local)})')
    t = gh_json('release', 'list', '-R', f'{ORG}/HRSystem-Template', '--limit', '50', '--json', 'tagName')
    tn = [r['tagName'] for r in (t or [])]
    say('OK' if tn == ['v' + ver] else 'FAIL', f'Template: Releases = {tn} (must be exactly [v{ver}])')
    tzip = os.path.join(VERSIONS, 'V' + ver, 'Template', f'HRSystem-{ver}.zip')
    ti = gh_json('release', 'view', 'v' + ver, '-R', f'{ORG}/HRSystem-Template', '--json', 'assets') if tn else None
    if ti and os.path.exists(tzip):
        sz = {a['name']: a['size'] for a in ti['assets']}.get(f'HRSystem-{ver}.zip')
        say('OK' if sz == os.path.getsize(tzip) else 'FAIL', f'Template asset size {sz} vs local {os.path.getsize(tzip)}')
    s = gh_json('release', 'list', '-R', f'{ORG}/HRSystem-Setup', '--limit', '5', '--json', 'tagName,isLatest')
    say('OK' if s else 'WARN', 'Setup repo newest Release: ' + (', '.join(r['tagName'] for r in s if r['isLatest']) if s else 'unreadable'))
    dv = re.search(r"DASH_VERSION = '([^']+)'", read(os.path.join(STUDIO, 'manager', 'server.mjs')))
    dv = dv.group(1) if dv else '?'
    code, msg = sh('gh', 'api', f'repos/{ORG}/HRSystem-Dashboard/commits?per_page=1', '--jq', '.[0].commit.message|split("\n")[0]')
    say('OK' if re.search(rf'(^|[\sv]){re.escape(dv)}\b', msg) else 'FAIL',f'Dashboard in manager/ = v{dv}; newest commit on GitHub: "{msg[:70]}"')
    code, dtags = sh('gh', 'api', f'repos/{ORG}/HRSystem-Dashboard/tags', '--jq', '.[].name')
    say('OK' if f'v{dv}' in dtags.split() else 'WARN', f'Dashboard tags: {dtags.split() or "none"} (a tag v<version> is the way back)')


def check_unreleased():
    print('\n== 4. Source against the released Regina main')
    sh('git', 'fetch', '-q', 'origin', cwd=STUDIO)
    code, _ = sh('git', 'rev-parse', '--verify', 'origin/main', cwd=STUDIO)
    if code != 0:
        say('WARN', 'origin/main not found')
        return
    tar = subprocess.run(['git', 'archive', '--format=tar', 'origin/main', 'Source'], cwd=STUDIO, capture_output=True).stdout
    tmp = tempfile.mkdtemp(prefix='hrsystem-audit-')
    tarfile.open(fileobj=io.BytesIO(tar)).extractall(tmp)
    # .impeccable = the design skill's hook cache (never shipped: pack.py and the release mirror leave it out)
    skip = {'node_modules', 'dist', '.vite', '.env', '.baseline.sql', '.baseline-ids.json', '.last-run.json', '.impeccable'}
    diffs = []

    def walk(a, b, rel=''):
        cmp = filecmp.dircmp(a, b)
        for n in cmp.left_only:
            if n not in skip:
                diffs.append('only in Source: ' + rel + n)
        for n in cmp.right_only:
            if n not in skip:
                diffs.append('only released: ' + rel + n)
        for n in cmp.diff_files:
            ta, tb = open(os.path.join(a, n), 'rb').read().replace(b'\r\n', b'\n'), open(os.path.join(b, n), 'rb').read().replace(b'\r\n', b'\n')
            if ta != tb:
                diffs.append('changed: ' + rel + n)
        for n in cmp.common_dirs:
            if n not in skip:
                walk(os.path.join(a, n), os.path.join(b, n), rel + n + '/')
    walk(SRC, os.path.join(tmp, 'Source'))
    say('OK' if not diffs else 'WARN', f'Source differs from released main in {len(diffs)} file(s)' + (' (nothing unreleased)' if not diffs else ' = NOT released yet'))
    for d in diffs[:15]:
        print('        ' + d)
    import shutil
    shutil.rmtree(tmp, ignore_errors=True)


def check_hygiene():
    print('\n== 5. Code hygiene')
    big = []
    for top in ('src', 'server', 'server.mjs'):
        p = os.path.join(SRC, top)
        files = [p] if os.path.isfile(p) else [os.path.join(d, f) for d, _, fs in os.walk(p) for f in fs]
        for f in files:
            if f.endswith(('.js', '.jsx', '.mjs', '.css')):
                n = read(f).count('\n') + 1
                if n > 800 and 'i18n' not in f:   # the translation dictionaries are data tables, one row per text
                    big.append(f'{os.path.relpath(f, SRC)} ({n})')
    say('OK' if not big else 'WARN', 'files over 800 lines: ' + (', '.join(big) if big else 'none'))
    mig = sorted(f[:-4] for f in os.listdir(os.path.join(SRC, 'migrations')) if f.endswith('.sql'))
    schema = read(os.path.join(SRC, 'DatabaseSchema.sql'))
    missing = [m for m in mig if m not in schema]
    say('OK' if not missing else 'FAIL', f'{len(mig)} migrations, all listed in DatabaseSchema.sql' if not missing else f'not in DatabaseSchema.sql: {missing}')
    secrets = [f for f in os.listdir(SRC) if f in ('.env',)]
    say('OK' if not secrets else 'WARN', 'no .env in Source root' if not secrets else '.env present in Source (never ship it)')


if __name__ == '__main__':
    v = check_versions()
    check_local(v)
    check_github(v)
    check_unreleased()
    check_hygiene()
    print(f"\nSummary: {results['OK']} OK, {results['WARN']} WARN, {results['FAIL']} FAIL")
    sys.exit(1 if results['FAIL'] else 0)
