"""Build the release zips of a version from Source/.

    python "Setup/Claude Studio/scripts/pack.py" 2.0.1

Writes Setup/Versions/V<x.y.z>/HRSystem-<ver>.zip (the app: the GitHub Release asset every installation downloads) and
-Setup.zip (the thin Windows setup: installer/ scripts + client.json; it downloads the app from the client's repo) (a build with a
-N suffix, e.g. 2.15.3-1, goes in the sub-folder Setup/Versions/V<x.y.z>/V<ver>/), then puts a copy of the Setup zip in Setup/
(older copies in Setup/ are removed only when Versions/ has the same file).
The client copy (Regina Center SHPK/reginaV<ver>.zip) is made by hand; see README.md (root).
Run `npm run build` and the tests first: dist/ and node_modules/ are not shipped (every installation builds).
"""
import json
import filecmp, os, re, shutil, sys, zipfile

SETUP = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))   # Setup/scripts/.. = Setup (the HRSystem-Setup repo)
SRC = os.path.join(SETUP, 'Claude Studio', 'Source')
VERSIONS = os.path.join(SETUP, 'Versions')
TOP = ['.env.example', 'ARCHITECTURE.md', 'DatabaseSchema.sql', 'index.html', 'jsconfig.json', 'package-lock.json',
       'package.json', 'postcss.config.js', 'server.mjs', 'tailwind.config.js', 'vite.config.js']
# tests/ stays out (V2.9.0): it needs a local MySQL and is never run on the server; it only made the upload bigger.
FOLDERS = ['migrations', 'public', 'server', 'src']
# The Windows setup (one setup, the updater, the SQL importer) lives in Claude Studio/installer/ (in git); its files go to the
# root of the LocalSetup zip. (Until 2026-10-21 they were carried from the previous LocalSetup zip.)
INSTALLER_DIR = os.path.join(SETUP, 'installer')
# The setup zip shows only three files (owner, 2026-10-21): Install, Uninstall, Dashboard; everything else is in its files/ folder.
ROOT_BATS = ['Install.bat', 'Uninstall.bat', 'Dashboard.bat']
INSTALLER = ['installer.ps1', 'wizard.ps1', 'hr-common.ps1', 'hr-links.ps1', 'updater.ps1', 'update.bat', 'sql-import.ps1', 'sql-import.bat', 'uninstall.ps1',
             'uninstall-wizard.ps1', 'LEXO-ME-PARE.txt']


# The dashboard (Claude Studio/manager/) travels in the thin setup zip and is installed next to the app (owner, 2026-10-21).
MANAGER_DIR = os.path.join(SETUP, 'Claude Studio', 'manager')
MANAGER = ['server.mjs', 'public/index.html', 'README.md']


def app_zip_name(ver):
    parts = [int(n) for n in re.findall(r'\d+', ver)][:3]
    if parts < [1, 0, 2]:
        sys.exit('Versions before 1.0.2 are archived and are not packed again.')
    return f'HRSystem-{ver}.zip'


def version_key(name):
    return [int(n) for n in re.findall(r'\d+', name)]


def source_files():
    files = list(TOP)
    for folder in FOLDERS:
        for root, dirs, names in os.walk(os.path.join(SRC, folder)):
            dirs.sort()
            for name in sorted(names):
                if name.startswith('.baseline') or name == '.last-run.json':
                    continue
                files.append(os.path.relpath(os.path.join(root, name), SRC).replace(os.sep, '/'))
    return files


def version_dir(ver):
    """Versions/V<x.y.z>/ holds a release; its -1, -2 ... builds are sub-folders V<x.y.z>-N/ of it."""
    base = re.match(r'\d+\.\d+\.\d+', ver).group(0)
    return os.path.join(VERSIONS, f'V{base}') if ver == base else os.path.join(VERSIONS, f'V{base}', f'V{ver}')


def write(path, prefix, files, installer=False):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for f in files:
            z.write(os.path.join(SRC, f), prefix + f)
        if installer:
            for name in INSTALLER:
                z.write(os.path.join(INSTALLER_DIR, name), name)


def thin_zip(path, repo, channel='stable', app=False):
    """The setup zip: Install/Uninstall/Dashboard + files/ with the scripts, the dashboard and the app (files/HRSystem/). client.json names the
    client's GitHub repository, used for updates (update.bat, the dashboard)."""
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name in ROOT_BATS:
            z.write(os.path.join(INSTALLER_DIR, name), name)
        for name in INSTALLER:
            z.write(os.path.join(INSTALLER_DIR, name), 'files/' + name)
        for rel in MANAGER:
            z.write(os.path.join(MANAGER_DIR, rel), 'files/manager/' + rel)
        # The setup holds NO program (owner, 2026-10-23): at install time the installer takes the newest Release of the Template repo (or of the client's repo when a
        # token is given). A change of the base program is therefore made in the Template repo only, never here.
        if app:  # legacy switch, off: pack.py never bundles the program any more
            for f in source_files():
                z.write(os.path.join(SRC, f), 'files/HRSystem/' + f)
        z.writestr('files/client.json', json.dumps({'repo': repo, 'channel': channel}, indent=2) + chr(10))


