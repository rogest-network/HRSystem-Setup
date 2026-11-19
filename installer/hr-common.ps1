# HRSystem on Windows: what the setup, the updater and the SQL importer share.
# HRSYSTEM_ROOT / HRSYSTEM_DATA can point somewhere else for tests; the defaults are the real install.
# The installation can be anywhere (the setup window lets the owner choose the drive and folder): an installed copy of this file sits in the
# installation folder itself (next to current.txt), so that folder is the root; the data folder is <root>Data.
$script:Root = if ($env:HRSYSTEM_ROOT) { $env:HRSYSTEM_ROOT } elseif ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'current.txt'))) { $PSScriptRoot } else { 'C:\HRSystem' }
$script:DataRoot = if ($env:HRSYSTEM_DATA) { $env:HRSYSTEM_DATA } else { $script:Root.TrimEnd('\') + 'Data' }
# HRSYSTEM_AUTO=1 (set by the setup window): no question is asked in a console or a dialog; every value comes from the environment.
$script:Auto = [bool]$env:HRSYSTEM_AUTO
$script:Releases = Join-Path $script:Root 'releases'
$script:CurrentFile = Join-Path $script:Root 'current.txt'
$script:EnvFile = Join-Path $script:Root '.env'
$script:TokenFile = Join-Path $script:Root 'github.token'
$script:UpdateConfig = Join-Path $script:Root 'update.json'
$script:Backups = Join-Path $script:DataRoot 'Backups'
$script:TaskName = if ($env:HRSYSTEM_TASK) { $env:HRSYSTEM_TASK } else { 'HRSystem' }
# npm's "New major version of npm available" notice ignores the log level and goes to stderr, which older scripts took for an error (2026-10-30).
$env:npm_config_update_notifier = 'false'

function Banner([string]$Text) { Write-Host "`n=== $Text ===" -ForegroundColor Cyan }
function Ok([string]$Text) { Write-Host $Text -ForegroundColor Green }
function Warn([string]$Text) { Write-Host $Text -ForegroundColor Yellow }

function Is-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Refresh-Path {
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Find-Exe([string]$Name) {
  $cmd = Get-Command $Name -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($base in @('C:\Program Files\MySQL', 'C:\Program Files (x86)\MySQL')) {
    foreach ($dir in (Get-ChildItem $base -Directory -ErrorAction SilentlyContinue)) {
      $f = Get-ChildItem $dir.FullName -Filter $Name -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($f) { return $f.FullName }
    }
  }
  return $null
}

# The settings of the installation (.env) as a hashtable.
function Read-HrEnv {
  $map = @{}
  if (Test-Path $script:EnvFile) {
    Get-Content $script:EnvFile | ForEach-Object {
      $line = $_.Trim()
      if ($line -and -not $line.StartsWith('#')) {
        $i = $line.IndexOf('=')
        if ($i -ge 1) { $map[$line.Substring(0, $i).Trim()] = $line.Substring($i + 1) }
      }
    }
  }
  return $map
}

function Use-HrEnv {
  $map = Read-HrEnv
  foreach ($key in $map.Keys) { [Environment]::SetEnvironmentVariable($key, $map[$key], 'Process') }
  return $map
}

function Get-InstalledVersion {
  if (-not (Test-Path $script:CurrentFile)) { return $null }
  return (Get-Content $script:CurrentFile -Raw).Trim()
}

# 1.2.10 > 1.2.9: compare the numbers one by one (-1, 0, 1).
function Compare-Version([string]$A, [string]$B) {
  $x = @(([regex]::Matches($A, '\d+') | ForEach-Object { [int]$_.Value }))
  $y = @(([regex]::Matches($B, '\d+') | ForEach-Object { [int]$_.Value }))
  for ($i = 0; $i -lt [Math]::Max($x.Count, $y.Count); $i++) {
    $p = if ($i -lt $x.Count) { $x[$i] } else { 0 }
    $q = if ($i -lt $y.Count) { $y[$i] } else { 0 }
    if ($p -ne $q) { return [Math]::Sign($p - $q) }
  }
  return 0
}

function Test-Health([int]$Port) {
  try { return ((Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/api/health" -TimeoutSec 3).Content -match '"ok":true') } catch { return $false }
}

function Wait-Health([int]$Port, [int]$Seconds = 60) {
  for ($i = 0; $i -lt $Seconds; $i += 2) {
    if (Test-Health $Port) { return $true }
    Start-Sleep -Seconds 2
  }
  return $false
}

# Installs the packages of a release folder (the current folder). With the lockfile of the release: `npm ci`, the exact versions that were
# tested; a newer package can never change the build (2026-11-09: postcss-selector-parser 7.2.0 broke every responsive CSS class of a
# lockless install). Without a lockfile, or if `npm ci` refuses it, the old way: the lockfile is removed and `npm install` resolves again.
# Returns the exit code of npm.
function Install-HrPackages {
  $ErrorActionPreference = 'Continue'  # npm writes warnings to stderr; only the exit code counts (local to this function)
  if (Test-Path 'package-lock.json') {
    npm ci --include=optional --no-audit --no-fund 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { return 0 }
    Write-Host 'npm ci nuk u krye; po provohet npm install...' -ForegroundColor Yellow
    Remove-Item 'package-lock.json' -Force -ErrorAction SilentlyContinue
  }
  npm install --include=optional --no-audit --no-fund 2>&1 | Out-Null
  return $LASTEXITCODE
}

# Checks the CSS the build wrote (dist\assets\*.css): Tailwind's responsive classes are written ".sm\:hidden" (one backslash). A broken
# tool writes three backslashes, so every phone/computer switch is dead while the app still answers the health check. Returns the reason
# in Albanian when the CSS is broken, $null when it is fine.
function Test-BuiltCss([string]$ReleaseDir) {
  $files = @(Get-ChildItem -Path (Join-Path $ReleaseDir 'dist\assets') -Filter '*.css' -ErrorAction SilentlyContinue)
  if (-not $files.Count) { return 'Build-i nuk krijoi asnje skedar CSS.' }
  $css = ($files | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
  if ($css.Contains('\\\:')) { return 'CSS-ja e build-it eshte e prishur (klasat e ekranit me tre "\"): nje pakete e re e ndertimit.' }
  if (-not [regex]::IsMatch($css, '\.(sm|md|lg)\\:')) { return 'CSS-ja e build-it nuk ka klasat e ekranit (sm/md/lg).' }
  return $null
}

# Stops the app (only the node process that runs this installation's server.mjs) and starts it again from current.txt.
function Restart-HrApp {
  Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
    # not the dashboard (manager\server.mjs): ending it with the app made it vanish for minutes after every update
    if ($_.CommandLine -and $_.CommandLine -like "*$($script:Root)*server.mjs*" -and $_.CommandLine -notlike '*\manager\*') {
      try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch { }
    }
  }
  Start-Sleep -Seconds 2
  # the launcher (start-hrsystem.ps1) starts the app again when it stops; start it if it is not running
  $launcherRunning = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -and $_.CommandLine -like '*start-hrsystem.ps1*' -and $_.CommandLine -like "*$($script:Root)*" }
  if (-not $launcherRunning) {
    if (Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue) { Start-ScheduledTask -TaskName $script:TaskName }
    else { Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$(Join-Path $script:Root 'start-hrsystem.ps1')`"" -WindowStyle Hidden | Out-Null }
  }
}

# --- GitHub token (read-only), kept encrypted for this machine (Windows DPAPI), readable by administrators only
function Save-GitHubToken([string]$Token) {
  Add-Type -AssemblyName System.Security
  $bytes = [Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($Token.Trim()), $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
  Remove-Item $script:TokenFile -Force -ErrorAction SilentlyContinue
  Set-Content -Path $script:TokenFile -Value ([Convert]::ToBase64String($bytes)) -Encoding ascii
  # LocalMachine DPAPI lets any local account decrypt it, so the file itself is closed: Administrators, SYSTEM and the installing account (the dashboard's).
  try {
    $acl = New-Object Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($who in @('BUILTIN\Administrators', 'NT AUTHORITY\SYSTEM', [Security.Principal.WindowsIdentity]::GetCurrent().Name)) {
      $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($who, 'FullControl', 'Allow')))
    }
    Set-Acl -Path $script:TokenFile -AclObject $acl
  } catch { Warn "Lejet e github.token nuk u kufizuan: $($_.Exception.Message)" }
}
# The token: the environment, the encrypted file, or (never stored) the GitHub CLI when it is installed and signed in.
function Get-GitHubToken {
  if ($env:HRSYSTEM_GITHUB_TOKEN) { return $env:HRSYSTEM_GITHUB_TOKEN }
  if (Test-Path $script:TokenFile) {
    Add-Type -AssemblyName System.Security
    $bytes = [Convert]::FromBase64String((Get-Content $script:TokenFile -Raw).Trim())
    return [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($bytes, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine))
  }
  $gh = Get-Command gh.exe -ErrorAction SilentlyContinue
  if ($gh) { try { $t = (& $gh.Source auth token 2>$null | Select-Object -First 1); if ($t) { return $t.Trim() } } catch { } }
  return $null
}

# A secret typed in a small Windows dialog (paste works there; the black console often refuses it). The text is hidden unless
# "Shfaq" is ticked. Returns '' when the person presses "Kalo" (skip). Falls back to the console prompt if no dialog can be shown.
function Read-Secret([string]$Prompt) {
  if ($script:Auto) { return '' }
  try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'HRSystem Setup'
    $form.StartPosition = 'CenterScreen'
    $form.ClientSize = New-Object System.Drawing.Size(560, 170)
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Prompt
    $label.Location = New-Object System.Drawing.Point(12, 10)
    $label.Size = New-Object System.Drawing.Size(536, 50)
    $box = New-Object System.Windows.Forms.TextBox
    $box.UseSystemPasswordChar = $true
    $box.Location = New-Object System.Drawing.Point(12, 66)
    $box.Size = New-Object System.Drawing.Size(536, 24)
    $show = New-Object System.Windows.Forms.CheckBox
    $show.Text = 'Shfaq'
    $show.Location = New-Object System.Drawing.Point(12, 98)
    $show.Size = New-Object System.Drawing.Size(120, 22)
    $show.Add_CheckedChanged({ $box.UseSystemPasswordChar = -not $show.Checked })
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'OK'
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $ok.Location = New-Object System.Drawing.Point(368, 128)
    $skip = New-Object System.Windows.Forms.Button
    $skip.Text = 'Kalo'
    $skip.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $skip.Location = New-Object System.Drawing.Point(458, 128)
    $form.AcceptButton = $ok
    $form.CancelButton = $skip
    $form.Controls.AddRange(@($label, $box, $show, $ok, $skip))
    $form.Add_Shown({ $form.Activate(); $box.Focus() | Out-Null })
    $result = $form.ShowDialog()
    $text = $box.Text.Trim()
    $form.Dispose()
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) { return $text }
    return ''
  } catch {
    $secure = Read-Host $Prompt -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr).Trim() } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
  }
}

# update.json: { "repo": "owner/name", "channel": "stable" | "test" }. One repository per client; "stable" follows the Releases that
# are not marked pre-release (what the client's live installation gets), "test" also takes pre-releases (the test environment gets a
# version first, and the owner promotes it to stable once it was tried).
function Get-UpdateSettings {
  # No repository is built in (owner, 2026-10-22): it comes from update.json, and that is written from the GitHub token (Resolve-UpdateRepo).
  $settings = @{ repo = ''; channel = 'stable' }
  if (Test-Path $script:UpdateConfig) {
    try {
      $j = Get-Content $script:UpdateConfig -Raw | ConvertFrom-Json
      if ($j.repo) { $settings.repo = [string]$j.repo }
      if ($j.channel) { $settings.channel = [string]$j.channel }
    } catch { }
  }
  return $settings
}
function Get-UpdateRepo { return (Get-UpdateSettings).repo }
function Save-UpdateSettings([string]$Repo, [string]$Channel) {
  Remove-Item $script:UpdateConfig -Force -ErrorAction SilentlyContinue   # an old file with other permissions must not block the new one
  Set-Content -Path $script:UpdateConfig -Value (@{ repo = $Repo; channel = $Channel } | ConvertTo-Json) -Encoding ascii
}

# The repository the updates come from is the one the GitHub token can read (owner, 2026-10-22: not a repository fixed in the setup). A fine-grained token
# is made for one repo, so its repo is the program's. `Prefer` (the repo saved in update.json) is kept while the token still reaches it; otherwise the
# only HRSystem-* repository that is not the Template / Dashboard / Test one, otherwise the first. Returns '' when the token cannot list repositories.
function Find-RepoFromToken([string]$Token, [string]$Prefer = '') {
  $h = @{ Authorization = "Bearer $Token"; 'User-Agent' = 'hrsystem-updater'; Accept = 'application/vnd.github+json' }
  $names = @()
  foreach ($url in @('https://api.github.com/user/repos?per_page=100&sort=updated', 'https://api.github.com/installation/repositories?per_page=100')) {
    try {
      $r = Invoke-RestMethod -Uri $url -Headers $h -TimeoutSec 20
      $list = if ($url -like '*installation*') { $r.repositories } else { $r }   # (on an array, $r.repositories would be an array of nulls)
      $names = @($list | ForEach-Object { $_.full_name })
      if ($names.Count) { break }
    } catch { }
  }
  if (-not $names.Count) { return '' }
  if ($Prefer) { $hit = $names | Where-Object { $_ -ieq $Prefer } | Select-Object -First 1; if ($hit) { return $hit } }
  # Order: the client's own HRSystem-* repos, then the Template, then any other (never the Dashboard / Test repo); the first one that has a Release wins
  # (a token that also reaches the public Dashboard repo must not pick it: it has no Release).
  $own = @($names | Where-Object { $_ -match '/HRSystem-' -and $_ -notmatch '-(Template|Dashboard|Test|Setup)$' })
  $tpl = @($names | Where-Object { $_ -match '-Template$' })
  $rest = @($names | Where-Object { $_ -notmatch '-(Dashboard|Test|Template|Setup)$' -and $_ -notin $own })
  foreach ($n in @($own + $tpl + $rest)) {
    try {
      $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$n/releases?per_page=5" -Headers $h -TimeoutSec 20
      if (@($rel | Where-Object { -not $_.draft -and $_.tag_name -match '^[vV]\d+\.\d+\.\d+$' }).Count) { return $n }
    } catch { }
  }
  return @($own + $tpl + $rest + $names)[0]
}
# The repo for an update: from the token; saved to update.json when it changed. When the token cannot list repositories the saved one stays.
function Resolve-UpdateRepo([string]$Token, $Settings) {
  $found = Find-RepoFromToken $Token $Settings.repo
  if (-not $found) { return $Settings.repo }
  if ($found -ne $Settings.repo) { Save-UpdateSettings $found $Settings.channel; Write-Host "Repo i perditesimeve (nga tokeni): $found" }
  return $found
}

function Get-GitHubHeaders([string]$Token) {
  $h = @{ 'User-Agent' = 'regina-updater'; Accept = 'application/vnd.github+json' }
  if ($Token) { $h.Authorization = "Bearer $Token" }   # a public repo (the Template) is read without a token
  return $h
}

# The Release to install: stable = the newest that is not a pre-release; test = the newest version tag including pre-releases
# (tags like test-3.0.0 are reference builds and are never offered).
function Get-TargetRelease([string]$Repo, [string]$Token, [string]$Channel) {
  $headers = Get-GitHubHeaders $Token
  if ($Channel -ne 'test') { return Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers }
  $all = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases?per_page=30" -Headers $headers
  $best = $null
  foreach ($r in $all) {
    if ($r.draft -or $r.tag_name -notmatch '^[vV]\d+(\.\d+)*$') { continue }
    if (-not $best -or (Compare-Version $r.tag_name $best.tag_name) -gt 0) { $best = $r }
  }
  if (-not $best) { throw "Nuk u gjet asnje Release me version ne $Repo." }
  return $best
}
function Find-AppAsset($Release) {
  # The app zip of a Release is HRSystem-<version>.zip.
  return $Release.assets | Where-Object { $_.name -match '^HRSystem-\d+\.\d+\.\d+\.zip$' } | Select-Object -First 1
}

# GitHub sends the file from another address; the token must not follow it, so the redirect is followed by hand.
function Save-ReleaseAsset([string]$Url, [string]$Token, [string]$Target) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $request = [Net.HttpWebRequest]::Create($Url)
  $request.AllowAutoRedirect = $false
  $request.UserAgent = 'regina-updater'
  $request.Accept = 'application/octet-stream'
  if ($Token) { $request.Headers.Add('Authorization', "Bearer $Token") }
  $response = $request.GetResponse()
  try {
    if ([int]$response.StatusCode -in 301, 302, 303, 307, 308) {
      $location = $response.Headers['Location']
      $response.Close()
      Invoke-WebRequest -UseBasicParsing -Uri $location -OutFile $Target | Out-Null
    } else {
      $file = [IO.File]::Create($Target)
      try { $response.GetResponseStream().CopyTo($file) } finally { $file.Close() }
    }
  } finally { $response.Close() }
}

# A database backup (a .sql file) before anything changes; the last 14 are kept.
function Backup-Database {
  $mysqldump = Find-Exe 'mysqldump.exe'
  if (-not $mysqldump) { throw 'mysqldump.exe nuk u gjet: backup-i i databazes nuk mund te behet.' }
  $cfg = Read-HrEnv
  New-Item -ItemType Directory -Force -Path $script:Backups | Out-Null
  # <database name>-<date>-<time>.sql, e.g. regina-20261022-141108.sql
  $dbLabel = if ($cfg['DB_NAME']) { $cfg['DB_NAME'] } else { 'hrsystem' }
  $file = Join-Path $script:Backups ($dbLabel + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.sql')
  $old = $env:MYSQL_PWD
  $env:MYSQL_PWD = $cfg['DB_PASSWORD']
  try {
    & $mysqldump "--user=$($cfg['DB_USER'])" '--protocol=TCP' "--host=$($cfg['DB_HOST'])" "--port=$($cfg['DB_PORT'])" '--single-transaction' '--no-tablespaces' '--hex-blob' '--default-character-set=utf8mb4' "--result-file=$file" $cfg['DB_NAME']
    if ($LASTEXITCODE -ne 0) { throw 'mysqldump deshtoi.' }
  } finally { $env:MYSQL_PWD = $old }
  # the newest 14 are kept, or more when the dashboard keeps more (its automatic-backup setting)
  $keep = 14
  try { $ds = Get-Content (Join-Path $script:Root 'dashboard-settings.json') -Raw | ConvertFrom-Json; if ($ds.autoBackupKeep -gt 14) { $keep = [int]$ds.autoBackupKeep } } catch { }
  Get-ChildItem $script:Backups -Filter ($dbLabel + '-*.sql') | Sort-Object LastWriteTime -Descending | Select-Object -Skip $keep | Remove-Item -Force -ErrorAction SilentlyContinue
  return $file
}

function Show-Result([bool]$Success, [string]$Message) {
  Write-Host ''
  if ($Success) {
    Write-Host '################################' -ForegroundColor Green
    Write-Host "  SUKSES: $Message" -ForegroundColor Green
    Write-Host '################################' -ForegroundColor Green
  } else {
    Write-Host '################################' -ForegroundColor Red
    Write-Host "  GABIM: $Message" -ForegroundColor Red
    Write-Host '################################' -ForegroundColor Red
  }
}

# The Node.js major the system is TESTED with (owner, 2026-10-24: always the newest version that works with the system). Raise it only after the system
# was tested on the new major; the dashboard's "Programet e sistemit" card keeps the installed one at the newest release of its own major.
$script:HrTestedNodeMajor = 24

# Newest release of the tested major from nodejs.org, checked against nodejs.org's SHA-256 list BEFORE it runs, installed with msiexec (setup runs as
# administrator). -DownloadOnly stops after the check and returns the file. Returns $true (or the file) on success, $false when it could not be done:
# the caller then falls back to winget.
function Install-NodeVerified {
    param([int]$Major = $script:HrTestedNodeMajor, [switch]$DownloadOnly)
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $index = Invoke-RestMethod -UseBasicParsing -Uri 'https://nodejs.org/dist/index.json'
        $entry = $index | Where-Object { $_.version -like "v$Major.*" } | Select-Object -First 1
        if (!$entry) { Write-Host "Node.js $Major nuk u gjet te nodejs.org."; return $false }
        $v = [string]$entry.version
        $file = "node-$v-x64.msi"
        $base = "https://nodejs.org/dist/$v"
        $tmp = Join-Path $env:TEMP $file
        Write-Host "Po shkarkohet Node.js $v ..."
        Invoke-WebRequest -UseBasicParsing -Uri "$base/$file" -OutFile $tmp
        $sums = (Invoke-WebRequest -UseBasicParsing -Uri "$base/SHASUMS256.txt").Content
        $line = ($sums -split '\r?\n') | Where-Object { $_ -match ([regex]::Escape($file) + '\s*$') } | Select-Object -First 1
        $want = if ($line) { ($line -split '\s+')[0].ToLower() } else { '' }
        $got = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower()
        if (!$want -or $want -ne $got) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue; Write-Host 'Kontrolli SHA-256 i Node.js deshtoi: nuk u instalua.'; return $false }
        Write-Host 'Skedari u verifikua (SHA-256).'
        if ($DownloadOnly) { return $tmp }
        $p = Start-Process msiexec.exe -ArgumentList '/i', ('"' + $tmp + '"'), '/qn', '/norestart' -Wait -PassThru
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { Write-Host "Instalimi i Node.js deshtoi (kodi $($p.ExitCode))."; return $false }
        return $true
    } catch {
        Write-Host "Node.js: $($_.Exception.Message)"
        return $false
    }
}

# --- Microsoft Visual C++ Redistributable 2015-2022 (x64) ---------------------------------------------------------------------------------
# php.exe (the dashboard's phpMyAdmin, "Hap databazen") and MySQL 8.4 do not start without it, and PHP also refuses a runtime that is OLDER
# than the one it was built with ("'vcruntime140.dll' 14.x is not compatible with this PHP build linked with 14.y"). PHP 8.3 (vs16) is linked
# with 14.29, PHP 8.4 (vs17) with 14.4x: a runtime below this version is brought up to Microsoft's newest one.
$script:HrVcMinVersion = [version]'14.44'
# Microsoft's own permanent links: the newest v14 runtime first, the Visual Studio 2022 one when that cannot be installed (an older Windows).
$script:HrVcUrls = @('https://aka.ms/vc14/vc_redist.x64.exe', 'https://aka.ms/vs/17/release/vc_redist.x64.exe')

# The installed x64 runtime as a [version], $null when it is missing. What counts is what php.exe loads: vcruntime140.dll and vcruntime140_1.dll
# in System32; the registry only names the version when the file's own cannot be read. -SystemDir is for tests.
function Get-VcRuntimeVersion {
    param([string]$SystemDir = '')
    if (-not $SystemDir) {
        $SystemDir = Join-Path $env:SystemRoot 'Sysnative'   # a 32-bit PowerShell reaches the real System32 under this name
        if (-not (Test-Path $SystemDir)) { $SystemDir = Join-Path $env:SystemRoot 'System32' }
    }
    $dll = Join-Path $SystemDir 'vcruntime140.dll'
    if (-not (Test-Path $dll) -or -not (Test-Path (Join-Path $SystemDir 'vcruntime140_1.dll'))) { return $null }
    try {
        $fv = [Diagnostics.FileVersionInfo]::GetVersionInfo($dll)
        if ($fv.FileMajorPart -ge 14) { return (New-Object Version $fv.FileMajorPart, $fv.FileMinorPart, $fv.FileBuildPart) }
    } catch { }
    foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, $view)
            $key = $base.OpenSubKey('SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64')
            if ($key -and [int]$key.GetValue('Installed', 0) -eq 1) {
                return (New-Object Version ([int]$key.GetValue('Major', 14)), ([int]$key.GetValue('Minor', 0)), ([int]$key.GetValue('Bld', 0)))
            }
        } catch { }
    }
    return (New-Object Version 14, 0, 0)
}

# $true only for a file whose Authenticode signature is valid and is Microsoft Corporation's (issued by a Microsoft code-signing authority).
function Test-MicrosoftSigned([string]$Path) {
    try {
        $sig = Get-AuthenticodeSignature -FilePath $Path
        if ([string]$sig.Status -ne 'Valid' -or -not $sig.SignerCertificate) { return $false }
        $subject = [string]$sig.SignerCertificate.Subject
        $issuer = [string]$sig.SignerCertificate.Issuer
        return (($subject -match '(^|,\s*)CN=Microsoft Corporation(,|$)') -and ($subject -match '(^|,\s*)O=Microsoft Corporation(,|$)') -and ($issuer -match '(^|,\s*)O=Microsoft Corporation(,|$)'))
    } catch { return $false }
}

# Makes sure the runtime is there. Installed and new enough: nothing is downloaded (unless -Force: php.exe itself said the runtime is too old).
# Otherwise Microsoft's vc_redist.x64.exe is downloaded, its signature is checked BEFORE it runs, and it is installed silently (0, 1638 = a newer
# one is already there, 3010 = done, restart wanted). It NEVER throws: a failure is a message and the install goes on.
# -CheckOnly only reports. Returns @{ Ok; Installed (version or $null); Changed; Restart; Message (Albanian) }.
function Install-VcRuntime {
    param([switch]$Force, [switch]$CheckOnly)
    $ProgressPreference = 'SilentlyContinue'
    $have = Get-VcRuntimeVersion
    $r = @{ Ok = $false; Installed = $have; Changed = $false; Restart = $false; Message = '' }
    if ($have -and $have -ge $script:HrVcMinVersion -and -not $Force) {
        $r.Ok = $true; $r.Message = "Microsoft Visual C++ Runtime $have - OK"
        return $r
    }
    $why = if (-not $have) { 'mungon' } elseif ($have -lt $script:HrVcMinVersion) { "eshte i vjeter ($have)" } else { "duhet rifreskuar ($have)" }
    if ($CheckOnly) { $r.Message = "Microsoft Visual C++ Runtime $why."; return $r }
    Write-Host "Microsoft Visual C++ Runtime (x64) $why. Po instalohet nga Microsoft..."
    $last = ''
    foreach ($url in $script:HrVcUrls) {
        $tmp = Join-Path $env:TEMP ('hrsystem-vc_redist-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.exe')
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Write-Host "Po shkarkohet $url ..."
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp -TimeoutSec 300
            if (-not (Test-MicrosoftSigned $tmp)) { $last = 'nenshkrimi i skedarit te shkarkuar nuk eshte i Microsoft: nuk u ekzekutua'; continue }
            Write-Host 'Skedari u verifikua (nenshkrimi i Microsoft Corporation). Po instalohet...'
            $p = Start-Process -FilePath $tmp -ArgumentList '/install', '/quiet', '/norestart' -PassThru
            $null = $p.Handle   # without it PowerShell 5.1 loses the exit code of a process it did not wait for with -Wait
            if (-not $p.WaitForExit(600000)) { try { $p.Kill() } catch { }; $last = 'instalimi nuk mbaroi brenda 10 minutash'; continue }
            $code = $p.ExitCode
            if ($code -eq 0 -or $code -eq 1638 -or $code -eq 3010) {
                $r.Ok = $true; $r.Changed = ($code -ne 1638); $r.Restart = ($code -eq 3010)
                break
            }
            $last = "instaluesi i Microsoft u mbyll me kodin $code"
        } catch { $last = $_.Exception.Message }
        finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
    $r.Installed = Get-VcRuntimeVersion
    if ($r.Ok -and -not $r.Installed) { $r.Ok = $false; $last = 'instaluesi mbaroi, por vcruntime140.dll nuk gjendet te System32' }
    if ($r.Ok) {
        $r.Message = "Microsoft Visual C++ Runtime $($r.Installed) - OK" + $(if ($r.Restart) { ' (Windows kerkon nje restart per ta perfunduar; instalimi vazhdon)' } else { '' })
    } else {
        $r.Message = "Microsoft Visual C++ Runtime nuk u instalua ($last). Instalimi vazhdon; pa te nuk hapet phpMyAdmin (Hap databazen): instaloje me vone nga $($script:HrVcUrls[1])"
    }
    return $r
}

# --- The database tools: PHP + phpMyAdmin (the dashboard's "Hap databazen") ------------------------------------------------------------------
# The DASHBOARD downloads and installs them by itself into <root>\tools\{php, phpmyadmin, phpmyadmin-data} (30 s after it starts and every 30
# minutes while they are missing; both downloads are SHA-256 checked there). There is ONE downloader, the dashboard's: the setup only waits
# for it to finish and checks that php.exe really starts.

# What is on disk now: Phase = ready (installed.json + php.exe + index.php, the dashboard's own test), or how far the dashboard is:
# download (tools\downloads), unpack (.php-new / .phpmyadmin-new), check (php.exe is there, not accepted yet), wait (nothing yet).
function Get-DbToolsState {
    param([string]$Root = $script:Root)
    $tools = Join-Path $Root 'tools'
    $php = Join-Path $tools 'php\php.exe'
    $metaFile = Join-Path $tools 'phpmyadmin-data\installed.json'
    $s = @{ Phase = 'wait'; Version = ''; Php = ''; PhpExe = $php }
    $meta = $null
    if (Test-Path $metaFile) { try { $meta = Get-Content $metaFile -Raw | ConvertFrom-Json } catch { } }
    if ($meta -and $meta.version -and (Test-Path $php) -and (Test-Path (Join-Path $tools 'phpmyadmin\index.php'))) {
        $s.Phase = 'ready'; $s.Version = [string]$meta.version; $s.Php = [string]$meta.php
    }
    elseif ((Test-Path (Join-Path $tools '.php-new')) -or (Test-Path (Join-Path $tools '.phpmyadmin-new'))) { $s.Phase = 'unpack' }
    elseif (Test-Path (Join-Path $tools 'downloads')) { $s.Phase = 'download' }
    elseif (Test-Path $php) { $s.Phase = 'check' }
    return $s
}

# Albanian text for the black window and the setup log, which show plain ASCII reliably.
function ConvertTo-PlainAscii([string]$Text) {
    $map = @{ 0xEB = 'e'; 0xCB = 'E'; 0xE7 = 'c'; 0xC7 = 'C' }
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $Text.ToCharArray()) {
        $n = [int]$ch
        if ($map.ContainsKey($n)) { [void]$sb.Append($map[$n]) } elseif ($n -lt 128) { [void]$sb.Append($ch) } else { [void]$sb.Append('?') }
    }
    return $sb.ToString()
}

# The dashboard writes why its own install failed (no internet, ...) as a JSON line with where = "phpMyAdmin" in manager\dashboard-errors.log.
# Returns the newest such message written after $Since, '' when there is none.
function Get-DbToolsError {
    param([string]$Root = $script:Root, [datetime]$Since = [datetime]::MinValue)
    try {
        $file = Join-Path $Root 'manager\dashboard-errors.log'
        if (-not (Test-Path $file)) { return '' }
        $lines = @(Get-Content $file -Tail 30 -Encoding UTF8 -ErrorAction Stop)
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            if ($lines[$i] -notmatch '"where"\s*:\s*"phpMyAdmin"') { continue }
            # the regex, not ConvertFrom-Json: that one turns the "at" text into a date of its own liking
            $at = [regex]::Match($lines[$i], '"at"\s*:\s*"([^"]+)"').Groups[1].Value
            $when = [datetime]::MinValue
            if (-not [datetime]::TryParse($at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$when)) { continue }
            if ($when -lt $Since.ToUniversalTime()) { return '' }
            $msg = ''
            try { $msg = [string]($lines[$i] | ConvertFrom-Json).message } catch { }
            if ($msg) { return (ConvertTo-PlainAscii $msg) }
        }
    } catch { }
    return ''
}

# Runs php.exe -v (with the dashboard's php.ini when it is written). A missing or too old Visual C++ runtime is recognised the way the dashboard
# does (exit 0xC0000135, or a vcruntime message). Returns @{ Ok; Line ("PHP 8.3.36"); NeedsVc; Detail }.
function Test-DbToolsPhp {
    param([string]$Root = $script:Root)
    $php = Join-Path $Root 'tools\php\php.exe'
    $ini = Join-Path $Root 'tools\php\php.ini'
    $r = @{ Ok = $false; Line = ''; NeedsVc = $false; Detail = '' }
    if (-not (Test-Path $php)) { $r.Detail = 'php.exe mungon'; return $r }
    # A program that misses a DLL shows a Windows error box and waits for a click: not during a setup. The mode is inherited by php.exe.
    $oldMode = $null
    try {
        if (-not ('HrNative.Kernel' -as [type])) { Add-Type -Namespace HrNative -Name Kernel -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint uMode);' }
        $oldMode = [HrNative.Kernel]::SetErrorMode(0x8003)
    } catch { }
    try {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $php
        $psi.Arguments = if (Test-Path $ini) { '-c "' + $ini + '" -v' } else { '-n -v' }
        $psi.WorkingDirectory = $env:TEMP
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
        $psi.EnvironmentVariables['PHP_INI_SCAN_DIR'] = ''
        $proc = [Diagnostics.Process]::Start($psi)
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit(30000)) { try { $proc.Kill() } catch { }; $r.Detail = 'php.exe nuk u pergjigj brenda 30 sekondave'; return $r }
        $proc.WaitForExit()
        $out = ([string]$outTask.Result + [string]$errTask.Result).Trim()
        $code = $proc.ExitCode
        $first = (($out -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
        $r.NeedsVc = ($code -eq -1073741515) -or ($out -match 'vcruntime|msvcp|VCRUNTIME140')
        if ($code -eq 0 -and $out -match '(?m)^PHP \d' -and -not $r.NeedsVc) {
            $r.Ok = $true
            $r.Line = ((($out -split "`r?`n") | Where-Object { $_ -match '^PHP \d' } | Select-Object -First 1) -replace '\s*\(.*$', '')
        } elseif ($r.NeedsVc) { $r.Detail = 'mungon ose eshte i vjeter Microsoft Visual C++ Runtime (x64)' }
        else { $r.Detail = "kodi $code" + $(if ($first) { ': ' + (ConvertTo-PlainAscii ([string]$first)) } else { '' }) }
    } catch { $r.Detail = $_.Exception.Message }
    finally { if ($null -ne $oldMode) { try { [void][HrNative.Kernel]::SetErrorMode($oldMode) } catch { } } }
    return $r
}

# The last step of the setup: waits, with a line of progress, until the dashboard has PHP + phpMyAdmin ready, then checks php.exe. It never
# throws and never fails the install: when the tools are not there in time the dashboard goes on installing them by itself.
# -Since = when the dashboard was started (its failure line may be older than this step). -Seconds 0 = only look, do not wait.
# Returns @{ Ready; Version (phpMyAdmin); Php; Line ("PHP 8.3.36"); Reason (Albanian, why not ready) }.
function Wait-DbTools {
    param([string]$Root = $script:Root, [int]$Seconds = 240, [int]$Poll = 2, [datetime]$Since = (Get-Date))
    $r = @{ Ready = $false; Version = ''; Php = ''; Line = ''; Reason = '' }
    $texts = @{ wait = 'Dashboard-i po e pergatit instalimin'; download = 'Po shkarkohen PHP dhe phpMyAdmin'; unpack = 'Po hapen skedaret'; check = 'Po kontrollohet PHP' }
    try {
        $start = Get-Date; $lastPhase = ''; $lastSaid = -100; $checkSince = $null
        if ($Since -gt $start) { $Since = $start }
        while ($true) {
            $s = Get-DbToolsState $Root
            $elapsed = [int]((Get-Date) - $start).TotalSeconds
            if ($s.Phase -eq 'ready') { break }
            # php.exe in place but not accepted for a while: the dashboard's own check of it failed (it takes a second or two when it passes)
            if ($s.Phase -eq 'check') { if (-not $checkSince) { $checkSince = Get-Date } elseif (((Get-Date) - $checkSince).TotalSeconds -ge 25) { break } } else { $checkSince = $null }
            $fail = Get-DbToolsError $Root $Since
            if ($fail) { $r.Reason = $fail; break }
            if ($elapsed -ge $Seconds) { break }
            if ($s.Phase -ne $lastPhase -or ($elapsed - $lastSaid) -ge 15) {
                Write-Host ("  {0}... ({1} s)" -f $texts[$s.Phase], $elapsed)
                $lastPhase = $s.Phase; $lastSaid = $elapsed
            }
            Start-Sleep -Seconds $Poll
        }
        $s = Get-DbToolsState $Root
        if ($s.Phase -ne 'ready' -and $s.Phase -ne 'check') {
            if (-not $r.Reason) { $r.Reason = "nuk u bene gati brenda $Seconds sekondave (interneti mungon ose eshte i ngadalte)" }
            return $r
        }
        $t = Test-DbToolsPhp $Root
        if (-not $t.Ok -and $t.NeedsVc) {
            # php.exe itself says the runtime is missing or older than it needs: Microsoft's newest one, then once more
            $vc = Install-VcRuntime -Force
            if ($vc.Ok) { Write-Host $vc.Message } else { Write-Host $vc.Message -ForegroundColor Yellow }
            $t = Test-DbToolsPhp $Root
        }
        if ($s.Phase -eq 'check' -and $t.Ok) {
            # php.exe works: the dashboard may be a moment from done
            for ($i = 0; $i -lt 10 -and $s.Phase -ne 'ready'; $i++) { Start-Sleep -Seconds 1; $s = Get-DbToolsState $Root }
        }
        $r.Version = $s.Version; $r.Php = $s.Php; $r.Line = $t.Line
        if ($s.Phase -eq 'ready' -and $t.Ok) { $r.Ready = $true }
        elseif (-not $t.Ok) { $r.Reason = "PHP nuk niset ($($t.Detail))" }
        else { $r.Reason = 'PHP punon, por dashboard-i nuk e ka mbyllur ende instalimin e phpMyAdmin' }
    } catch { $r.Reason = $_.Exception.Message }
    return $r
}
