# HRSystem uninstall (owner, 2026-10-21; wizard + "Keep database" 2026-10-22).
# Normally started by uninstall-wizard.ps1 (the window with Next / Next) with HRSYSTEM_AUTO=1 and HRSYSTEM_KEEP_DB=1|0; without them it asks in the console.
#   Keep the database = YES (default): BEFORE anything is deleted the last export of the database (HRSystem-databaza-<date>.sql) and the keys text
#     (HRSystem-celesat.txt: database user and password, MySQL root, APP_SECRET, SETUP_TOKEN ...) are saved on the Desktop. Only ONE copy of each stays there.
#   Keep the database = NO: nothing is saved.
# Then EVERYTHING is removed: the application and all its files, the dashboard, the tasks, the database service and its files (backups included), the
# tunnels, the shortcuts and the logs. If the export cannot be made (and "keep" is YES) nothing is deleted.
# Output: "=== step ===" lines (the window turns them into a progress bar) and, last, "=== READY ===" or "GABIM: ...".
$ErrorActionPreference = 'Stop'

# The installation can be on any drive: the installed copy of this script sits in the installation folder (next to current.txt).
$installRoot = if ($env:HRSYSTEM_ROOT) { $env:HRSYSTEM_ROOT } elseif ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'current.txt'))) { $PSScriptRoot } else { 'C:\HRSystem' }
$installRoot = $installRoot.TrimEnd('\')
$dataRoot = if ($env:HRSYSTEM_DATA) { $env:HRSYSTEM_DATA.TrimEnd('\') } else { $installRoot + 'Data' }
# HRSYSTEM_SANDBOX=1 (tests only): other task / service names and nothing outside the sandbox folders is touched (no shortcuts, no tunnel service).
$sandbox = ($env:HRSYSTEM_SANDBOX -eq '1')
$serviceName = if ($sandbox) { 'HRSystemSandboxMySQL' } else { 'HRSystemMySQL' }
$taskName = if ($sandbox) { 'HRSystemSandbox' } else { 'HRSystem' }
$auto = ($env:HRSYSTEM_AUTO -eq '1')

function Is-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Step([string]$name) { Write-Host "=== $name ===" -ForegroundColor Cyan }

function Read-EnvFile([string]$Path) {
    $cfg = @{}
    if (Test-Path $Path) {
        Get-Content $Path | ForEach-Object { if ($_ -match '^([A-Z_]+)=(.*)$') { $cfg[$Matches[1]] = $Matches[2] } }
    }
    return $cfg
}

function Desktop-Folder {
    $d = [Environment]::GetFolderPath('Desktop')
    if (-not $d) { $d = Join-Path $env:USERPROFILE 'Desktop' }
    return $d
}

# The export of the database on the Desktop. Returns the file path, or $null when there is no database to save.
function Save-LastBackup {
    $cfg = Read-EnvFile (Join-Path $installRoot '.env')
    if (-not $cfg['DB_NAME']) { Write-Host 'Nuk u gjet databaze per eksport (mungon .env) - po vazhdohet.' -ForegroundColor DarkGray; return $null }
    $dump = Get-ChildItem 'C:\Program Files\MySQL' -Recurse -Filter mysqldump.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $dump) { $c = Get-Command mysqldump.exe -ErrorAction SilentlyContinue; if ($c) { $dump = Get-Item $c.Source } }
    if (-not $dump) { throw 'mysqldump.exe nuk u gjet: eksporti nuk mund te behet, prandaj asgje nuk u fshi.' }
    # The database must be running to be saved.
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') { try { Start-Service -Name $serviceName -ErrorAction Stop } catch { } }
    $port = [int]$cfg['DB_PORT']
    for ($i = 0; $i -lt 30 -and -not (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Seconds 1 }
    $desktop = Desktop-Folder
    $file = Join-Path $desktop ('HRSystem-databaza-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.sql')
    $old = $env:MYSQL_PWD
    $env:MYSQL_PWD = $cfg['DB_PASSWORD']
    try {
        & $dump.FullName "--user=$($cfg['DB_USER'])" '--protocol=TCP' "--host=$($cfg['DB_HOST'])" "--port=$($cfg['DB_PORT'])" '--single-transaction' '--no-tablespaces' '--hex-blob' '--default-character-set=utf8mb4' "--result-file=$file" $cfg['DB_NAME']
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $file)) { throw 'mysqldump deshtoi' }
    } catch {
        Remove-Item $file -Force -ErrorAction SilentlyContinue
        throw "Eksporti i databazes deshtoi ($($_.Exception.Message)): asgje nuk u fshi."
    } finally { $env:MYSQL_PWD = $old }
    # Only the newest export stays on the Desktop.
    Get-ChildItem $desktop -Filter 'HRSystem-databaza-*.sql' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $file } | Remove-Item -Force -ErrorAction SilentlyContinue
    return $file
}