def bootstrap_zip():
    """Setup/HRS-Setup.zip: the small file kept on the USB stick (owner, 2026-10-22). It never changes: its Install.bat downloads the NEWEST setup zip from the
    private repo rogest-network/HRSystem-Setup and opens it. If Setup/Claude Studio/secrets/setup-token.txt exists (a read-only fine-grained GitHub token for that
    repo, kept only on this PC, never in git) it is put inside the zip as setup-token.txt, so the PCs never ask for it."""
    boot = os.path.join(INSTALLER_DIR, 'bootstrap')
    out = os.path.join(SETUP, 'HRS-Setup.zip')
    token = os.path.join(SETUP, 'Claude Studio', 'secrets', 'setup-token.txt')
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        z.write(os.path.join(boot, 'Install.bat'), 'Install.bat')
        z.write(os.path.join(boot, 'bootstrap.ps1'), 'files/bootstrap.ps1')
        # A full copy of the setup (no program) travels inside, so the USB works with no token and no internet; the newest setup is used when it can be downloaded.
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            thin = os.path.join(tmp, 'setup.zip')
            thin_zip(thin, '')
            with zipfile.ZipFile(thin) as t:
                for info in t.infolist():
                    z.writestr('setup/' + info.filename, t.read(info.filename))
        if os.path.exists(token):
            z.write(token, 'setup-token.txt')
    print('HRS-Setup.zip ->', out, '(token inside)' if os.path.exists(token) else '(no token inside: it asks nothing, the token is optional in the setup window)')


def main():
    if '--bootstrap' in sys.argv[1:]:
        bootstrap_zip()
        return
    # --setup-only: rebuild ONLY the thin Setup zip (Versions/V<x>/ and the copy in Setup/) after an installer/dashboard change; the app zip is not touched.
    setup_only = '--setup-only' in sys.argv
    args = [a for a in sys.argv[1:] if a not in ('--setup-only', '--publish')]
    if len(args) != 1:
        sys.exit(__doc__)
    ver = args[0].lstrip('vV')
    files = source_files()
    out = version_dir(ver)
    os.makedirs(out, exist_ok=True)
    if setup_only:
        thin = os.path.join(out, f'HRSystemV{ver}-Setup.zip')
        thin_zip(thin, '')
        print(f'V{ver}: setup zip only ->', thin)   # only in Versions/ (Setup/ holds just HRS-Setup.zip)
        if '--publish' in sys.argv[1:]:
            # The Setup zip goes to the private repo rogest-network/HRSystem-Setup as the asset of Release v<ver> (owner, 2026-10-22: a new PC downloads it from
            # there instead of a USB stick). The release is created once; a rebuild replaces its asset.
            import subprocess
            repo = 'rogest-network/HRSystem-Setup'
            have = subprocess.run(['gh', 'release', 'view', f'v{ver}', '-R', repo], capture_output=True).returncode == 0
            if have:
                cmd = ['gh', 'release', 'upload', f'v{ver}', thin, '--clobber', '-R', repo]
            else:
                cmd = ['gh', 'release', 'create', f'v{ver}', thin, '-R', repo, '--target', 'main', '--title', f'Setup V{ver}', '--notes', 'Setup zip: Install.bat (folder, first owner, business), Uninstall.bat, Dashboard.bat.']
            subprocess.run(cmd, check=True)
            print('published to', repo)
        return
    # The app zip is HRSystem-<version>.zip (owner, 2026-10-22).
    app_zip = os.path.join(out, app_zip_name(ver))
    write(app_zip, '', files)
    thin = os.path.join(out, f'HRSystemV{ver}-Setup.zip')
    thin_zip(thin, '')   # no repository is named in the setup (owner, 2026-10-22): it comes from the GitHub token

    for name in os.listdir(SETUP):
        m = re.fullmatch(r'(?:ReginaHR-|HRSystem)(V[\w.-]+?)-(LocalSetup|Setup)\.zip', name)
        if not m or m.group(1) == f'V{ver}':
            continue
        kept = os.path.join(version_dir(m.group(1)[1:]), name)
        if os.path.exists(kept) and filecmp.cmp(kept, os.path.join(SETUP, name), shallow=False):
            os.remove(os.path.join(SETUP, name))
        else:
            print('kept (no identical copy in Versions/):', name)
    # Setup/ holds only the thin setup (owner, 2026-10-21); the app zip stays in Versions/ (it is the GitHub Release asset).
    print(f'V{ver}: {len(files)} files ->', out)


if __name__ == '__main__':
    main()
