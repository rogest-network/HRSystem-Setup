# HRSystem test environment on this PC: several companies side by side, each its own copy, port, database and GitHub repo.
# NOTHING here touches the real install (C:\HRSystem, its MySQL, its tunnel): everything lives in C:\HRTest with its own MySQL (port 3398).
#   test-env.bat add <name> <owner/repo> [stable|test]   makes the company (e.g. regina rogest-network/HRSystem-ReginaCenter test)
#   test-env.bat update <name|all>                       installs the newest Release of its repo
#   test-env.bat start|stop [name|all]                   starts / stops the test database and the companies
#   test-env.bat list                                    names, ports, versions, health
#   test-env.bat remove <name>                           stops it and deletes its folder and database
param([string]$Action = 'list', [string]$Name = '', [string]$Repo = '', [string]$Channel = 'test')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$base = 'C:\HRTest'
$dbPort = 3398
$dbRoot = 'x'   # localhost only, test data only
$myDir = Join-Path $base 'mysql'
$registry = Join-Path $base 'companies.json'

function Say([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c }
function New-Secret([int]$n) { -join ((48..57) + (65..90) + (97..122) | Get-Random -Count $n | ForEach-Object { [char]$_ }) }
function Find-Mysql([string]$exe) {
  $dir = Get-ChildItem 'C:\Program Files\MySQL' -Directory -Filter 'MySQL Server*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
  if (-not $dir) { throw 'MySQL nuk u gjet ne C:\Program Files\MySQL.' }
  return Join-Path $dir.FullName "bin\$exe"
}
function Get-Companies { if (Test-Path $registry) { $j = Get-Content $registry -Raw | ConvertFrom-Json; return @(foreach ($x in $j) { $x }) } else { return @() } }
function Save-Companies($list) { New-Item -ItemType Directory -Force -Path $base | Out-Null; $arr = @($list | Where-Object { $_ -and $_.name }); $text = "[" + ((@($arr | ForEach-Object { ConvertTo-Json -InputObject $_ -Depth 4 -Compress })) -join ",") + "]"; Set-Content $registry $text -Encoding utf8 }
function Test-Port([int]$p) { try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', $p); $c.Close(); return $true } catch { return $false } }
function Test-Health([int]$p) { try { return ((Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$p/api/health" -TimeoutSec 3).Content -match '"ok":true') } catch { return $false } }

function Start-TestDb {
  if (Test-Port $dbPort) { return }
  $mysqld = Find-Mysql 'mysqld.exe'
  $data = Join-Path $myDir 'data'
  if (-not (Test-Path (Join-Path $data 'mysql'))) {
    Say 'Po krijohet MySQL i testit (nje here)...' Cyan
    New-Item -ItemType Directory -Force -Path $data | Out-Null
    & $mysqld --no-defaults --initialize-insecure "--datadir=$data" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'MySQL i testit nuk u inicializua.' }
  }
  Start-Process -FilePath $mysqld -ArgumentList "--no-defaults --datadir=`"$data`" --port=$dbPort --bind-address=127.0.0.1 --mysqlx=OFF --console" -WindowStyle Hidden -RedirectStandardError (Join-Path $myDir 'mysqld.log') | Out-Null
  for ($i = 0; $i -lt 60 -and -not (Test-Port $dbPort); $i++) { Start-Sleep -Seconds 1 }
  if (-not (Test-Port $dbPort)) { throw 'MySQL i testit nuk u nis (shiko C:\HRTest\mysql\mysqld.log).' }
  # root has no password after --initialize-insecure; give it the test one (once)
  $mysql = Find-Mysql 'mysql.exe'
  & $mysql -uroot --protocol=TCP -P $dbPort -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$dbRoot'" 2>$null | Out-Null
}
function Stop-TestDb {
  if (-not (Test-Port $dbPort)) { return }
  $env:MYSQL_PWD = $dbRoot
  try { & (Find-Mysql 'mysqladmin.exe') -uroot --protocol=TCP -P $dbPort shutdown 2>&1 | Out-Null } finally { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue }
}
function Invoke-Sql([string]$sql) {
  $old = $env:MYSQL_PWD; $env:MYSQL_PWD = $dbRoot
  try { & (Find-Mysql 'mysql.exe') -uroot --protocol=TCP -P $dbPort -e $sql 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { throw "SQL deshtoi: $sql" } } finally { $env:MYSQL_PWD = $old }
}
function Root-Of([string]$n) { Join-Path $base $n }

# The selector on every login page: each company lists the others by address (HRSYSTEM_COMPANIES in .env).
function Write-Env($c, $all) {
  $list = @($all | ForEach-Object { [ordered]@{ id = $_.name; name = $_.name; url = "http://localhost:$($_.port)" } })
  $json = ConvertTo-Json -InputObject $list -Compress
  @("PORT=$($c.port)", 'DB_HOST=127.0.0.1', "DB_PORT=$dbPort", "DB_NAME=hrtest_$($c.name)", "DB_USER=hrtest_$($c.name)", "DB_PASSWORD=$($c.dbPassword)",
    "APP_SECRET=$($c.appSecret)", "SETUP_TOKEN=$($c.setupToken)", 'HRSYSTEM_ENABLE_DATABASE=true', "APP_ORIGIN=http://localhost:$($c.port)", "HRSYSTEM_COMPANIES=$json") |
    Set-Content (Join-Path (Root-Of $c.name) '.env') -Encoding ascii
}
function Write-Launcher([string]$n) {
  $root = Root-Of $n
  $node = (Get-Command node.exe -ErrorAction Stop).Source
  @"
`$ErrorActionPreference = 'Continue'
`$root = '$root'
Get-Content (Join-Path `$root '.env') | ForEach-Object {
  `$line = `$_.Trim(); if (!`$line -or `$line.StartsWith('#')) { return }
  `$i = `$line.IndexOf('='); if (`$i -lt 1) { return }
  [Environment]::SetEnvironmentVariable(`$line.Substring(0, `$i).Trim(), `$line.Substring(`$i + 1), 'Process')
}
while (`$true) {
  `$release = (Get-Content (Join-Path `$root 'current.txt') -Raw).Trim()
  if (`$release -notmatch '^[0-9A-Za-z._-]+`$' -or `$release.Contains('..')) { Start-Sleep -Seconds 30; continue }
  `$dir = Join-Path (Join-Path `$root 'releases') `$release
  Set-Location `$dir
  if (Test-Path (Join-Path `$dir 'server.mjs')) { & '$node' (Join-Path `$dir 'server.mjs') >> (Join-Path `$root 'HRSystem-Server.log') 2>&1 }
  Start-Sleep -Seconds 3
}
"@ | Set-Content (Join-Path $root 'start-hrsystem.ps1') -Encoding utf8
}
function Start-Company($c) {
  if (Test-Health $c.port) { return }
  Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path (Root-Of $c.name) 'start-hrsystem.ps1')`"" -WindowStyle Hidden | Out-Null
}
function Stop-Company($c) {
  $root = Root-Of $c.name
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -like "*$root\*" -and ($_.Name -eq 'node.exe' -or $_.CommandLine -like '*start-hrsystem.ps1*') -and $_.ProcessId -ne $PID } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch { } }
}
# The shared updater of the installer runs against this company's folder (HRSYSTEM_ROOT): backup, build, migrations, switch, health check.
function Run-Updater($c, [string]$zip = '') {
  $env:HRSYSTEM_ROOT = Root-Of $c.name; $env:HRSYSTEM_DATA = (Root-Of $c.name) + 'Data'; $env:HRSYSTEM_TASK = "HRTest-$($c.name)"; $env:HRSYSTEM_AUTO = '1'
  try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path (Root-Of $c.name) 'updater.ps1') @(if ($zip) { $zip }) | Out-Host; return [int]$LASTEXITCODE }
  finally { Remove-Item Env:HRSYSTEM_ROOT, Env:HRSYSTEM_DATA, Env:HRSYSTEM_TASK, Env:HRSYSTEM_AUTO -ErrorAction SilentlyContinue }
}
# The "local" company runs the code in Setup\Claude Studio\Source as it is NOW (no GitHub, nothing published): a copy without node_modules, dist, tests,
# .env and tools, its version renamed <version>-test<yyMMddHHmm>, zipped; the standard updater installs that zip (build, migrations, switch, health check).
$sourceDir = Join-Path (Split-Path -Parent $here) 'Claude Studio\Source'
function Build-LocalZip {
  $stage = Join-Path $env:TEMP ('hrtest-src-' + [guid]::NewGuid().ToString('N'))
  & robocopy.exe $sourceDir $stage /E /XD node_modules dist tests tools .git .vite /XF .env /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw 'Kopja e Source/ deshtoi.' }
  $pkg = Join-Path $stage 'package.json'
  $text = [IO.File]::ReadAllText($pkg)
  $ver = ([regex]::Match($text, '"version"\s*:\s*"([^"]+)"')).Groups[1].Value
  $text = [regex]::Replace($text, '"version"\s*:\s*"[^"]+"', ('"version": "' + $ver + '-test' + (Get-Date -Format 'yyMMddHHmm') + '"'), 1)
  [IO.File]::WriteAllText($pkg, $text)
  $zip = Join-Path $env:TEMP ('hrtest-' + [guid]::NewGuid().ToString('N') + '.zip')
  Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force
  Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
  return $zip
}
function Install-Company($c) {
  if ($c.repo -eq 'local') {
    $zip = Build-LocalZip
    try { return (Run-Updater $c $zip) } finally { Remove-Item $zip -Force -ErrorAction SilentlyContinue }
  }
  return (Run-Updater $c)
}
function Get-One([string]$n) { $c = Get-Companies | Where-Object { $_.name -eq $n }; if (-not $c) { throw "Kompania '$n' nuk ekziston (test-env.bat list)." }; return $c }
function Pick([string]$n) { if ($n -eq 'all' -or -not $n) { return Get-Companies } else { return @(Get-One $n) } }

switch ($Action) {
  'add' {
    if ($Name -notmatch '^[a-z][a-z0-9]{1,15}$') { throw 'Emri: shkronja te vogla dhe numra (2-16), p.sh. regina, template, urban.' }
    if ($Repo -ne 'local' -and $Repo -notmatch '^[\w.-]+/[\w.-]+$') { throw 'Repo: owner/emri (p.sh. rogest-network/HRSystem-ReginaCenter) ose local (kodi i Source/ ne kete PC).' }
    if ($Channel -notin @('stable', 'test')) { throw 'Kanali: stable ose test.' }
    $all = @(Get-Companies)
    if ($all | Where-Object { $_.name -eq $Name }) { throw "Kompania '$Name' ekziston." }
    $port = 3101; while (($all | Where-Object { $_.port -eq $port }) -or (Test-Port $port)) { $port++ }
    Start-TestDb
    $c = [pscustomobject]@{ name = $Name; repo = $Repo; channel = $Channel; port = $port; dbPassword = (New-Secret 24); appSecret = (New-Secret 48); setupToken = (New-Secret 40) }
    $root = Root-Of $Name
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'releases\0.0.0') | Out-Null
    Set-Content (Join-Path $root 'current.txt') '0.0.0' -NoNewline
    foreach ($f in 'hr-common.ps1', 'hr-links.ps1', 'updater.ps1') { Copy-Item (Join-Path $here $f) (Join-Path $root $f) -Force }
    Set-Content (Join-Path $root 'update.json') (ConvertTo-Json @{ repo = $Repo; channel = $Channel }) -Encoding ascii
    Invoke-Sql "CREATE DATABASE IF NOT EXISTS ``hrtest_$Name`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
    Invoke-Sql "CREATE USER IF NOT EXISTS 'hrtest_$Name'@'127.0.0.1' IDENTIFIED BY '$($c.dbPassword)'"
    Invoke-Sql "CREATE USER IF NOT EXISTS 'hrtest_$Name'@'localhost' IDENTIFIED BY '$($c.dbPassword)'"
    Invoke-Sql "GRANT ALL ON ``hrtest_$Name``.* TO 'hrtest_$Name'@'127.0.0.1'; GRANT ALL ON ``hrtest_$Name``.* TO 'hrtest_$Name'@'localhost'"
    $all = @($all) + $c
    Save-Companies $all
    foreach ($x in $all) { Write-Env $x $all; if ($x.name -ne $Name -and (Test-Health $x.port)) { Stop-Company $x; Start-Sleep -Seconds 2; Start-Company $x } }   # every company's selector now lists the new one (the others restart to read it)
    Write-Launcher $Name
    Say "Po instalohet $Name nga $Repo..." Cyan
    if ($Repo -eq 'local') {
      # the local code carries its own base schema: load it before the first install
      $old = $env:MYSQL_PWD; $env:MYSQL_PWD = $dbRoot
      try { Get-Content (Join-Path $sourceDir 'DatabaseSchema.sql') -Raw -Encoding UTF8 | & (Find-Mysql 'mysql.exe') -uroot --protocol=TCP -P $dbPort --default-character-set=utf8mb4 "hrtest_$Name" } finally { $env:MYSQL_PWD = $old }
    }
    $code = Install-Company $c
    if ($code -ne 0 -and $Repo -ne 'local') {
      # a new database is empty: the migrations need the base schema first (what the Windows setup does); load it from the downloaded release, then try again
      $schema = Get-ChildItem (Join-Path $root 'releases') -Directory | ForEach-Object { Join-Path $_.FullName 'DatabaseSchema.sql' } | Where-Object { Test-Path $_ } | Select-Object -First 1
      $env:MYSQL_PWD = $dbRoot
      try { $tables = @(& (Find-Mysql 'mysql.exe') -uroot --protocol=TCP -P $dbPort -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='hrtest_$Name' AND table_name='users'") } finally { Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue }
      $empty = -not ($tables | Where-Object { "$_" -match '^[1-9]' })
      if ($schema -and $empty) {
        Say 'Databaza eshte bosh: po ngarkohet skema baze, pastaj provohet perseri...' Cyan
        Invoke-Sql "DROP TABLE IF EXISTS ``hrtest_$Name``.schema_migrations"   # the failed first run made it; the schema creates it again
        $old = $env:MYSQL_PWD; $env:MYSQL_PWD = $dbRoot
        try { Get-Content $schema -Raw -Encoding UTF8 | & (Find-Mysql 'mysql.exe') -uroot --protocol=TCP -P $dbPort --default-character-set=utf8mb4 "hrtest_$Name" } finally { $env:MYSQL_PWD = $old }
        $code = Install-Company $c
      }
    }
    if ($code -ne 0) { throw "Instalimi i '$Name' deshtoi (shiko $root\Updater.log)." }
    Start-Company $c
    Say 'Po ngarkohen te dhenat testuese...' Cyan
    & (Get-Command node.exe).Source (Join-Path $here 'test-env-seed.mjs') $Name | Out-Host
    Say "U krye. ${Name}: http://localhost:$port/setup  (SETUP_TOKEN: $($c.setupToken))" Green
  }
  'update' {
    Start-TestDb
    foreach ($c in (Pick $Name)) {
      Say "== $($c.name) ==" Cyan
      foreach ($f in 'hr-common.ps1', 'hr-links.ps1', 'updater.ps1') { Copy-Item (Join-Path $here $f) (Join-Path (Root-Of $c.name) $f) -Force }
      if ((Install-Company $c) -ne 0) { Say "$($c.name): perditesimi deshtoi." Red }
    }
  }
  'start' { Start-TestDb; foreach ($c in (Pick $Name)) { Start-Company $c; Say "$($c.name): http://localhost:$($c.port)" Green } }
  'stop' {
    foreach ($c in (Pick $Name)) { Stop-Company $c; Say "$($c.name): u ndal." }
    if (-not $Name -or $Name -eq 'all') { Stop-TestDb; Say 'MySQL i testit: u ndal.' }
  }
  'seed' {
    # 520+ invented employees with attendance, leave, requests ... in the company's own test database (it is emptied first)
    $node = (Get-Command node.exe -ErrorAction Stop).Source
    foreach ($c in (Pick $Name)) { Say "== $($c.name) ==" Cyan; & $node (Join-Path $here 'test-env-seed.mjs') $c.name | Out-Host }
  }
  'panel' {
    # the panel of the test space on http://localhost:3600 (pick a company, start/stop/update); starts the test database and every company first
    Start-TestDb; foreach ($c in (Get-Companies)) { Start-Company $c }
    if (-not (Test-Port 3600)) { Start-Process -FilePath (Get-Command node.exe).Source -ArgumentList "`"$(Join-Path $here 'test-env-panel.mjs')`"" -WindowStyle Hidden | Out-Null; Start-Sleep -Seconds 2 }
    Start-Process 'http://localhost:3600'
    Say 'Paneli: http://localhost:3600' Green
  }
  'list' {
    $all = Get-Companies
    if (-not $all) { Say 'Asnje kompani. Shto: test-env.bat add regina rogest-network/HRSystem-ReginaCenter test' ; break }
    foreach ($c in $all) {
      $v = if (Test-Path (Join-Path (Root-Of $c.name) 'current.txt')) { (Get-Content (Join-Path (Root-Of $c.name) 'current.txt') -Raw).Trim() } else { '?' }
      $h = if (Test-Health $c.port) { 'punon' } else { 'ndalur' }
      Say ("{0,-10} {1,-8} {2,-8} http://localhost:{3,-5} {4}" -f $c.name, $v, $h, $c.port, $c.repo)
    }
  }
  'remove' {
    $c = Get-One $Name
    Stop-Company $c
    if (Test-Port $dbPort) { Invoke-Sql "DROP DATABASE IF EXISTS ``hrtest_$Name``; DROP USER IF EXISTS 'hrtest_$Name'@'127.0.0.1'; DROP USER IF EXISTS 'hrtest_$Name'@'localhost'" }
    Start-Sleep -Seconds 2
    Remove-Item (Root-Of $Name), ((Root-Of $Name) + 'Data') -Recurse -Force -ErrorAction SilentlyContinue
    $rest = @(Get-Companies | Where-Object { $_.name -ne $Name })
    Save-Companies $rest
    foreach ($x in $rest) { Write-Env $x $rest }
    Say "$Name u fshi." Green
  }
  default { throw "Veprim i panjohur: $Action" }
}
