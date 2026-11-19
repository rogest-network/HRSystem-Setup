# Regina.HR on a Windows computer (the local setup, since 1.0.1)

One setup, one updater, one SQL importer. They live in `Setup/Claude Studio/installer/` (in git) and `scripts/pack.py` puts them
in the root of `HRSystemV<x>-Setup.zip` (scripts + `client.json`; the app is downloaded from the client's repo). The old separate network tool
(`Setup/Tools/HRSystemNetworkSetup.zip`) is gone: the tunnel is a step of the setup.

## Repo-driven (owner's decision, 2026-10-21)
Versions live on GitHub, one repository per client. `update.json` in the install folder names the repo and the channel
(`stable` = newest Release that is not a pre-release; `test` = also pre-releases, used by the PC test environment).
`HRSystemV<x>-Setup.zip` is the thin setup (scripts + `client.json`): `Install.bat` asks for the read-only GitHub token and downloads the
app from the repo, so a new client is only `scripts/new_client.py <Client>` (a repo from `rogest-network/HRSystem-Template`, its first Release and a Setup
zip whose `client.json` names that repo). There is no zip with the app inside any more (owner, 2026-10-21): the app zip (`HRSystem-<x>.zip`) lives on GitHub. Without a stored token the updater uses the signed-in `gh`
(the owner's own PC). A Release re-published under the same number is installed as `<version>-b2`, `-b3` ... (marker `.asset` in the
release folder).

## The first owner (`/setup`)
At the end of `Install.bat` the browser opens `http://localhost:3000/setup#token=<SETUP_TOKEN>`: the part after `#` never goes to the
server, the page reads it, removes it from the address bar and hides the token field. The owner types only the owner's name,
user name and password, the business name and picks the logo and icon. After the owner exists `/setup` closes itself (tested on an empty database 2026-10-21).
**The setup window (2026-10-22, owner's order) asks only what a person must decide:** the folder, the **first owner** (user, name, password) and the **business** (name, logo, icon). It does NOT ask for the database name, the GitHub token, the repository or the Cloudflare token: the database is named and made automatically, the app comes from the Setup zip, and a token the owner put into the zip (`github-token.txt` next to Install.bat) is read by the installer itself (otherwise a token is added later in the dashboard). After the install the window creates the owner and the business through the app's own `/api/setup` (SETUP_TOKEN from `HRSystem-Keys.txt`, logo/icon compressed like the browser does: logo up to 1200x600, icon 512x512 PNG; `Origin` = `APP_ORIGIN` or the address called). An existing installation skips the owner and business pages. Tested 2026-10-22 against a test app on a test MySQL: owner created (role pronari), branding served, a second call answers `EXISTS`, a 100x100 icon is refused.
The older text about the token (kept for the installer's own logic when a token file is present): the setup used to ask for the **GitHub token** (2026-10-22): the repository is found from the token, never from a repo fixed in the setup
(`Find-Repo` in `wizard.ps1`, `Find-RepoFromToken` in `hr-common.ps1`: the client's own `HRSystem-*` repos first, then the Template, then others, never the Dashboard/Test repo; the first one that has a Release wins, so a token that also reaches the public Dashboard repo does not pick it - fixed 2026-10-22 after the owner got "no Release" with a Template token).
The updater (`update.bat`) does the same on every run and saves the repo to `update.json`; `client.json` no longer names a repo. The Setup zip is rebuilt
with `python "Setup/Claude Studio/scripts/pack.py" --setup-only <ver>` (not pushed to any repo). Both windows (setup and
uninstall) are branded "HRSystem". Tested: `Find-Repo` with the signed-in `gh` token (no hint → HRSystem-ReginaCenter; hint Template → Template; bad token → empty).

## Getting the Setup on a new PC (owner, 2026-10-22)
The built Setup zip is a Release asset of the private repo `rogest-network/HRSystem-Setup` (the repo holds only a README). On a new PC: open the repo's Releases while signed in to GitHub, download `HRSystemV<x>-Setup.zip`, extract, run `Install.bat`. No USB stick. The owner publishes a rebuilt zip with `python "Setup/Claude Studio/scripts/pack.py" --setup-only <ver> --publish` (creates the Release once, later builds replace its asset).

**The USB stick keeps ONE small file, `Setup/HRS-Setup.zip`, which never changes** (owner, 2026-10-22). Its `Install.bat` runs `bootstrap.ps1`, which downloads the newest setup zip from `HRSystem-Setup` (Releases), unpacks it to `%LOCALAPPDATA%\HRSystem-Setup\<tag>` (only the newest is kept; unchanged = no new download) and opens its `Install.bat`. Offline or a wrong token: it offers the last unpacked copy. The read-only GitHub token of that repo is read from `setup-token.txt` inside the zip (built from `Setup/Claude Studio/secrets/setup-token.txt`, git-ignored, only on this PC); without it the window asks once per Windows user and remembers it (DPAPI). Build: `python "Setup/Claude Studio/scripts/pack.py" --bootstrap`. Tested 2026-10-22: download, cache hit (1.2 s), a bad token answers 401 without launching.

**The dashboard is installed from its own repo** (owner, 2026-10-23): `installer.ps1` downloads `https://github.com/rogest-network/HRSystem-Dashboard/archive/refs/heads/main.zip` (public, no token), unpacks it and copies it to `<install>\manager`, so a fresh install always has the newest dashboard. Only when that is unreachable (no internet) it uses the copy bundled in the setup zip (`files/manager`). Tested 2026-10-23: the download and unpack work and the repo's `server.mjs` equals the installed one.

**The setup holds NO program** (owner, 2026-10-23: the Setup and the Template are not kept twice). At install time `installer.ps1` downloads the newest Release of the **client's repo** when a token is available (`HRSYSTEM_GITHUB_TOKEN` from the USB bootstrap, `github-token.txt`, or `gh`; the repo is found from the token), otherwise of **`rogest-network/HRSystem-Template`**, which then must be readable without a token (public). A change of the base program is made in the Template repo only; the setup zip is not rebuilt for it. Tested 2026-10-23: with a token the Template Release downloads and unpacks (v1.0.1, schema present); without a token the private Template answers 404 and the installer says so and asks for a token.

## Uninstall (owner, 2026-10-21)
Since 2026-10-22 `Uninstall.bat` opens a window like the setup (`uninstall-wizard.ps1`, Next / Next, brand "HRSystem"; `Uninstall.bat /console`
runs the old console version). Pages: welcome, **Keep: Database [Po] [Jo]** (one click, default Po), summary (red "Çinstalo"), progress, done.
- **Po:** BEFORE anything is deleted, two files go to the Desktop (only one copy of each is kept): `HRSystem-databaza-<date>.sql` (export) and
  `HRSystem-celesat.txt` (copy of `HRSystem-Keys.txt`: database user/password, MySQL root, APP_SECRET, SETUP_TOKEN). If the export cannot be made
  nothing is deleted.
- **Jo:** nothing is saved.
- Then **everything** is removed: application and files, dashboard, tasks, launcher, node/cloudflared/php processes of the folder, database service
  and files (backups included), Cloudflare tunnel service, shortcuts, setup logs. Only the two Desktop files remain (with Po). Node.js and MySQL
  Server stay installed (other programs may use them).
- The uninstall **stops the running application and the dashboard by itself** (by port, because the dashboard runs as `node server.mjs` with no path in its command line and would otherwise hold its folder and restart the app); the window first asks "Je i sigurt?" when something is running. Tested in a sandbox with two fake servers (app-like and dashboard-like): both stopped, folder removed.
- `uninstall.ps1` is the engine (`HRSYSTEM_AUTO=1`, `HRSYSTEM_KEEP_DB=1|0`, `HRSYSTEM_ROOT`, `HRSYSTEM_DATA`); `HRSYSTEM_SANDBOX=1` is for tests only
  (other task/service names, no shortcuts/tunnel, no admin needed). Tested 2026-10-22 in a sandbox on C: with a real test MySQL: Po and Jo.
After that a new install is clean, and the export can be imported (Dashboard: *Importo databazen*, or `sql-import.bat`).

## What the zip shows (owner, 2026-10-21)
Only three files: **Install.bat**, **Uninstall.bat** and **Dashboard.bat** (everything else is in the `files` folder). Install asks for the
passwords in Windows dialogs, installs, and at the end **opens the Dashboard** (not the application) and puts a *HRSystem Dashboard*
shortcut on the desktop. The Dashboard (the system picks a free port itself and writes the address to `C:\HRSystem\dashboard-url.txt`; the desktop shortcut and Dashboard.bat read it; it runs as the administrator who installed, starts at sign-in) shows where
everything is installed (folders, `.env`, database files, backups, logs, each with a Hap button), the address, domain and tunnel, and has
**Stop / Start / Restart** of the application, backups (download, open folder), **Perditeso** (update), **Ekzekuto SQL**, **Importo
databazen** and **Cinstalo**. A new installation shows two ways forward: create the owner (`/setup`, token filled in) or import the old
database first and then open the login. Uninstall is also a file of its own (`Uninstall.bat`, in the install folder too) so it works even
when the Dashboard does not.

## What the owner does
| File | What it does |
|---|---|
| `Install.bat` | Installs Node.js, the Microsoft Visual C++ runtime and MySQL 8.4 when they are missing (winget), makes the database, installs the app, starts it with Windows, installs the dashboard and, as its last step, waits until the dashboard has PHP + phpMyAdmin ready (section "Database tools" below). At the end it asks, and Enter skips: the **Cloudflare Tunnel token** (opens the app from the internet with the owner's own address) and a **read-only GitHub token** (so `update.bat` can fetch new versions). Running it again is safe and is how the tunnel or the token is added later. |
| `update.bat` | Fetches the newest GitHub Release and installs it. `update.bat check` only says if there is a newer one; `update.bat <zip>` installs a local `HRSystem-<x>.zip`. |
| `sql-import.bat` | Runs one `.sql` file on the database (a window chooses it, or `sql-import.bat file.sql`), after a backup. |
| `uninstall.bat` | Stops and removes the app (asks before deleting data). |
All of them open as Administrator and end with **SUKSES** or **GABIM** (details in `Updater.log`, `Sql-Import.log`, `HRSystem-Install.log`).

## What `update.bat` does, in order
1. Reads the installed version (`C:\HRSystem\current.txt`); asks GitHub for the newest Release of its channel (tags `test-*` are
   never offered) and stops with "you have the newest" when it is not newer.
2. Downloads the Release's `HRSystem-<x>.zip` (the token does not follow GitHub's redirect to the file store).
3. Database backup to `C:\HRSystemData\Backups` (the last 14 kept).
4. Unzips to `C:\HRSystem\releases\<version>`, installs the packages, builds.
5. **The SQL of the version**: `node server/core/migrate-cli.mjs` against the installation's database; every migration it applies is
   shown. A failing migration stops everything before the switch: the installed version keeps running, the message says GABIM.
6. Names the new release in `current.txt`, restarts the app and checks `/api/health`. If it does not answer, the old release is put
   back (the migrations are additive and safe to run again, so nothing is undone in the database; the backup is named in the message).
7. Keeps the previous release and removes older ones.

## On the computer
`C:\HRSystem\` (releases, `current.txt`, `.env`, `HRSystem-Keys.txt`, the launcher `start-hrsystem.ps1`, the scripts, logs, `manager\` = the dashboard, `tools\` = PHP + phpMyAdmin),
`C:\HRSystemData\` (the MySQL data folder and the backups). The Task Scheduler task `HRSystem` starts the launcher at Windows start
(as SYSTEM); the launcher starts the release named in `current.txt` and starts it again if it stops. MySQL is the service
`HRSystemMySQL` (a free port from 3307). `github.token` is encrypted with Windows DPAPI (this machine) and readable by administrators only.

## Folder permissions (security review, 2026-11-18)
A folder made under `C:\` inherits "Authenticated Users: Modify", and the app runs from `C:\HRSystem` as SYSTEM, so before this any ordinary
user of a shared PC could change its scripts and run code as SYSTEM. At the end of the setup (stage "Lejet e folderave") `Lock-HrFolders`
(`installer/hr-common.ps1`) closes both folders:

| Who | `C:\HRSystem` | `C:\HRSystemData` |
|---|---|---|
| SYSTEM (the app, MySQL), Administrators (elevated: dashboard, updater, uninstall) | Full | Full |
| The account that ran the setup (the owner; the dashboard task runs as him) | Modify: Explorer, Notepad and the dashboard's open-folder buttons work with no "access denied" | Modify |
| Every other user of the PC | only the list of the top folder and `Dashboard.bat` (the Public-desktop shortcut); no logs, no `dashboard.key` | nothing (database files and backups) |

`.env`, `HRSystem-Keys.txt`, `github.token` and `tools\phpmyadmin-data` keep their own closed permissions (SYSTEM + Administrators).
How (`Protect-HrTree` in `installer/hr-links.ps1`; no `icacls /T`, `takeown /R` or `robocopy /MIR` on these folders any more, because they
follow junctions, symbolic links and hard links out of the folder): 1. every link inside is removed (only the link); 2. the top folder gets its
exact permissions; 3. one walk, top down, that never enters a link: each folder is closed (owner, explicit entries of anyone else removed)
before it is read, links found are removed, files are closed, and an item Administrators cannot open is taken over by itself (`takeown /A`
on that item only). A finished lock writes `.hr-locked` in the folder; a lock with any problem prints GABIM in red and writes nothing, so the
next run tries again. The setup does the same at its START on an old folder (`Unlock-Folder`), and the uninstall before it deletes anything
(a folder it cannot close completely is left for the owner; `Uninstall.bat` copies `hr-links.ps1` to TEMP next to the uninstall script).
Deny entries are removed (HRSystem sets none). While the walk runs (and only then) SeBackupPrivilege is on, so an elevated run reads the
link count of every file whatever its entries say; it is switched off before anything else starts. The uninstall deletes with robocopy /XJ
and .NET `Directory.Delete`, which never enter a link (never `Remove-Item -Recurse`). In the data folder a hard-linked file (maybe a database file) is reported and nothing is
changed; the setup then uses a fresh MySQL data folder instead of cleaning the old one with recursive tools. Residual: a link planted in the few milliseconds between steps 1 and 2, or in a
folder that still had an ordinary user's own explicit entry before the walk reached it, can receive the top folder's inherited entries.
`updater.ps1` repeats the lock when it is missing, but an installed updater is never replaced by an update, so an install made with a setup
older than 2026-11-18 is closed only by running the new setup again over it. A second Windows account of the owner is not given Modify: he
uses the installing account or opens things as Administrator. `Dashboard.bat` falls back to `http://127.0.0.1:3500` when it cannot read
`dashboard-url.txt`, and never starts itself again from the same folder.

## Database tools: Visual C++ runtime, PHP, phpMyAdmin (owner, 2026-11-12: "installin me e pas PHP krejt mirë në rregull")
The dashboard's button "Hap databazën (phpMyAdmin)" needs PHP for Windows and phpMyAdmin in `<install>\tools\{php, phpmyadmin, phpmyadmin-data}`.
**The dashboard is the only downloader** (`pmaInstall` / `pmaEnsure` in `manager/server.mjs`, both downloads SHA-256 checked; 30 s after it starts and
every 30 minutes while they are missing). The installer has no second downloader; it does three things:
1. **Step "Visual C++ Runtime"** (after Node.js, before MySQL; `Install-VcRuntime` in `hr-common.ps1`). php.exe does not start without the Microsoft
   Visual C++ Redistributable 2015-2022 x64, and refuses one OLDER than it was linked with (PHP 8.3 vs16 = 14.29, PHP 8.4 vs17 = 14.4x); MySQL's own
   installer wants it too. Before this step the setup did nothing about it: it only came along as a winget dependency of `Oracle.MySQL`
   (`Microsoft.VCRedist.2015+.x64`), so it was missing when MySQL was already on the PC. Detection (`Get-VcRuntimeVersion`): `vcruntime140.dll` +
   `vcruntime140_1.dll` in System32, version from the file (registry `HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64` only as a fallback for
   the number). Missing or below `$script:HrVcMinVersion` (14.44): Microsoft's `https://aka.ms/vc14/vc_redist.x64.exe` (newest v14; then
   `https://aka.ms/vs/17/release/vc_redist.x64.exe`) is downloaded, `Test-MicrosoftSigned` (Authenticode `Valid`, subject CN/O = Microsoft Corporation,
   issuer O = Microsoft Corporation) must pass BEFORE it runs, then `/install /quiet /norestart` (0, 1638, 3010 = success; 10 minutes at most).
   A failure is a yellow line in Albanian and the install goes on.
2. **`tools\phpmyadmin-data` is made and closed before the dashboard first starts** (`Protect-Folder` in `installer.ps1`: inheritance removed, only
   SYSTEM and Administrators, inherited by everything written there later). While phpMyAdmin is open its PHP session file holds the database password
   (like `.env`); `secret.hex` and the one-time sign-in token live there too. The dashboard runs elevated, so it and its php.exe still write there.
   The rest of the install folder is NOT closed (owner, 2026-10-21): only `.env`, `HRSystem-Keys.txt`, `github.token` and this folder are.
   NOT covered by the installer: an installation made before 2026-11-12 whose dashboard created the folder itself (it has the open, inherited rights
   until `Install.bat` is run over it again), and a `tools` folder deleted by hand and made again by the dashboard.
3. **Last step "Mjetet e databazes (PHP, phpMyAdmin)"** (before READY; `Wait-DbTools` in `hr-common.ps1`). It waits up to 240 s (`HRSYSTEM_TOOLS_WAIT`
   = seconds, tests) for `tools\phpmyadmin-data\installed.json` + `tools\php\php.exe` + `tools\phpmyadmin\index.php`, printing what the dashboard is
   doing (waiting / downloading = `tools\downloads` / unpacking = `.php-new`, `.phpmyadmin-new` / checking PHP), then runs `php.exe -c php.ini -v`
   (`Test-DbToolsPhp`) and prints `DBTOOLS=READY|phpMyAdmin <v>, PHP <v>`. It stops waiting early when the dashboard writes its failure line
   (`manager\dashboard-errors.log`, where = "phpMyAdmin", e.g. no internet) or when php.exe sits there unaccepted for 25 s; when php.exe itself reports
   the runtime (exit 0xC0000135 or a `vcruntime` message) `Install-VcRuntime -Force` runs once and php is tried again. Not ready in time =
   `DBTOOLS=LATER|<why>` and the install still ends with READY: the dashboard goes on by itself. The setup window shows the stage
   ("Mjetet e databazës (PHP, phpMyAdmin)", the bar creeps 94-97 %) and its last page has the line `phpMyAdmin: gati (...)` or
   `phpMyAdmin: Dashboard-i e instalon vetë pas pak (kërkon internet)`.

**Update and uninstall.** `update.bat` / the dashboard's update only write `releases\`, `current.txt` and logs: `tools\` survives every program update.
`uninstall.ps1` ends the php.exe that runs FROM this installation's `tools\` folder (matched by its executable path, never another PHP on the PC), in
the engine and again in the detached cleanup loop, so the folder can be removed; `tools\` goes with the install folder.

**Troubleshooting.** "phpMyAdmin: Dashboard-i e instalon vetë pas pak": no internet or a slow PC at install time; nothing to do, the dashboard retries
every 30 minutes and at the first click on "Hap databazën" (needs windows.php.net / phpmyadmin.net). "PHP nuk niset: mungon Microsoft Visual C++
Redistributable": install `vc_redist.x64.exe` from the link above (or run `Install.bat` again with internet), then click the button again. The reasons
are in `HRSystem-Install.log` (step "Mjetet e databazes") and in the dashboard's page Gabimet (`manager\dashboard-errors.log`).

Tested 2026-11-12 (sandbox roots in the scratchpad, not elevated): 27 checks of the functions (detection incl. an empty and a half system folder,
signature accept/refuse incl. a tampered Microsoft file, ready / empty / simulated dashboard sequence / stuck php / dashboard failure line / missing
DLL without an error box / PHP's "not compatible" message), the access rights on a throw-away folder under `C:\`, the setup window with a stand-in
installer (ready and not ready), and the uninstall in sandbox mode with a running php.exe (removed in 3 s; the previous script left the folder).
NOT tested: the real download and silent install of vc_redist (this PC has 14.51), an elevated dashboard writing into the closed folder, the real
dashboard filling `tools\` while the installer waits, a clean Windows PC.

## The GitHub token
Created by the owner at GitHub: Settings, Developer settings, Fine-grained tokens, repository `rogest-network/HRSystem-ReginaCenter` only,
permission **Contents: Read-only** (Metadata read is added by GitHub). It is pasted into `Install.bat` once and never goes through chat.

## Tests (2026-10-21)
The scripts parse without errors and the updater was run against a sandbox (`HRSYSTEM_ROOT` / `HRSYSTEM_DATA` point somewhere else
for tests; a test root does not need Administrator and cannot touch the real install): a good version with a new migration, a version
with a broken migration (stops before the switch), a version that cannot start (goes back), and the GitHub download. The full
`Install.bat` (winget installs, the MySQL service) was NOT run on a clean Windows computer.

## Setup window (2026-10-22)

`Install.bat` opens `files/wizard.ps1`, a WinForms "Next, Next" window (no console): pages Welcome, Location (drive list with free space, folder, data folder = `<folder>Data`; blocks Windows/Program Files/Users, needs 3 GB, warns about USB/external disks and refuses a second location when the `HRSystem` task already points elsewhere), Database (name, default `hrsystem`; backups are `<name>-<date>-<time>.sql`), Updates (GitHub repo NAME + read-only token, tested against the GitHub API before continuing), Summary, Progress (from the `=== step ===` lines of the installer), Done (dashboard, app, keys, log; "Provo përsëri" on failure). It runs `installer.ps1` hidden with `HRSYSTEM_AUTO=1` and `HRSYSTEM_ROOT / DATA / DBNAME / REPO / CHANNEL / GITHUB_TOKEN [/ MYSQL_ROOT_PASSWORD]`: no question is asked in a console or a dialog (`Read-Secret` returns empty). An existing MySQL with an unknown root password ends with `MYSQL_ROOT_PASSWORD_NEEDED`: the window asks for it and runs again. `hr-common.ps1` and `uninstall.ps1` take the installation folder from where they sit (next to `current.txt`), so an installation on D: works. `wizard.ps1 -Preview <folder>` draws every page into PNG files; `-FakeInstaller <script> -SelfTest <folder>` runs the whole flow against a stand-in installer (nothing is installed). NOT tested: a real install through the window on a clean Windows computer.
