"""Publish a program version to the TEMPLATE repo as a CLEAN build (owner, 2026-10-24). Setup only: never copied into any repo.

THE TEMPLATE REPO HAS ONE RELEASE ONLY (owner, 2026-10-24), carrying the REAL version of the code (owner, 2026-10-24: "rename the template to its own
version"): the same number as the Regina version of the run (v1.0.5 ...). Every run replaces it (the old Release and every other Release and tag of
the repo are deleted, then v<version> is created with the new zip HRSystem-<version>.zip); the app inside says the same number, so the number, the tag
and the zip agree. The code is the code of the Regina version of the same run.

    python "Setup/scripts/template_release.py" --dry-run     # builds and tests nothing, pushes nothing: shows what would change
    python "Setup/scripts/template_release.py"               # commits to HRSystem-Template main and creates its Release v<version>

Run it AFTER the Regina release of the same version (it takes the tree of origin/main of the Regina repo, so `git fetch` happens first).
What makes the template CLEAN (the template only starts new, empty databases, no existing company can break):
  - no migration files (Source/migrations/ keeps only a README: the server needs the folder, an empty one means "nothing to run");
  - DatabaseSchema.sql is the final schema (it already lists every migration in schema_migrations; that stays);
  - tests that need the migration history are removed (tests/migrations-check.mjs, the old schemas), package.json has no test:migrations;
  - what belongs to Regina only (her test-environment scripts, notes, CI) is removed (same list as template.py).
Before publishing, test the tree it builds (see HANDBOOK.md "Template release"): build, unit, contract, server checks need node_modules and MySQL,
so run them on a copy of the tree with the real node_modules linked in (cmd /c mklink /J), then publish.
The zip is HRSystem-<version>.zip, built with pack.py's own writer, and a copy is kept in Setup/Versions/V<version>/Template/.
"""
import io, json, os, shutil, subprocess, sys, tarfile, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SETUP = os.path.abspath(os.path.join(HERE, '..'))                 # Setup/ (the HRSystem-Setup repo)
STUDIO = os.path.join(SETUP, 'Claude Studio')                      # the Regina clone
TEMPLATE = 'rogest-network/HRSystem-Template'
CO_AUTHOR = 'Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>'
REGINA_ONLY = ['manual', 'docs/QA', '.github', 'scripts/pc-test', 'scripts/vps', 'docs/rebuild', 'docs/TEST_ENV_PC.md', 'docs/DEPLOYMENT_VPS.md',
               'docs/AUDIT-2026-10-18.md', 'docs/_organize_map.json', 'CHANGELOG.md', 'manager/instances.json']
GRANT_OLD = "const grant = readFileSync(join(dir, 'migrations', '0005_evidence_edit_permission.sql'), 'utf8').replace(/^--.*$/gm, '').split(';').find((part) => part.includes('UPDATE'));"
GRANT_NEW = ("const grant = \"UPDATE `users` SET `manager_permissions` = JSON_ARRAY_APPEND(`manager_permissions`, '$', 'evidence_edit') WHERE `role` = 'menaxheri' "
             "AND (CASE WHEN JSON_VALID(`manager_permissions`) AND JSON_TYPE(`manager_permissions`) = 'ARRAY' THEN JSON_CONTAINS(`manager_permissions`, '\\\"evidence_add\\\"') "
             "AND NOT JSON_CONTAINS(`manager_permissions`, '\\\"evidence_edit\\\"') ELSE 0 END) = 1\";")


def run(*cmd, cwd=None, check=True):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding='utf-8')
    if check and r.returncode != 0:
        sys.exit(f"{' '.join(cmd[:3])} failed: {(r.stderr or r.stdout).strip()}")
    return r.stdout.strip()


def build_tree(out):
    """The clean template tree of origin/main of the Regina repo, in `out`."""
    run('git', 'fetch', '-q', 'origin', cwd=STUDIO)
    tar = subprocess.run(['git', 'archive', '--format=tar', 'origin/main'], cwd=STUDIO, capture_output=True, check=True).stdout
    tarfile.open(fileobj=io.BytesIO(tar)).extractall(out)
    for rel in REGINA_ONLY:
        p = os.path.join(out, rel)
        shutil.rmtree(p) if os.path.isdir(p) else (os.path.exists(p) and os.remove(p))
    src = os.path.join(out, 'Source')
    mig = os.path.join(src, 'migrations')
    for name in os.listdir(mig):
        os.remove(os.path.join(mig, name))
    with open(os.path.join(mig, 'README.md'), 'w', encoding='utf-8', newline='\n') as f:
        f.write('# migrations\n\nThis template starts every new client on the final `DatabaseSchema.sql`, so it carries no migration history.\n'
                'A client repo made from it adds its own `NNNN_name.sql` files here when it changes its database (see docs/DATABASE.md).\n'
                'The server only compares the `.sql` files of this folder with the table `schema_migrations`; an empty folder means nothing to run.\n')
    for rel in ['tests/migrations-check.mjs', 'tests/fixtures/schema-v2.15.3.sql', 'tests/fixtures/schema-v3.0.0.sql']:
        p = os.path.join(src, rel)
        if os.path.exists(p):
            os.remove(p)
    pj = os.path.join(src, 'package.json')
    data = json.load(open(pj, encoding='utf-8'))
    data['scripts'].pop('test:migrations', None)
    # The Template runs every test the program runs, except the migration check (it has no migration history).
    steps = [s for s in data['scripts']['test'].split(' && ') if s.strip() != 'npm run test:migrations']
    data['scripts']['test'] = ' && '.join(steps)
    regina_version = data['version']   # the Template keeps the real version of the code (package.json and the lock stay as they are)
    with open(pj, 'w', encoding='utf-8', newline='\n') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write('\n')
    sc = os.path.join(src, 'tests', 'server-checks.mjs')
    text = open(sc, encoding='utf-8', newline='').read()
    if GRANT_OLD in text:   # the check of migration 0005 uses its statement directly
        text = text.replace(GRANT_OLD, GRANT_NEW).replace('migration 0005: a manager who may add gets "Edito" once', 'a manager who may add gets "Edito" once')
        text = text.replace("import { readFileSync } from 'node:fs';" + chr(10), '', 1)
        open(sc, 'w', encoding='utf-8', newline='').write(text)
    return regina_version


