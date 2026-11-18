# HRSystem setup for Windows (Install.bat): ONE setup. It installs Node.js and MySQL when they are missing, makes the database,
# installs the app, starts it by itself with Windows, and (optionally) connects the Cloudflare tunnel and the GitHub updates. It also makes
# sure the Microsoft Visual C++ runtime is there and, at the end, waits until the dashboard has PHP + phpMyAdmin ready ("Hap databazen").
# Updates later: update.bat. A SQL file: sql-import.bat.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$sourceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $sourceRoot 'hr-common.ps1')
$payload = Join-Path $sourceRoot 'HRSystem'
$installRoot = $script:Root
$dataRoot = $script:DataRoot
$mysqlData = Join-Path $dataRoot 'MySQLData'
$mysqlIni = Join-Path $installRoot 'mysql-hrsystem.ini'
$mysqlLog = Join-Path $dataRoot 'mysql-error.log'
$envFile = $script:EnvFile
$keyFile = Join-Path $installRoot 'HRSystem-Keys.txt'
$installLog = Join-Path $installRoot 'HRSystem-Install.log'
$marker = Join-Path $dataRoot 'install-complete.marker'
$serviceName = 'HRSystemMySQL'
$mysqlPort = $null
$dbName = 'hrsystem'
# The name of the database can be chosen (owner, 2026-10-22): HRSYSTEM_DBNAME, or asked here (Enter = hrsystem). An installation that already
# has a .env keeps its name. The backups are named <name>-<date>-<time>.sql.
$existingCfg = if (Test-Path $script:EnvFile) { Read-HrEnv } else { @{} }
if ($existingCfg['DB_NAME']) { $dbName = $existingCfg['DB_NAME'] }
else {
    $chosenDb = $env:HRSYSTEM_DBNAME
    if (-not $chosenDb -and -not $script:Auto -and [Environment]::UserInteractive) { try { $chosenDb = ([string](Read-Host 'Emri i databazes (Enter = hrsystem; shkronja, numra, _)')).Trim() } catch { $chosenDb = '' } }
    if ($chosenDb) {
        if ($chosenDb -notmatch '^[A-Za-z][A-Za-z0-9_]{0,40}$') { throw "Emri i databazes '$chosenDb' nuk eshte i vlefshem: fillon me shkronje dhe ka vetem shkronja, numra dhe _ (maks. 41)." }
        $dbName = $chosenDb.ToLowerInvariant()
    }
}
$dbUser = 'hrsystem_app'
$taskName = $script:TaskName

function New-Secret([int]$Bytes = 32) {
    $b = New-Object byte[] $Bytes
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($b) } finally { $rng.Dispose() }
    return ([BitConverter]::ToString($b)).Replace('-', '').ToLowerInvariant()
}
function To-Plain([Security.SecureString]$Secure) {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
function Get-FreeTcpPort([int]$Start = 3307, [int]$End = 3399) {
    for ($port = $Start; $port -le $End; $port++) {
        $inUse = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if (!$inUse) { return $port }
    }
    throw "Nuk u gjet port i lire per MySQL ne rangun $Start-$End."
}
function Wait-MySQL([string]$Mysql, [string]$Password = '') {
    $old = $env:MYSQL_PWD
    $env:MYSQL_PWD = $Password
    try {
        for ($i = 0; $i -lt 30; $i++) {
            & $Mysql '--user=root' '--protocol=TCP' '--host=127.0.0.1' "--port=$mysqlPort" '--execute=SELECT 1;' 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { return $true }
            Start-Sleep -Seconds 1
        }
        return $false
    } finally { $env:MYSQL_PWD = $old }
}
function Invoke-RootSql([string]$Mysql, [string]$Password, [string]$Sql) {
    $old = $env:MYSQL_PWD
    $env:MYSQL_PWD = $Password
    try {
        & $Mysql '--user=root' '--protocol=TCP' '--host=127.0.0.1' "--port=$mysqlPort" "--execute=$Sql"
        if ($LASTEXITCODE -ne 0) { throw 'MySQL command deshtoi.' }
    } finally { $env:MYSQL_PWD = $old }
}
function Read-KeyFileValue([string]$Path, [string]$Key) {
    if (!(Test-Path $Path)) { return $null }
    $line = Get-Content $Path | Where-Object { $_ -like "$Key=*" } | Select-Object -First 1
    if (!$line) { return $null }
    return $line.Substring($Key.Length + 1)
}

# At the START: give this administrator and SYSTEM full control of the folder and everything an earlier (or failed) install left in it,
# and clear read-only flags. Only adds rights, never fails the install, so installing again over an old installation always works.
# Since 2026-11-19 without takeown /R and icacls /T, which follow links an ordinary user may have planted in an old, still open folder: Protect-HrTree
# (hr-links.ps1) removes the links, closes the folder to ordinary users and takes over, item by item, whatever Administrators could not open.
# Returns $true only when the folder was closed completely (then no link is left and ordinary users cannot add one, so recursive tools are safe).
function Unlock-Folder([string]$Path, [switch]$KeepHardLinks) {
    $ok = $false
    try {
        if (Get-Command Protect-HrTree -ErrorAction SilentlyContinue) {
            $r = Protect-HrTree -Path $Path -OwnerSid ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value) -KeepHardLinks:$KeepHardLinks
            foreach ($n in $r.Notes) { Write-Host "  $n" -ForegroundColor DarkYellow }
            $ok = $r.Ok
        }
        if ($ok) { & attrib.exe -r (Join-Path $Path '*') /s /d 2>&1 | Out-Null }   # only once no link is left
    } catch { }
    return $ok
}
# At the END (all files are written) the install and data folders are closed with Lock-HrFolders (hr-common.ps1).

# The files with passwords and secrets (.env, the key file): only SYSTEM (the application and its tasks) and Administrators (setup, updater, dashboard) may
# read them; nobody else on this PC. Best effort: a failure is only a warning, never a failed install.
function Protect-File([string]$Path) {
    try { & icacls.exe $Path /inheritance:r /grant:r '*S-1-5-18:F' '*S-1-5-32-544:F' 2>&1 | Out-Null } catch { Write-Host "Leje te skedarit nuk u vendosen: $Path" -ForegroundColor Yellow }
}
# The same for a folder that holds secrets (tools\phpmyadmin-data: while phpMyAdmin is open its PHP session file holds the database password, as
# .env does, and the folder keeps phpMyAdmin's cookie secret). Made and closed BEFORE the dashboard starts, so everything the dashboard writes
# there later inherits it. The dashboard runs elevated (it reads .env too), so it still writes there. Best effort, never a failed install.
function Protect-Folder([string]$Path) {
    try {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
        & icacls.exe $Path /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' 2>&1 | Out-Null
    } catch { Write-Host "Leje te folderit nuk u vendosen: $Path" -ForegroundColor Yellow }
}

