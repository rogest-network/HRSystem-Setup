"""Publish the clean template repository (owner, 2026-10-21): GitHub rogest-network/HRSystem-Template.

    python "Setup/Claude Studio/scripts/template.py"

Takes the tree of origin/main of the Regina repo (the code), removes what belongs to Regina only (her test environment scripts,
the rebuild notes, the VPS notes, the CI file), and commits the result as one new commit of the template repo. Creates the repo
(private, marked as a GitHub template) the first time. A client repo is then made from it with new_client.py.
"""
import io, os, shutil, subprocess, sys, tarfile, tempfile

STUDIO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'Claude Studio'))
TEMPLATE = 'rogest-network/HRSystem-Template'
REGINA_ONLY = ['.github', 'scripts/pc-test', 'scripts/vps', 'docs/rebuild', 'docs/TEST_ENV_PC.md', 'docs/DEPLOYMENT_VPS.md',
               'docs/AUDIT-2026-10-18.md', 'docs/_organize_map.json', 'CHANGELOG.md', 'manager/instances.json']


def run(*cmd, cwd=None, check=True):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding='utf-8')
    if check and r.returncode != 0:
        sys.exit(f"{' '.join(cmd[:3])} failed: {(r.stderr or r.stdout).strip()}")
    return r.stdout.strip()


def main():
    run('git', 'fetch', '-q', 'origin', cwd=STUDIO)
    work = tempfile.mkdtemp(prefix='hrsystem-template-')
    try:
        content = os.path.join(work, 'content')
        os.makedirs(content)
        tar = subprocess.run(['git', 'archive', '--format=tar', 'origin/main'], cwd=STUDIO, capture_output=True, check=True).stdout
        tarfile.open(fileobj=io.BytesIO(tar)).extractall(content)
        for rel in REGINA_ONLY:
            target = os.path.join(content, rel)
            if os.path.isdir(target):
                shutil.rmtree(target)
            elif os.path.exists(target):
                os.remove(target)

        exists = subprocess.run(['gh', 'repo', 'view', TEMPLATE], capture_output=True).returncode == 0
        if not exists:
            run('gh', 'repo', 'create', TEMPLATE, '--private', '--description', 'HRSystem template: every new client repo is made from this')
        repo = os.path.join(work, 'repo')
        run('gh', 'repo', 'clone', TEMPLATE, repo)
        run('git', 'checkout', '-B', 'main', cwd=repo)
        for name in os.listdir(repo):
            if name != '.git':
                p = os.path.join(repo, name)
                shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
        for name in os.listdir(content):
            src, dst = os.path.join(content, name), os.path.join(repo, name)
            shutil.copytree(src, dst) if os.path.isdir(src) else shutil.copy2(src, dst)
        run('git', 'add', '-A', cwd=repo)
        if not run('git', 'status', '--porcelain', cwd=repo):
            print('Template is already up to date.')
        else:
            sha = run('git', 'rev-parse', '--short', 'origin/main', cwd=STUDIO)
            run('git', 'commit', '-q', '-m', f'HRSystem template (from Regina main {sha})', cwd=repo)
            run('git', 'push', '-q', '-u', 'origin', 'main', cwd=repo)
            print('Template updated from Regina main', sha)
        run('gh', 'repo', 'edit', TEMPLATE, '--template')
    finally:
        def force(fn, path, exc):
            os.chmod(path, 0o700)
            fn(path)
        shutil.rmtree(work, onerror=force)


if __name__ == '__main__':
    main()
