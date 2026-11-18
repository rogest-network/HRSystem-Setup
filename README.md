# HRSystem Setup

Ky repo mban **setup-in e Windows** të HRSystem: skriptet e instalimit (`installer/`), skriptet që ndërtojnë dhe publikojnë
versionet (`scripts/`) dhe dokumentet e tyre (`docs/`). Zip-i i gatshëm i setup-it (`HRSystemV<version>-Setup.zip`) është te
**Releases**, jo në git. Asnjë token, fjalëkalim apo kod aplikacioni nuk mbahet këtu.

## Si instalohet në një kompjuter të ri (pa USB)

1. Hap **Releases** të këtij repo dhe shkarko zip-in e fundit (`HRSystemV…-Setup.zip`).
2. Nxirre zip-in në një folder (p.sh. Desktop).
3. Kliko dy herë **Install.bat** (Run as administrator).
4. Dritarja kërkon vetëm folderin, pronarin e parë (përdorues, emër, fjalëkalim) dhe biznesin (emër, logo, ikonë). Databaza, Node.js dhe MySQL bëhen vetë.

Heqja: **Uninstall.bat** (zgjedh a ruhet databaza; ndalon vetë aplikacionin).

## Udhëzuesi i plotë

## Në kompjuterin e dyqanit (Windows): një skedar i vetëm
1. Merr `HRS-Setup.zip` (i vetmi skedar në këtë dosje; vihet një herë në USB dhe nuk ndryshon kurrë), zbërthe dhe kliko dy herë **`Install.bat`**: shkarkon vetë setup-in e fundit nga repo `HRSystem-Setup` dhe hap dritaren e instalimit (folderi, pronari i parë, biznesi; pa pyetje për token ose databazë). Setup-et e plota janë te `Versions/V<x>/`.
   Instalimi i bën vetë, pa asnjë hap me dorë (kërkohet internet): Node.js, **Microsoft Visual C++ Runtime** (nëse mungon ose është i vjetër, shkarkohet nga Microsoft dhe verifikohet nënshkrimi), MySQL 8.4, aplikacionin, Dashboard-in dhe, si hap i fundit, **mjetet e databazës (PHP + phpMyAdmin)** për butonin "Hap databazën (phpMyAdmin)" të Dashboard-it. Faqja e fundit e dritares tregon `phpMyAdmin: gati (...)`.
2. **Përditësim:** `update.bat` merr automatikisht Release-n e fundit nga GitHub (backup, build, SQL, kontroll, kthim automatik) dhe tregon **SUKSES** ose **GABIM**. `sql-import.bat` ekzekuton një skedar `.sql`. Përditësimi nuk e prek dosjen `tools` (PHP, phpMyAdmin).

## phpMyAdmin / PHP: nëse diçka nuk shkon
- **Faqja e fundit thotë "phpMyAdmin: Dashboard-i e instalon vetë pas pak":** instalimi mbaroi pa to (pa internet, ose kompjuter i ngadaltë: pritet deri në 4 minuta). Nuk duhet bërë asgjë: Dashboard-i provon vetë çdo 30 minuta, ose menjëherë kur shtyp "Hap databazën (phpMyAdmin)". Duhet internet (php.net, phpmyadmin.net).
- **"PHP nuk niset: mungon Microsoft Visual C++ Redistributable":** instalimi e vendos vetë; nëse atëherë nuk kishte internet, shkarko `vc_redist.x64.exe` nga Microsoft (https://aka.ms/vs/17/release/vc_redist.x64.exe), instaloje dhe shtyp përsëri "Hap databazën".
- **Ku janë:** `<dosja e instalimit>\tools\php`, `tools\phpmyadmin`, `tools\phpmyadmin-data` (rreth 150 MB). Dosja `tools\phpmyadmin-data` hapet vetëm nga Administratorët dhe SYSTEM (aty rri përkohësisht fjalëkalimi i databazës sa kohë phpMyAdmin është hapur).
- **Çinstalimi** e ndal vetë `php.exe` të kësaj dosjeje dhe e heq `tools` bashkë me instalimin.

## Çfarë ka në këtë repo

| Dosja | Çfarë |
|---|---|
| `installer/` | `Install.bat`, `Uninstall.bat`, `Dashboard.bat`, `installer.ps1`, `wizard.ps1`, `updater.ps1` / `update.bat`, `sql-import`, `uninstall`, `bootstrap/` (zip-i i USB-së), `test-env.*` (hapësira e provës) |
| `scripts/` | `pack.py` (ndërton zip-at; `--setup-only <ver> --publish` publikon setup-in këtu), `template_release.py` (Release i Template), `new_client.py` (klient i ri), `status_audit.py` (kontrolli i gjendjes), `catchup_sql.py`, `website-qa/` |
| `docs/` | `WINDOWS_SETUP.md` (instalimi në detaje), `TEST_SPACE_MULTI_COMPANY.md` |

Në PC-në e punës ky repo është dosja `Desktop\HRSystem\Setup`. Brenda saj `Claude Studio\` është kopja e repo-s
`HRSystem-ReginaCenter` (programi + manuali) dhe nuk hyn këtu; as `Versions\`, `Clients\` dhe zip-at (`.gitignore`).
Manuali i gjithë projektit: `Claude Studio\manual\` (repo Regina).

## Rregull

Programi jeton te repot e klientëve (p.sh. `HRSystem-ReginaCenter`) dhe te `HRSystem-Template`, dashboard-i te
`HRSystem-Dashboard`. Ky repo është publik: kurrë token, `.env`, `secrets\` apo të dhëna të një kompanie.

---

English: the HRSystem Windows setup (installer scripts, the release/packaging scripts and their docs). The ready setup zip is
under Releases: download it, extract, run `Install.bat` as administrator.