# The keys text (database user / password, MySQL root, APP_SECRET, SETUP_TOKEN ...) next to the export: with both a new install can be made later.
function Save-Keys {
    $src = Join-Path $installRoot 'HRSystem-Keys.txt'
    if (-not (Test-Path $src)) { return $null }
    $dest = Join-Path (Desktop-Folder) 'HRSystem-celesat.txt'
    Copy-Item -LiteralPath $src -Destination $dest -Force
    if (-not (Test-Path $dest)) { throw 'Skedari me celesat nuk u ruajt ne Desktop: asgje nuk u fshi.' }
    return $dest
}

# Before takeown /R, icacls /T, robocopy /MIR and Remove-Item -Recurse (they follow junctions, symbolic and hard links, so a link an ordinary user
# planted, to C:\Windows\System32 say, would make this elevated uninstall change or delete files outside HRSystem) the folder is closed with
# Protect-HrTree (hr-links.ps1, next to this script): links removed, no write left for ordinary users anywhere inside, so nothing new can be
# planted while the deletion runs (security review 2026-11-18/19). Returns $true when it is safe to go on; $false leaves the folder for the owner
# to delete by hand (a link or item that could not be handled, a folder itself a link, or hr-links.ps1 missing).
$linksScript = Join-Path $PSScriptRoot 'hr-links.ps1'
if (Test-Path -LiteralPath $linksScript) { . $linksScript }
function Remove-Links([string]$path, [switch]$KeepHardLinks) {
    if (-not (Test-Path -LiteralPath $path)) { return $true }
    if ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        try { [IO.Directory]::Delete($path, $false); Write-Host "U hoq lidhja: $path" -ForegroundColor Yellow } catch { }
        return $false   # the folder itself was a link: nothing of the target is touched
    }
    if (-not (Get-Command Protect-HrTree -ErrorAction SilentlyContinue)) { Write-Host "Mungon hr-links.ps1: $path nuk fshihet automatikisht, fshije me dore." -ForegroundColor Yellow; return $false }
    $r = Protect-HrTree -Path $path -OwnerSid ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value) -KeepHardLinks:$KeepHardLinks
    foreach ($n in $r.Notes) { Write-Host "  $n" -ForegroundColor Yellow }
    if (-not $r.Ok) { Write-Host "$path nuk fshihet automatikisht (shiko rreshtat me larte): fshije me dore." -ForegroundColor Yellow; return $false }
    return $true
}

# Empties a folder by mirroring an empty one (also removes trees that Remove-Item cannot: long paths, node_modules), then removes it.
function Wipe-Folder([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return }
    if (-not (Remove-Links $path)) { return }
    try {
        & takeown.exe /F $path /R /D Y 2>&1 | Out-Null
        & icacls.exe $path /reset /T /C 2>&1 | Out-Null
        & icacls.exe $path /grant '*S-1-5-32-544:(OI)(CI)F' /T /C 2>&1 | Out-Null
        $emptyDir = Join-Path $env:TEMP 'hrsystem-empty'
        New-Item -ItemType Directory -Force -Path $emptyDir | Out-Null
        & robocopy.exe $emptyDir $path /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS 2>&1 | Out-Null
    } catch { }
    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
}

