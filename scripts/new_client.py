"""Make a new client (owner, 2026-10-21): its own GitHub repo from the template, its first Release and its Setup zip.

    python "Setup/Claude Studio/scripts/new_client.py" Urban [1.0.0]

1. creates rogest-network/HRSystem-Urban (private) from rogest-network/HRSystem-Template (run template.py first / after code changes),
2. publishes Release v<ver> there with the app zip (Setup/Versions/V<ver>/HRSystem-<ver>.zip),
3. writes Setup/Clients/Urban/HRSystemV<ver>-Urban-Setup.zip: the thin setup, client.json pointing to that repo.

On the client's computer: unzip, run Install.bat, paste the read-only GitHub token of THAT repo (never in chat).
"""
import os, re, subprocess, sys, time

import pack

OWNER = 'rogest-network'
TEMPLATE = f'{OWNER}/HRSystem-Template'


def gh(*args, check=True):
    r = subprocess.run(['gh', *args], capture_output=True, text=True, encoding='utf-8')
    if check and r.returncode != 0:
        sys.exit(f"gh {' '.join(args[:3])} failed: {(r.stderr or r.stdout).strip()}")
    return r.stdout.strip()


def main():
    if len(sys.argv) not in (2, 3) or not re.fullmatch(r'[A-Za-z0-9-]+', sys.argv[1]):
        sys.exit(__doc__)
    name = sys.argv[1]
    ver = sys.argv[2] if len(sys.argv) == 3 else None
    if ver is None:
        import json
        ver = json.load(open(os.path.join(pack.SRC, 'package.json'), encoding='utf-8'))['version']
    repo = f'{OWNER}/HRSystem-{name}'
    zip_app = os.path.join(pack.version_dir(ver), pack.app_zip_name(ver))
    if not os.path.exists(zip_app):
        sys.exit(f'Run pack.py {ver} first: {zip_app} is missing.')

    if subprocess.run(['gh', 'repo', 'view', repo], capture_output=True).returncode == 0:
        print('Repo exists already:', repo)
    else:
        gh('repo', 'create', repo, '--private', '--template', TEMPLATE)
        print('Repo created:', repo)
        for _ in range(20):  # GitHub copies the template files a few seconds after the repo exists
            if subprocess.run(['gh', 'api', f'repos/{repo}/contents/package.json', '--silent'], capture_output=True).returncode == 0 or \
               subprocess.run(['gh', 'api', f'repos/{repo}/contents/Source/package.json', '--silent'], capture_output=True).returncode == 0:
                break
            time.sleep(3)

    if subprocess.run(['gh', 'release', 'view', f'v{ver}', '-R', repo], capture_output=True).returncode == 0:
        print(f'Release v{ver} exists already in', repo)
    else:
        gh('release', 'create', f'v{ver}', zip_app, '-R', repo, '--target', 'main', '--title', f'V{ver}',
           '--notes', f'First release of {name} (the template V{ver}).')
        print(f'Release v{ver} published in', repo)

    out_dir = os.path.join(pack.SETUP, 'Clients', name)
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f'HRSystemV{ver}-{name}-Setup.zip')
    pack.thin_zip(out, repo)
    print('Setup zip:', out)


if __name__ == '__main__':
    main()