def main():
    dry = '--dry-run' in sys.argv[1:]
    work = tempfile.mkdtemp(prefix='hrsystem-template-clean-')
    try:
        content = os.path.join(work, 'content')
        os.makedirs(content)
        version = build_tree(content)
        sys.path.insert(0, HERE)
        import pack
        pack.SRC = os.path.join(content, 'Source')
        zip_path = os.path.join(SETUP, 'Versions', f'V{version}', 'Template', f'HRSystem-{version}.zip')
        if not dry:
            os.makedirs(os.path.dirname(zip_path), exist_ok=True)
            for old in os.listdir(os.path.dirname(zip_path)):
                if old.endswith('.zip'):
                    os.remove(os.path.join(os.path.dirname(zip_path), old))
            pack.write(zip_path, '', pack.source_files())
            print('zip ->', zip_path)
        repo = os.path.join(work, 'repo')
        run('gh', 'repo', 'clone', TEMPLATE, repo)
        run('git', 'checkout', '-B', 'main', 'origin/main', cwd=repo)
        for name in os.listdir(repo):
            if name != '.git':
                p = os.path.join(repo, name)
                shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
        for name in os.listdir(content):
            src, dst = os.path.join(content, name), os.path.join(repo, name)
            shutil.copytree(src, dst) if os.path.isdir(src) else shutil.copy2(src, dst)
        run('git', 'add', '-A', cwd=repo)
        changes = run('git', 'status', '--porcelain', cwd=repo)
        print(f'Regina V{version} as Template {version}: {len(changes.splitlines())} changed files in the template repo')
        if dry:
            print(changes[:2000] or 'Template is already up to date.')
            return
        if changes:
            sha = run('git', 'rev-parse', '--short', 'origin/main', cwd=STUDIO)
            msg = f'HRSystem template {version} (clean build: final DatabaseSchema.sql, no migration history)\n\nFrom Regina main {sha} (V{version}).\n\n{CO_AUTHOR}'
            run('git', 'commit', '-q', '-m', msg, cwd=repo)
            run('git', 'push', '-q', 'origin', 'HEAD:main', cwd=repo)
            print('pushed to', TEMPLATE)
        # ONE Release only (owner, 2026-10-24): every Release and tag of the Template repo is deleted, then v{version} is created with the new zip.
        tag = f'v{version}'
        releases = run('gh', 'release', 'list', '-R', TEMPLATE, '--limit', '200', '--json', 'tagName', '--jq', '.[].tagName', check=False).split()
        for name in releases:
            run('gh', 'release', 'delete', name, '-R', TEMPLATE, '--cleanup-tag', '--yes')
        for name in run('gh', 'api', f'repos/{TEMPLATE}/tags', '--paginate', '--jq', '.[].name', check=False).split():
            run('gh', 'api', '-X', 'DELETE', f'repos/{TEMPLATE}/git/refs/tags/{name}', check=False)
        notes = os.path.join(work, 'notes.txt')
        open(notes, 'w', encoding='utf-8').write("- Build i pastër për klientë të rinj: databaza e plotë e rregulluar (DatabaseSchema.sql), pa histori migrimesh.\n"
                                                  f"- Njëlloj si versioni V{version} i Regina-s për kodin e programit.\n"
                                                  "- Ky është i vetmi release i Template-it: çdo version i ri e zëvendëson.\n")
        run('gh', 'release', 'create', tag, zip_path, '-R', TEMPLATE, '--target', 'main', '--title', f'V{version}','--notes-file', notes)
        print(f'Release {tag} created in {TEMPLATE} (the only one): code of Regina V{version}.')
    finally:
        def force(fn, path, exc):
            os.chmod(path, 0o700)
            fn(path)
        shutil.rmtree(work, onerror=force)


if __name__ == '__main__':
    main()