try {
    if (!(Is-Admin) -and -not $sandbox) {
        throw 'Hape Uninstall.bat me Right-click > Run as administrator.'
    }

    $keepDb = $true
    if ($env:HRSYSTEM_KEEP_DB -eq '0') { $keepDb = $false }
    elseif ($env:HRSYSTEM_KEEP_DB -ne '1' -and -not $auto) {
        Write-Host ''
        Write-Host '=== HRSystem Uninstall ===' -ForegroundColor Cyan
        Write-Host "Do te hiqen PLOTESISHT: aplikacioni ($installRoot), dashboard-i, databaza ($dataRoot), detyrat dhe tunelet." -ForegroundColor Yellow
        $k = Read-Host 'Mbaj databazen (eksport + celesat ne Desktop)? Shkruaj PO ose JO (Enter = anulo)'
        if ($k -notmatch '^(po|jo)$') { Write-Host 'Anuluar: asgje nuk u ndryshua.' -ForegroundColor Green; exit 0 }
        $keepDb = ($k -match '^po$')
    }

    # 1. The export and the keys first, while everything is still there. If they fail nothing is removed.
    $backup = $null; $keys = $null
    if ($keepDb) {
        Step 'Eksporti i databazes'
        $backup = Save-LastBackup
        if ($backup) { Write-Host "Eksporti i databazes: $backup" -ForegroundColor Green }
        $keys = Save-Keys
        if ($keys) { Write-Host "Celesat: $keys" -ForegroundColor Green }
    }

    # 2. Tasks, dashboard, application, tunnels in use and the desktop shortcut.
    Step 'Aplikacioni dhe dashboard-i'
    foreach ($name in @($taskName, "$taskName-Dashboard")) {
        if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
            try { Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue } catch {}
            Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "Detyra $name u hoq." -ForegroundColor Green
        }
    }
    # the launcher (start-hrsystem.ps1) restarts node every 3 s: it goes first, then node (application and dashboard), then the tunnels started from this folder
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine -like '*start-hrsystem.ps1*' -and $_.CommandLine -like "*$installRoot*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*$installRoot*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Get-CimInstance Win32_Process -Filter "Name='cloudflared.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*$installRoot*" } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    # The dashboard runs as "node server.mjs" from its own folder (no path in its command line) and would start the application again, and it holds its folder
    # open: it is found by its port, like the application (owner, 2026-10-22: a running server must never stop the uninstall; it is stopped here, automatically).
    $ports = @()
    $envCfg = Read-EnvFile (Join-Path $installRoot '.env')
    if ($envCfg['PORT'] -match '^\d+$') { $ports += [int]$envCfg['PORT'] }
    $urlFile = Join-Path $installRoot 'dashboard-url.txt'
    if (Test-Path $urlFile) { try { $ports += ([uri]((Get-Content $urlFile -Raw).Trim())).Port } catch { } }
    foreach ($port in ($ports | Select-Object -Unique)) {
        Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | ForEach-Object {
            $pr = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
            if ($pr -and $pr.ProcessName -match '^(node|cloudflared)$') { Stop-Process -Id $pr.Id -Force -ErrorAction SilentlyContinue }
        }
    }
    # phpMyAdmin's php.exe (a child of the dashboard, started from <folder>\tools\php) keeps that folder open. It normally ends with the dashboard;
    # after the dashboard is gone, whatever php.exe still runs FROM THIS installation's tools folder is ended (never another PHP on this PC).
    $toolsPrefix = $installRoot + '\tools\'
    Get-CimInstance Win32_Process -Filter "Name='php.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($toolsPrefix, [StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 1
    if (-not $sandbox) {
        foreach ($n in @('HRSystem Dashboard.url', 'HRSystem Dashboard.lnk')) {
            Remove-Item (Join-Path 'C:\Users\Public\Desktop' $n) -Force -ErrorAction SilentlyContinue
            Remove-Item (Join-Path (Desktop-Folder) $n) -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Host 'Aplikacioni dhe dashboard-i u ndalen.' -ForegroundColor Green

    # 3. The database service and its files (the backups made by the updater and the dashboard are in the data folder too).
    Step 'Databaza dhe skedaret e saj'
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc) {
        try { if ($svc.Status -ne 'Stopped') { Stop-Service -Name $serviceName -Force -ErrorAction Stop } } catch {}
        & sc.exe delete $serviceName | Out-Null
        Start-Sleep -Seconds 1
        Write-Host 'Sherbimi HRSystemMySQL u hoq.' -ForegroundColor Green
    }
    if (Test-Path $dataRoot) {
        Wipe-Folder $dataRoot
        Write-Host 'Databaza dhe skedaret e saj u fshine.' -ForegroundColor Green
    }

    # 4. The Cloudflare Tunnel (a Windows service made by the setup).
    Step 'Tuneli Cloudflare'
    if (-not $sandbox -and (Get-Service -Name 'Cloudflared' -ErrorAction SilentlyContinue)) {
        $cf = Get-Command cloudflared.exe -ErrorAction SilentlyContinue
        $cfPath = if ($cf) { $cf.Source } else { @('C:\Program Files\cloudflared\cloudflared.exe', 'C:\Program Files (x86)\cloudflared\cloudflared.exe') | Where-Object { Test-Path $_ } | Select-Object -First 1 }
        if ($cfPath) {
            try { & $cfPath service uninstall 2>$null | Out-Null; Write-Host 'Cloudflare Tunnel u hoq.' -ForegroundColor Green } catch { Write-Host 'Tuneli nuk u hoq: ekzekuto "cloudflared service uninstall".' -ForegroundColor Yellow }
        } else { Write-Host 'cloudflared.exe nuk u gjet; ekzekuto "cloudflared service uninstall".' -ForegroundColor Yellow }
    }

    # 5. Leftovers outside the folders: logs and temporary files of the setup.
    Step 'Skedaret e mbetur'
    foreach ($f in @('hrsystem-setup.log', 'hrsystem-uninstall.ps1', 'hrsystem-uninstall.log', 'hrsystem-empty')) {
        Remove-Item -LiteralPath (Join-Path $env:TEMP $f) -Recurse -Force -ErrorAction SilentlyContinue
    }
    # The GitHub token the setup remembered for this Windows user (setup-token.dat) must not stay behind.
    Remove-Item -LiteralPath (Join-Path $env:APPDATA 'HRSystem') -Recurse -Force -ErrorAction SilentlyContinue

    # 6. The application folder. A folder cannot be deleted while a process uses it (its working folder or an open file): the cleanup
    # runs from TEMP, ends every node/powershell process of this installation (not the window that shows this result) and tries again
    # for about 30 seconds.
    Step 'Folderi i aplikacionit'
    # Links first: takeown /R, icacls /T, robocopy /MIR and Remove-Item -Recurse below would follow one out of the folder. When one stays,
    # the cleanup still stops this installation's processes but leaves the folder for the owner.
    $wipeOk = Remove-Links $installRoot
    $wipeFlag = if ($wipeOk) { '$true' } else { '$false' }
    if ($wipeOk) { Write-Host "$installRoot do te fshihet brenda disa sekondave." -ForegroundColor Yellow }
    else { Write-Host "$installRoot nuk fshihet automatikisht (shiko rreshtat me larte): fshije me dore pasi te mbyllet kjo dritare." -ForegroundColor Yellow }
    $cleanup = @"
`$wipe = $wipeFlag
Set-Location `$env:TEMP
for (`$i = 0; `$i -lt 15; `$i++) {
    Start-Sleep -Seconds 2
    try {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object { (`$_.Name -eq 'node.exe' -or `$_.Name -eq 'powershell.exe' -or `$_.Name -eq 'cloudflared.exe') -and `$_.ProcessId -ne `$PID -and `$_.CommandLine -and `$_.CommandLine -like '*$installRoot*' } |
            ForEach-Object { Stop-Process -Id `$_.ProcessId -Force -ErrorAction SilentlyContinue }
        # phpMyAdmin's php.exe, only the one that runs from this installation's tools folder
        Get-CimInstance Win32_Process -Filter "Name='php.exe'" -ErrorAction SilentlyContinue |
            Where-Object { `$_.ExecutablePath -and `$_.ExecutablePath.StartsWith('$installRoot\tools\', [StringComparison]::OrdinalIgnoreCase) } |
            ForEach-Object { Stop-Process -Id `$_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch {}
    if (-not `$wipe) { break }
    if (Test-Path -LiteralPath '$installRoot') {
        & takeown.exe /F '$installRoot' /R /D Y 2>&1 | Out-Null
        & icacls.exe '$installRoot' /reset /T /C 2>&1 | Out-Null
        & icacls.exe '$installRoot' /grant '*S-1-5-32-544:(OI)(CI)F' /T /C 2>&1 | Out-Null
        `$empty = Join-Path `$env:TEMP 'hrsystem-empty'
        New-Item -ItemType Directory -Force -Path `$empty | Out-Null
        & robocopy.exe `$empty '$installRoot' /MIR /R:0 /W:0 /NFL /NDL /NJH /NJS 2>&1 | Out-Null
    }
    Remove-Item -LiteralPath '$installRoot' -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath '$installRoot')) { break }
}
Remove-Item -LiteralPath (Join-Path `$env:TEMP 'hrsystem-empty') -Recurse -Force -ErrorAction SilentlyContinue
# the downloaded setup that the USB stick keeps unpacking (it may be the folder this uninstall started from, so it goes last)
Remove-Item -LiteralPath (Join-Path '$env:LOCALAPPDATA' 'HRSystem-Setup') -Recurse -Force -ErrorAction SilentlyContinue
"@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cleanup))
    Start-Process powershell.exe -WindowStyle Hidden -WorkingDirectory $env:TEMP -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encoded)

    Write-Host ''
    Write-Host 'HRSystem u cinstalua plotesisht.' -ForegroundColor Green
    if ($backup) { Write-Host "Eksporti i databazes: $backup (importoje me dashboard-in ose sql-import.bat pas instalimit te ri)." -ForegroundColor Green }
    if ($keys) { Write-Host "Celesat (databaza, APP_SECRET, tokenat): $keys" -ForegroundColor Green }
    if (-not $keepDb) { Write-Host 'Databaza NUK u ruajt: nuk mbeti asgje ne kete kompjuter.' -ForegroundColor Yellow }
    Write-Host 'Node.js dhe MySQL Server nuk u cinstaluan (mund t i perdorin programe tjera): instalimi i ri eshte i pastert dhe i shpejte.' -ForegroundColor DarkGray
    Step 'READY'
    exit 0
}
catch {
    Write-Host ''
    Write-Host "GABIM: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