New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
[void](Unlock-Folder $installRoot)
# The old MySQL data below is cleaned with takeown /R and icacls /T further down: only when this closed the data folder completely.
$dataSafe = (-not (Test-Path -LiteralPath $dataRoot)) -or (Unlock-Folder $dataRoot -KeepHardLinks)
# Work from the install folder, not from the folder the zip was extracted to: every process started below (the application, the
# dashboard, Notepad) inherits the working folder, and a folder that is some process's working folder cannot be deleted afterwards.
Set-Location $installRoot
try { Start-Transcript -Path $installLog -Append | Out-Null } catch {}

try {
    if (!(Is-Admin)) { throw 'Setup duhet hapur si Administrator.' }
    # The application comes from the client's own GitHub repository when a token is given (the newest version, with the client's own
    # files), otherwise from the copy inside this zip (no token and no internet needed).
    $bundled = Test-Path (Join-Path $payload 'package.json')
    $bundledPayload = $payload
    $clientFile = Join-Path $sourceRoot 'client.json'
    $client = if (Test-Path $clientFile) { Get-Content $clientFile -Raw | ConvertFrom-Json } else { $null }
    $repoName = if ($env:HRSYSTEM_REPO) { [string]$env:HRSYSTEM_REPO } elseif ($client -and $client.repo) { [string]$client.repo } elseif ($bundled) { Get-UpdateRepo } else { 'rogest-network/HRSystem-Template' }   # no token and no client repo: the base program is the newest Release of the Template repo (owner, 2026-10-23)
    $channel = if ($env:HRSYSTEM_CHANNEL) { [string]$env:HRSYSTEM_CHANNEL } elseif ($client -and $client.channel) { [string]$client.channel } else { 'stable' }
    $ghToken = Get-GitHubToken
    # Easiest: a file github-token.txt next to Install.bat holding the token (made in Notepad; deleted once it is saved).
    $tokenFileNextToSetup = Join-Path $sourceRoot 'github-token.txt'
    if (-not $ghToken -and (Test-Path $tokenFileNextToSetup)) { $ghToken = (Get-Content $tokenFileNextToSetup | Where-Object { $_.Trim() } | Select-Object -First 1).Trim() }
    $tokenAsked = $false
    # No token is asked here any more (owner, 2026-10-23): with a token (HRSYSTEM_GITHUB_TOKEN from the USB bootstrap, github-token.txt, gh) the client's own repo is used,
    # without one the Template repo's newest Release (it must then be readable without a token).
    # The repository comes from the token (owner, 2026-10-22): the setup window already found it (HRSYSTEM_REPO); otherwise the token tells.
    if ($ghToken -and -not $env:HRSYSTEM_REPO) { $fromToken = Find-RepoFromToken $ghToken ''; if ($fromToken -and $fromToken -notmatch '-Setup$') { $repoName = $fromToken } }
    if ($ghToken -or -not $bundled) {
        try {
            Banner "Shkarkimi i aplikacionit nga GitHub ($repoName)"
            $rel = Get-TargetRelease $repoName $ghToken $channel
            $asset = Find-AppAsset $rel
            if (-not $asset) { throw "Release $($rel.tag_name) nuk ka skedarin e aplikacionit (HRSystem-<versioni>.zip)." }
            $zipTemp = Join-Path $env:TEMP $asset.name
            Write-Host "Po shkarkohet $($asset.name) ($repoName, $($rel.tag_name))..."
            Save-ReleaseAsset $asset.url $ghToken $zipTemp
            if ((Get-Item $zipTemp).Length -ne $asset.size) { throw 'Shkarkimi nuk u plotesua.' }
            $downloaded = Join-Path $env:TEMP 'hrsystem-payload'
            if (Test-Path $downloaded) { Remove-Item $downloaded -Recurse -Force }
            Expand-Archive -Path $zipTemp -DestinationPath $downloaded -Force
            Remove-Item $zipTemp -Force
            $payload = $downloaded
            if ($ghToken) { Save-GitHubToken $ghToken }
            Save-UpdateSettings $repoName $channel
            Remove-Item $tokenFileNextToSetup -Force -ErrorAction SilentlyContinue   # the token is stored encrypted now
            $tokenGiven = $true
        } catch {
            if (-not $bundled) {
                if (-not $ghToken) { throw "Programi baze nuk u mor nga repo $repoName ($($_.Exception.Message)). Nese repo eshte privat, jepi setup-it nje token GitHub vetem-lexim." }
                throw
            }
            Warn "Shkarkimi nga repo deshtoi ($($_.Exception.Message)): perdoret aplikacioni brenda zip-it."
            $payload = $bundledPayload
            $ghToken = $null
        }
    } elseif (-not $bundled) {
        throw 'Pa token GitHub dhe pa aplikacion brenda zip-it: nuk ka cfare te instalohet.'
    }
    if (!(Test-Path (Join-Path $payload 'DatabaseSchema.sql'))) { throw 'DatabaseSchema.sql mungon.' }
    $version = (Get-Content (Join-Path $payload 'package.json') -Raw | ConvertFrom-Json).version
    Write-Host "HRSystem versioni $version" -ForegroundColor Cyan

    Banner 'Node.js'
    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    if (!$node) {
        # The newest release of the Node.js major the system is tested with (nodejs.org, SHA-256 checked); winget only when that cannot be done.
        Write-Host "Node.js mungon. Po instalohet versioni i fundit i provuar me sistemin (Node.js $script:HrTestedNodeMajor)..."
        if (!(Install-NodeVerified)) {
            if (!(Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'Node.js nuk u instalua dhe winget mungon. Instalo Windows App Installer dhe provo perseri.' }
            Write-Host 'Po provohet me winget...'
            winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements --silent
            if ($LASTEXITCODE -ne 0) { throw 'Instalimi i Node.js deshtoi.' }
        }
        Refresh-Path
    }
    $major = [int]((& node -p "process.versions.node.split('.')[0]").Trim())
    if ($major -lt 20) {
        Write-Host 'Node.js eshte i vjeter. Po behet upgrade...'
        if (!(Install-NodeVerified)) {
            if (!(Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'Kerkohet Node.js 20+.' }
            winget upgrade --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements --silent
        }
        Refresh-Path
        $major = [int]((& node -p "process.versions.node.split('.')[0]").Trim())
        if ($major -lt 20) { throw 'Upgrade i Node.js deshtoi; kerkohet Node.js 20+.' }
    }
    Write-Host "Node.js $(& node -v) - OK" -ForegroundColor Green
    $nodeExe = (Get-Command node.exe -ErrorAction Stop).Source

    # Before MySQL (its installer wants this runtime too) and before the dashboard starts: the dashboard installs PHP + phpMyAdmin by itself and
    # php.exe does not start without it. A failure here never stops the install (Install-VcRuntime in hr-common.ps1).
    Banner 'Visual C++ Runtime'
    try {
        $vcRuntime = Install-VcRuntime
        if ($vcRuntime.Ok) { Ok $vcRuntime.Message } else { Warn $vcRuntime.Message }
    } catch { Warn "Microsoft Visual C++ Runtime nuk u kontrollua ($($_.Exception.Message)). Instalimi vazhdon." }

    Banner 'MySQL binaries'
    $mysql = Find-Exe 'mysql.exe'
    $mysqld = Find-Exe 'mysqld.exe'
    if (!$mysql -or !$mysqld) {
        if (!(Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'MySQL mungon dhe winget nuk u gjet.' }
        Write-Host 'MySQL Server mungon. Po instalohet automatikisht (8.4 LTS)...'
        winget install --id Oracle.MySQL --version 8.4.9 -e --source winget --accept-package-agreements --accept-source-agreements --silent
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'Versioni 8.4.9 nuk u gjet; po provohet versioni i fundit...' -ForegroundColor Yellow
            winget install --id Oracle.MySQL -e --source winget --accept-package-agreements --accept-source-agreements --silent
            if ($LASTEXITCODE -ne 0) { throw 'Instalimi i MySQL Server deshtoi.' }
        }
        Refresh-Path
        $mysql = Find-Exe 'mysql.exe'
        $mysqld = Find-Exe 'mysqld.exe'
    }
    if (!$mysql -or !$mysqld) { throw 'MySQL u instalua, por mysql.exe/mysqld.exe nuk u gjet.' }
    Write-Host "MySQL: $mysqld" -ForegroundColor Green

    Banner 'MySQL HRSystem configuration'
    New-Item -ItemType Directory -Force -Path $dataRoot | Out-Null
    Unlock-Folder $dataRoot

    $existingRootPassword = Read-KeyFileValue $keyFile 'MYSQL_ROOT_PASSWORD'
    $savedPort = Read-KeyFileValue $keyFile 'DB_PORT'
    $isCompleted = Test-Path $marker
    $retryState = (!$isCompleted -and (Test-Path $keyFile) -and ![string]::IsNullOrWhiteSpace($existingRootPassword) -and ($savedPort -as [int]))
    $resumeState = ($isCompleted -or $retryState)
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue

    if ($resumeState) {
        if ($savedPort -and ($savedPort -as [int])) { $mysqlPort = [int]$savedPort }
        else { $mysqlPort = Get-FreeTcpPort 3307 3399 }
        if (Test-Path $mysqlIni) {
            $savedDataLine = Get-Content $mysqlIni | Where-Object { $_ -like 'datadir=*' } | Select-Object -First 1
            if ($savedDataLine) { $mysqlData = $savedDataLine.Substring(8).Replace('/', '\') }
        }
        if ($retryState) { Write-Host 'Instalim i papërfunduar u gjet. Po vazhdohet pa resetuar MySQL.' -ForegroundColor Yellow }
    }

    if (!$resumeState) {
        if ($svc) {
            try { if ($svc.Status -ne 'Stopped') { Stop-Service $serviceName -Force -ErrorAction SilentlyContinue } } catch {}
            & sc.exe delete $serviceName | Out-Null
            Start-Sleep -Seconds 2
        }

        # Stop only stale mysqld processes created by earlier HRSystem install attempts.
        try {
            Get-CimInstance Win32_Process -Filter "Name='mysqld.exe'" -ErrorAction SilentlyContinue |
                Where-Object { $_.CommandLine -and ($_.CommandLine -like '*HRSystemData*' -or $_.CommandLine -like '*mysql-hrsystem.ini*') } |
                ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Seconds 1
        } catch {}

        # Cleanup stale data if possible. If Windows still locks it, use a fresh data folder instead of failing.
        if (Test-Path $mysqlData) {
            try {
                # A data folder that could not be closed completely may hold a link these recursive tools would follow: a fresh folder instead.
                if (-not $dataSafe) { throw 'dosja e te dhenave nuk u mbyll plotesisht' }
                & takeown.exe /F $mysqlData /R /D Y | Out-Null
                & icacls.exe $mysqlData /inheritance:e /grant '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' /T /C | Out-Null
                Remove-Item $mysqlData -Recurse -Force -ErrorAction Stop
            } catch {
                Write-Host 'Folderi i vjeter MySQL eshte i bllokuar. Po perdoret nje data-folder fresh...' -ForegroundColor Yellow
                $suffix = 1
                do {
                    $candidate = Join-Path $dataRoot ("MySQLData-fresh-$suffix")
                    $suffix++
                } while (Test-Path $candidate)
                $mysqlData = $candidate
            }
        }
    }

    if (!$resumeState) {
        $mysqlPort = Get-FreeTcpPort 3307 3399
        Write-Host "MySQL port i zgjedhur automatikisht: $mysqlPort" -ForegroundColor Green
    } else {
        Write-Host "MySQL port ekzistues: $mysqlPort" -ForegroundColor Green
    }

    New-Item -ItemType Directory -Force -Path $mysqlData | Out-Null
    Unlock-Folder $mysqlData

    # Keep MySQL's own error log inside the writable data folder.
    $mysqlLog = Join-Path $mysqlData 'mysql-error.log'
    $baseDir = (Split-Path (Split-Path $mysqld -Parent) -Parent).Replace('\', '/')
    $dataDir = $mysqlData.Replace('\', '/')
    $logPath = $mysqlLog.Replace('\', '/')
    $iniLines = @(
        '[mysqld]'
        "basedir=$baseDir"
        "datadir=$dataDir"
        "port=$mysqlPort"
        'bind-address=127.0.0.1'
        'character-set-server=utf8mb4'
        'collation-server=utf8mb4_unicode_ci'
        "log-error=$logPath"
        'max_connections=100'
        'local-infile=OFF'
    )
    Set-Content -Path $mysqlIni -Value ($iniLines -join [Environment]::NewLine) -Encoding ascii

    if (!(Test-Path (Join-Path $mysqlData 'mysql'))) {
        Write-Host 'Po inicializohet MySQL data directory...'
        & $mysqld "--defaults-file=$mysqlIni" --initialize-insecure --console
        if ($LASTEXITCODE -ne 0) {
            $detail = if (Test-Path $mysqlLog) { (Get-Content $mysqlLog -Tail 25) -join ' | ' } else { '' }
            throw "Inicializimi i MySQL deshtoi. $detail"
        }
    }

    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (!$svc) {
        Write-Host 'Po regjistrohet HRSystemMySQL Windows Service...'
        & $mysqld --install $serviceName "--defaults-file=$mysqlIni"
        if ($LASTEXITCODE -ne 0) { throw 'Regjistrimi i HRSystemMySQL service deshtoi.' }
        Start-Sleep -Seconds 1
        $svc = Get-Service -Name $serviceName -ErrorAction Stop
    }

    if ($svc.Status -ne 'Running') {
        try { Start-Service -Name $serviceName -ErrorAction Stop }
        catch {
            $detail = if (Test-Path $mysqlLog) { (Get-Content $mysqlLog -Tail 30) -join ' | ' } else { '' }
            throw "HRSystemMySQL nuk u nis. $($_.Exception.Message) $detail"
        }
    }

    if (!$resumeState) {
        if (!(Wait-MySQL $mysql '')) {
            $detail = if (Test-Path $mysqlLog) { (Get-Content $mysqlLog -Tail 30) -join ' | ' } else { '' }
            throw "MySQL nuk u be ready pas nisjes. $detail"
        }

        Write-Host 'Krijo MySQL root password per kete instalim.' -ForegroundColor Yellow
        if ($script:Auto) { $p1 = New-Secret 16; $p2 = $p1; Write-Host 'Password-i i MySQL u krijua automatikisht (ruhet te HRSystem-Keys.txt).' }
        else {
        $p1 = Read-Secret 'Krijo nje password te ri per MySQL (minimum 8 karaktere). Ruaje ne nje vend te sigurt.'
        $p2 = Read-Secret 'Konfirmo password-in e MySQL (shkruaje perseri)'
        }
        if ([string]::IsNullOrWhiteSpace($p1) -or $p1.Length -lt 8) { throw 'Password-i duhet te kete minimum 8 karaktere.' }
        if ($p1 -ne $p2) { throw 'Password-at nuk perputhen.' }
        $rootPassword = $p1
        $safeRoot = $rootPassword.Replace("'", "''")
        Invoke-RootSql $mysql '' "ALTER USER 'root'@'localhost' IDENTIFIED BY '$safeRoot'; FLUSH PRIVILEGES;"
    } else {
        $rootPassword = $existingRootPassword
        if ([string]::IsNullOrWhiteSpace($rootPassword)) {
            $rootPassword = if ($script:Auto -and $env:HRSYSTEM_MYSQL_ROOT_PASSWORD) { $env:HRSYSTEM_MYSQL_ROOT_PASSWORD } else { Read-Secret 'Shkruaj MySQL root password ekzistues' }
            if ([string]::IsNullOrWhiteSpace($rootPassword)) { throw 'MYSQL_ROOT_PASSWORD_NEEDED: ky kompjuter ka tashme nje MySQL te instaluar me password; shkruaje te dritarja e setup-it.' }
        }
        if (!(Wait-MySQL $mysql $rootPassword)) { throw 'MySQL root password nuk u verifikua.' }
    }

    Banner 'Database + schema'
    $dbPassword = if ($resumeState) { Read-KeyFileValue $keyFile 'DB_PASSWORD' } else { $null }
    if ([string]::IsNullOrWhiteSpace($dbPassword)) { $dbPassword = New-Secret 24 }
    $appSecret = if ($resumeState) { Read-KeyFileValue $keyFile 'APP_SECRET' } else { $null }
    if ([string]::IsNullOrWhiteSpace($appSecret)) { $appSecret = New-Secret 32 }
    $setupToken = if ($resumeState) { Read-KeyFileValue $keyFile 'SETUP_TOKEN' } else { $null }
    if ([string]::IsNullOrWhiteSpace($setupToken)) { $setupToken = New-Secret 32 }

    if (!$resumeState) {
        $safeDb = $dbPassword.Replace("'", "''")
        $sql = @(
            "CREATE DATABASE IF NOT EXISTS ``$dbName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
            "CREATE USER IF NOT EXISTS '$dbUser'@'127.0.0.1' IDENTIFIED BY '$safeDb';"
            "ALTER USER '$dbUser'@'127.0.0.1' IDENTIFIED BY '$safeDb';"
            "CREATE USER IF NOT EXISTS '$dbUser'@'localhost' IDENTIFIED BY '$safeDb';"
            "ALTER USER '$dbUser'@'localhost' IDENTIFIED BY '$safeDb';"
            "GRANT ALL PRIVILEGES ON ``$dbName``.* TO '$dbUser'@'127.0.0.1';"
            "GRANT ALL PRIVILEGES ON ``$dbName``.* TO '$dbUser'@'localhost';"
            'FLUSH PRIVILEGES;'
        ) -join ' '
        Invoke-RootSql $mysql $rootPassword $sql

        $oldPwd = $env:MYSQL_PWD
        $env:MYSQL_PWD = $dbPassword
        try {
            Get-Content (Join-Path $payload 'DatabaseSchema.sql') -Raw | & $mysql "--user=$dbUser" '--protocol=TCP' '--host=127.0.0.1' "--port=$mysqlPort" $dbName
            if ($LASTEXITCODE -ne 0) { throw 'Importi i DatabaseSchema.sql deshtoi.' }
        } finally { $env:MYSQL_PWD = $oldPwd }
    } else {
        Write-Host 'Database/schema ekziston - po vazhdohet me instalimin e aplikacionit.' -ForegroundColor Green
    }

    Banner "Skedaret e HRSystem $version"
    $releaseDir = Join-Path $script:Releases $version
    New-Item -ItemType Directory -Force -Path $releaseDir | Out-Null
    Copy-Item -Path (Join-Path $payload '*') -Destination $releaseDir -Recurse -Force

    $envLines = @(
        'PORT=3000'
        'DB_HOST=127.0.0.1'
        "DB_PORT=$mysqlPort"
        "DB_NAME=$dbName"
        "DB_USER=$dbUser"
        "DB_PASSWORD=$dbPassword"
        "APP_SECRET=$appSecret"
        "SETUP_TOKEN=$setupToken"
        'HRSYSTEM_ENABLE_DATABASE=true'
    )
    Set-Content -Path $envFile -Value ($envLines -join [Environment]::NewLine) -Encoding ascii
    Protect-File $envFile

    $keyLines = @(
        'HRSYSTEM SELF-HOST KEYS'
        '======================='
        'DB_HOST=127.0.0.1'
        "DB_PORT=$mysqlPort"
        "DB_NAME=$dbName"
        "DB_USER=$dbUser"
        "DB_PASSWORD=$dbPassword"
        ''
        'MYSQL_SERVICE=HRSystemMySQL'
        'MYSQL_ROOT_USER=root'
        "MYSQL_ROOT_PASSWORD=$rootPassword"
        ''
        "APP_SECRET=$appSecret"
        "SETUP_TOKEN=$setupToken"
        ''
        'LOCAL_URL=http://localhost:3000'
        'SETUP_URL=http://localhost:3000/setup'
        "INSTALL_PATH=$installRoot"
    )
    Set-Content -Path $keyFile -Value ($keyLines -join [Environment]::NewLine) -Encoding utf8
    Protect-File $keyFile

    Banner 'Paketat + build (disa minuta)'
    Push-Location $releaseDir
    try {
        # Vite/Rollup needs its Windows native optional package during build.
        if (Test-Path (Join-Path $releaseDir 'node_modules')) { Remove-Item (Join-Path $releaseDir 'node_modules') -Recurse -Force -ErrorAction SilentlyContinue }
        # The release's lockfile is kept: npm ci installs the tested versions (Install-HrPackages in hr-common.ps1).
        if ((Install-HrPackages) -ne 0) { throw 'npm install deshtoi.' }

        npm run build
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'Build-i deshtoi. Po riparohet Rollup native dependency per Windows...' -ForegroundColor Yellow
            npm install --no-save --include=optional '@rollup/rollup-win32-x64-msvc'
            if ($LASTEXITCODE -ne 0) { throw 'Instalimi i Rollup Windows dependency deshtoi.' }
            npm run build
            if ($LASTEXITCODE -ne 0) { throw 'npm run build deshtoi edhe pas Rollup repair.' }
        }

        npm run check
        if ($LASTEXITCODE -ne 0) { throw 'npm run check deshtoi.' }

        # Runtime does not need Vite/Rollup/dev dependencies after dist is built.
        npm prune --omit=dev --omit=optional
        if ($LASTEXITCODE -ne 0) { throw 'npm prune deshtoi.' }
    } finally { Pop-Location }
    $cssProblem = Test-BuiltCss $releaseDir
    if ($cssProblem) { throw $cssProblem }
    Set-Content -Path $script:CurrentFile -Value $version -NoNewline

    Banner 'Windows auto-start'
    $launcher = Join-Path $installRoot 'start-hrsystem.ps1'
    # The launcher starts the release named in current.txt (the updater changes that file) and starts it again if it stops.
    $launcherLines = @(
        '$ErrorActionPreference = ''Continue'''
        "`$root = '$($installRoot.Replace("'", "''"))'"
        '$envFile = Join-Path $root ''.env'''
        'Get-Content $envFile | ForEach-Object {'
        '  $line=$_.Trim(); if(!$line -or $line.StartsWith(''#'')){return}'
        '  $i=$line.IndexOf(''=''); if($i -lt 1){return}'
        '  [Environment]::SetEnvironmentVariable($line.Substring(0,$i).Trim(),$line.Substring($i+1),''Process'')'
        '}'
        'while ($true) {'
        '  $release = (Get-Content (Join-Path $root ''current.txt'') -Raw).Trim()'
        '  if ($release -notmatch ''^[0-9A-Za-z._-]+$'' -or $release.Contains(''..'')) { Start-Sleep -Seconds 30; continue }   # a name that is not a release folder'
        '  $dir = Join-Path (Join-Path $root ''releases'') $release'
        '  Set-Location $dir'
        "  & '$($nodeExe.Replace("'", "''"))' (Join-Path `$dir 'server.mjs') >> (Join-Path `$root 'HRSystem-Server.log') 2>&1"
        '  Start-Sleep -Seconds 3'
        '}'
    )
    Set-Content -Path $launcher -Value ($launcherLines -join [Environment]::NewLine) -Encoding utf8

    foreach ($f in @('hr-common.ps1', 'hr-links.ps1', 'updater.ps1', 'update.bat', 'sql-import.ps1', 'sql-import.bat', 'uninstall.ps1', 'uninstall-wizard.ps1', 'LEXO-ME-PARE.txt')) {
        if (Test-Path (Join-Path $sourceRoot $f)) { Copy-Item (Join-Path $sourceRoot $f) (Join-Path $installRoot $f) -Force }
    }
    # The zip shows only Install.bat, Uninstall.bat and Dashboard.bat (the rest is in its files folder); the last two are kept here too.
    $zipRoot = if ((Split-Path $sourceRoot -Leaf) -eq 'files') { Split-Path $sourceRoot -Parent } else { $sourceRoot }
    foreach ($f in @('Uninstall.bat', 'Dashboard.bat')) {
        if (Test-Path (Join-Path $zipRoot $f)) { Copy-Item (Join-Path $zipRoot $f) (Join-Path $installRoot $f) -Force }
    }

    if (!(Test-Path $launcher)) { throw 'start-hrsystem.ps1 nuk u krijua.' }
    if (!(Test-Path $nodeExe)) { throw "Node executable nuk u gjet: $nodeExe" }

    $powerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (!(Test-Path $powerShellExe)) { throw "Windows PowerShell nuk u gjet: $powerShellExe" }

    $serverLog = Join-Path $installRoot 'HRSystem-Server.log'
    if (!(Test-Path $serverLog)) { New-Item -ItemType File -Path $serverLog -Force | Out-Null }

    # Stop only HRSystem node processes left by earlier installer attempts.
    Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.CommandLine -and $_.CommandLine -like "*$installRoot*server.mjs*" -and $_.CommandLine -notlike '*\manager\*') {
            try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
        }
    }

    # Start the server directly once during installation: a real process and log to check before relying on Task Scheduler.
    try {
        $directArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`""
        $directProc = Start-Process -FilePath $powerShellExe -ArgumentList $directArgs -WindowStyle Hidden -PassThru
    } catch {
        throw "Nisja direkte e HRSystem server deshtoi: $($_.Exception.Message)"
    }

    Banner 'Health check'
    $healthy = Wait-Health 3000 60
    if (!$healthy) {
        $serverDetail = if (Test-Path $serverLog) { (Get-Content $serverLog -Tail 40 -ErrorAction SilentlyContinue) -join ' | ' } else { 'HRSystem-Server.log nuk u krijua.' }
        throw "HRSystem server nuk u be healthy ne portin 3000. Detaje: $serverDetail"
    }

    # Only after the server has proven healthy, create the startup task.
    try {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        $taskArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`""
        $action = New-ScheduledTaskAction -Execute $powerShellExe -Argument $taskArgs
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'HRSystem self-hosted server' -Force | Out-Null
    } catch {
        throw "Krijimi i HRSystem auto-start task deshtoi: $($_.Exception.Message)"
    }

    # The dashboard (health, speed, versions, backups, update, SQL) on this computer: http://127.0.0.1:3500, starts with Windows
    # (owner, 2026-10-21). It listens only on 127.0.0.1. Its files are taken from the Dashboard repo (public, no token), always the newest
    # (owner, 2026-10-23); only when that is not reachable (no internet) the copy inside the setup zip (manager/) is used. The shortcut is on the desktop.
    try {
        $managerSrc = Join-Path $sourceRoot 'manager'
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $dashZip = Join-Path $env:TEMP 'hrsystem-dashboard.zip'; $dashTmp = Join-Path $env:TEMP 'hrsystem-dashboard'
            Remove-Item $dashZip, $dashTmp -Recurse -Force -ErrorAction SilentlyContinue
            Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/rogest-network/HRSystem-Dashboard/archive/refs/heads/main.zip' -OutFile $dashZip -TimeoutSec 60
            Expand-Archive -Path $dashZip -DestinationPath $dashTmp -Force
            $dashInner = Get-ChildItem $dashTmp -Directory | Select-Object -First 1
            if ($dashInner -and (Test-Path (Join-Path $dashInner.FullName 'server.mjs')) -and (Test-Path (Join-Path $dashInner.FullName 'public\index.html'))) {
                $managerSrc = $dashInner.FullName
                Ok 'Dashboard-i u mor nga repo i dashboard-it (versioni i fundit).'
            } else { Warn 'Repo i dashboard-it nuk ka skedarët e pritur: përdoret kopja e setup-it.' }
        } catch { Warn "Dashboard-i nuk u mor nga repo ($($_.Exception.Message)): përdoret kopja e setup-it." }
        if (Test-Path (Join-Path $managerSrc 'server.mjs')) {
            $managerDir = Join-Path $installRoot 'manager'
            New-Item -ItemType Directory -Force -Path $managerDir | Out-Null
            Copy-Item -Path (Join-Path $managerSrc '*') -Destination $managerDir -Recurse -Force
            Copy-Item -Path (Join-Path $sourceRoot 'manager\instances.example.json') -Destination $managerDir -Force -ErrorAction SilentlyContinue   # the repo does not carry it
            $dashTask = "$taskName-Dashboard"
            Unregister-ScheduledTask -TaskName $dashTask -Confirm:$false -ErrorAction SilentlyContinue
            # It runs as the administrator who installed (at sign-in, elevated, hidden): its Hap buttons open Explorer on that desktop and
            # it can start/stop the application, run the updater and the SQL tools.
            $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            $dashLog = Join-Path $installRoot 'Dashboard.log'
            $dashCommand = "Set-Location '$managerDir'; & '$nodeExe' server.mjs *>> '$dashLog'"
            $dAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command `"$dashCommand`""
            $dTrigger = New-ScheduledTaskTrigger -AtLogOn -User $me
            $dPrincipal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Highest
            $dSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
            Register-ScheduledTask -TaskName $dashTask -Action $dAction -Trigger $dTrigger -Principal $dPrincipal -Settings $dSettings -Description 'HRSystem Dashboard (127.0.0.1:3500)' -Force | Out-Null
            $dashUrlFile = Join-Path $installRoot 'dashboard-url.txt'
            Remove-Item $dashUrlFile -Force -ErrorAction SilentlyContinue
            # The dashboard installs PHP + phpMyAdmin into tools\ by itself, 30 s after it starts: its data folder is closed first.
            Protect-Folder (Join-Path $installRoot 'tools\phpmyadmin-data')
            $dashStarted = Get-Date
            # Started directly now (a hidden process of this administrator), not through Task Scheduler: that only matters at the next
            # sign-in. A task can sit "Queued" and never start, which left the dashboard closed after the install.
            Start-Process -FilePath $powerShellExe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-Command', $dashCommand)
            # The dashboard picks a free port itself (3500, else the next one) and writes its address here.
            for ($i = 0; $i -lt 30 -and !(Test-Path $dashUrlFile); $i++) { Start-Sleep -Seconds 1 }
            if (Test-Path $dashUrlFile) {
                $dashboardUrl = (Get-Content $dashUrlFile -Raw).Trim()
                # The shortcut runs Dashboard.bat (it starts the dashboard when it is off, then opens its fixed address), so it works after every restart (owner, 2026-10-23).
                try {
                    $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut('C:\Users\Public\Desktop\HRSystem Dashboard.lnk')
                    $lnk.TargetPath = (Join-Path $installRoot 'Dashboard.bat'); $lnk.WorkingDirectory = $installRoot; $lnk.WindowStyle = 7; $lnk.Description = 'HRSystem Dashboard'; $lnk.IconLocation = 'shell32.dll,13'; $lnk.Save()
                    Remove-Item 'C:\Users\Public\Desktop\HRSystem Dashboard.url' -Force -ErrorAction SilentlyContinue
                } catch { Set-Content -Path 'C:\Users\Public\Desktop\HRSystem Dashboard.url' -Value "[InternetShortcut]`r`nURL=$dashboardUrl`r`n" -Encoding ascii }
                Ok "Dashboard-i u instalua: $dashboardUrl (shortcut `"HRSystem Dashboard`" ne desktop, nis kur hyn ne Windows)."
            } else {
                Warn "Dashboard-i nuk u nis brenda 30 sekondave. Shiko $installRoot\Dashboard.log; aplikacioni punon normalisht."
                if (Test-Path (Join-Path $installRoot 'Dashboard.log')) { Get-Content (Join-Path $installRoot 'Dashboard.log') -Tail 8 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray } }
            }
        }
    } catch {
        Warn "Dashboard-i nuk u instalua: $($_.Exception.Message). Aplikacioni punon normalisht."
    }

    New-Item -ItemType File -Path $marker -Force | Out-Null

    # ---- Optional: the Cloudflare Tunnel (was network-Install.bat), in the same setup ----
    Banner 'Rrjeti: Cloudflare Tunnel (opsionale)'
    Write-Host 'Nese do qe HRSystem te hapet nga interneti me adrese tende (p.sh. https://staff.domaini-yt.com):' -ForegroundColor Yellow
    Write-Host '  krijo nje Tunnel ne Cloudflare (Zero Trust > Networks > Tunnels), shto Public Hostname me shenjestre http://localhost:3000,' -ForegroundColor Yellow
    Write-Host '  dhe paste ketu Tunnel Token (ose komanden "cloudflared service install ..."). Enter = kalo, mund ta shtosh me vone.' -ForegroundColor Yellow
    $tunnelInput = if ($script:Auto) { ([string]$env:HRSYSTEM_TUNNEL_TOKEN).Trim() } else { (Read-Secret 'Cloudflare Tunnel Token (ose komanda cloudflared service install ...). Shtyp Kalo nese s do ta vendosesh tani.').Trim() }
    $tunnelDone = $false
    if ($tunnelInput) {
        $token = $tunnelInput
        if ($token -match '(?i)service\s+install\s+(.+)$') { $token = $Matches[1].Trim().Trim('"').Trim("'") }
        if ($token.Length -lt 20) { Warn 'Tunnel Token duket i pavlefshem; tuneli u kalua.' }
        else {
            $cloudflared = Find-Exe 'cloudflared.exe'
            if (!$cloudflared) {
                foreach ($p in @('C:\Program Files\cloudflared\cloudflared.exe', 'C:\Program Files (x86)\cloudflared\cloudflared.exe')) { if (Test-Path $p) { $cloudflared = $p } }
            }
            if (!$cloudflared) {
                if (!(Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'cloudflared mungon dhe winget nuk u gjet.' }
                Write-Host 'cloudflared mungon. Po instalohet automatikisht...'
                winget install --id Cloudflare.cloudflared -e --source winget --accept-package-agreements --accept-source-agreements --silent
                Refresh-Path
                foreach ($p in @('C:\Program Files\cloudflared\cloudflared.exe', 'C:\Program Files (x86)\cloudflared\cloudflared.exe')) { if (Test-Path $p) { $cloudflared = $p } }
                if (!$cloudflared) { $cloudflared = Find-Exe 'cloudflared.exe' }
            }
            if (!$cloudflared) { throw 'cloudflared.exe nuk u gjet pas instalimit.' }
            if (Get-Service -Name 'cloudflared' -ErrorAction SilentlyContinue) {
                try { Stop-Service -Name 'cloudflared' -Force -ErrorAction SilentlyContinue } catch {}
                & $cloudflared service uninstall 2>$null | Out-Null
                Start-Sleep -Seconds 2
            }
            & $cloudflared service install $token
            if ($LASTEXITCODE -ne 0) { throw 'cloudflared service install deshtoi.' }
            Start-Sleep -Seconds 3
            Set-Service -Name 'cloudflared' -StartupType Automatic
            if ((Get-Service -Name 'cloudflared').Status -ne 'Running') { Start-Service -Name 'cloudflared' }
            Ok 'Cloudflare Tunnel u lidh dhe niset vete me Windows.'
            $tunnelDone = $true
        }
    }

    # The repository for later updates: the one found from the token (HRSYSTEM_REPO / $repoName when a token was used), else client.json.
    $clientFileForUpdates = Join-Path $sourceRoot 'client.json'
    if ($ghToken -and $repoName) { Save-UpdateSettings $repoName $channel }
    elseif (Test-Path $clientFileForUpdates) {
        try {
            $cj = Get-Content $clientFileForUpdates -Raw | ConvertFrom-Json
            if ($cj.repo) { Save-UpdateSettings ([string]$cj.repo) $(if ($cj.channel) { [string]$cj.channel } else { 'stable' }) }
        } catch { }
    }

    # ---- Optional: updates from GitHub (update.bat) ----
    Banner 'Perditesimet nga GitHub (opsionale)'
    Write-Host 'Me nje token GitHub vetem-lexim (fine-grained, vetem Contents: read mbi repo-n), update.bat merr vete versionin e ri.' -ForegroundColor Yellow
    Write-Host 'Tokeni ruhet i enkriptuar ne kete kompjuter. Enter = kalo (update.bat pastaj punon me nje zip lokal).' -ForegroundColor Yellow
    if ($tokenGiven) { Ok 'Tokeni GitHub u ruajt gjate shkarkimit.'; $ghToken = $null } elseif ($tokenAsked) { $ghToken = $null } else {
        $ghToken = Read-Secret 'Instalimi NUK ka nevoje per token. Token GitHub vetem-lexim duhet vetem per perditesime te ardhshme: shtyp Kalo (mund ta shtosh me vone).'
    }
    if (![string]::IsNullOrWhiteSpace($ghToken)) {
        Save-GitHubToken $ghToken
        $repo = Resolve-UpdateRepo $ghToken.Trim() (Get-UpdateSettings)   # the repo the token reads (saved to update.json)
        Save-UpdateSettings $repo ((Get-UpdateSettings).channel)
        try {
            $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ Authorization = "Bearer $($ghToken.Trim())"; 'User-Agent' = 'regina-setup'; Accept = 'application/vnd.github+json' }
            Ok "GitHub OK: versioni i fundit ne $repo eshte $($r.tag_name)."
        } catch { Warn "Tokeni u ruajt, por GitHub nuk u pergjigj ($($_.Exception.Message)). Kontrollo tokenin dhe te drejtat." }
    }

    # The files and the one folder that hold passwords are closed: .env, the key file (Protect-File) and tools\phpmyadmin-data (Protect-Folder).
    # The install and data folders: no write for ordinary users of the PC (the app runs from here as SYSTEM), the owner's own account keeps
    # Modify so nothing says "access denied" to him (owner, 2026-10-21, why the old full lock was dropped). Lock-HrFolders in hr-common.ps1.
    Banner 'Lejet e folderave'
    $meId = [Security.Principal.WindowsIdentity]::GetCurrent()
    Lock-HrFolders -Root $installRoot -Data $dataRoot -OwnerSid $meId.User.Value -Force
    Write-Host "Qasje e plote pa pyetje ka vetem llogaria $($meId.Name) (dhe administratoret kur hapen si Administrator); perdoruesit e tjere te ketij kompjuteri nuk mund te ndryshojne asgje ketu." -ForegroundColor DarkGray

    # ---- The database tools: PHP + phpMyAdmin (the dashboard's "Hap databazen"), ready before the owner's first click (owner, 2026-11-12) ----
    # The dashboard downloads and installs them itself (the only downloader); here the setup waits for it and checks php.exe. Never a failed
    # install: without internet, or on a slow PC, the dashboard goes on by itself (every 30 minutes, or at the first click on the button).
    # HRSYSTEM_TOOLS_WAIT = seconds to wait (tests; 0 = only look).
    Banner 'Mjetet e databazes (PHP, phpMyAdmin)'
    $toolsWait = 240
    if ($env:HRSYSTEM_TOOLS_WAIT -match '^\d+$') { $toolsWait = [int]$env:HRSYSTEM_TOOLS_WAIT }
    $dashUp = [bool]$dashboardUrl -or (Test-Path (Join-Path $installRoot 'dashboard-url.txt'))   # the file appears once the dashboard listens
    if ($dashUp -and $dashStarted) { $dbTools = Wait-DbTools -Root $installRoot -Seconds $toolsWait -Since $dashStarted }
    else { $dbTools = Wait-DbTools -Root $installRoot -Seconds 0; if (-not $dbTools.Ready) { $dbTools.Reason = 'dashboard-i nuk u nis (hape nga shortcut-i ne desktop)' } }
    if ($dbTools.Ready) {
        $dbToolsLine = "phpMyAdmin $($dbTools.Version), $($dbTools.Line)"
        Ok "Mjetet e databazes - gati: $dbToolsLine (butoni `"Hap databazen`" te dashboard-i)."
        Write-Host "DBTOOLS=READY|$dbToolsLine"
    } else {
        $dbToolsWhy = ([string]$dbTools.Reason).TrimEnd('.', ' ')
        Warn "Mjetet e databazes nuk jane gati ende: $dbToolsWhy."
        Warn 'Instalimi mbaron normalisht: dashboard-i i instalon vete (provon cdo 30 minuta, ose menjehere kur shtyp "Hap databazen"); kerkohet internet.'
        Write-Host "DBTOOLS=LATER|$dbToolsWhy"
    }

    try { Stop-Transcript | Out-Null } catch {}   # the log must not hold the keys shown below
    Banner 'READY'
    Write-Host "HRSystem $version u instalua ne $installRoot" -ForegroundColor Green
    Write-Host "MySQL service: HRSystemMySQL / port $mysqlPort" -ForegroundColor Green
    if ($dbTools.Ready) { Write-Host "Databaza (phpMyAdmin): gati - $dbToolsLine" -ForegroundColor Green } else { Write-Host 'Databaza (phpMyAdmin): instalohet vete nga dashboard-i (kerkon internet).' -ForegroundColor Yellow }
    Write-Host "Keys: $keyFile" -ForegroundColor Yellow
    Write-Host "SETUP_TOKEN: $setupToken" -ForegroundColor Yellow
    $shownUrl = if ($dashboardUrl) { $dashboardUrl } else { 'http://127.0.0.1:3500' }
    Write-Host "DASHBOARD-i: $shownUrl (shortcut `"HRSystem Dashboard`" ne desktop; adresa ruhet edhe te $installRoot\dashboard-url.txt)." -ForegroundColor Green
    Write-Host 'Aty zgjedh: krijo pronarin (/setup) OSE importo fillimisht databazen e vjeter, pastaj hap hyrjen.' -ForegroundColor Green
    Write-Host "Perditesim: $installRoot\update.bat   |   SQL: $installRoot\sql-import.bat" -ForegroundColor Green
    if (!$tunnelDone) { Write-Host 'Tuneli Cloudflare nuk u vendos; hape perseri Install.bat per ta shtuar.' -ForegroundColor DarkGray }
    if (-not $script:Auto) { try { Start-Process notepad.exe $keyFile } catch {} }
    # The dashboard (not the application) opens after the install. Its page offers /setup (token filled in) or the database import.
    if ($dashboardUrl -and -not $script:Auto) { try { Start-Process $dashboardUrl } catch {} }
    exit 0
}
catch {
    try { Stop-Transcript | Out-Null } catch {}
    Write-Host "`nGABIM: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Message -match 'denied|Access') {
        # Shown so a photo of this screen tells us exactly what blocks the write.
        Write-Host '--- Diagnostikim (leje) ---' -ForegroundColor DarkGray
        try { & icacls.exe $installRoot 2>&1 | Select-Object -First 8 | ForEach-Object { Write-Host "$_" -ForegroundColor DarkGray } } catch {}
        try { Get-ChildItem $installRoot -Force -ErrorAction SilentlyContinue | Select-Object -First 12 | ForEach-Object { Write-Host ("{0}  {1}  {2}" -f $_.Mode, $_.Attributes, $_.Name) -ForegroundColor DarkGray } } catch {}
    }
    Write-Host "Log: $installLog" -ForegroundColor Yellow
    if (Test-Path $mysqlLog) { Write-Host "MySQL log: $mysqlLog" -ForegroundColor Yellow }
    exit 1
}
