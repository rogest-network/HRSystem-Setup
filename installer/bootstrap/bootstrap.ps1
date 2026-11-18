# HRS-Setup.zip: the one small file that is kept on the USB stick (owner, 2026-10-22). It never changes: every time it runs it downloads the NEWEST Setup
# from the private repo rogest-network/HRSystem-Setup (Releases), unpacks it and opens its Install.bat (the setup window). Nothing has to be copied to the USB again
# when the setup changes. The read-only GitHub token for that repo is in setup-token.txt next to Install.bat (put there when the zip was made); without it
# the window asks once and remembers it for this Windows user (DPAPI).
# -NoLaunch (tests): download and unpack, print the folder, do not open the setup.
param([switch]$NoLaunch)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
Add-Type -AssemblyName System.Security
$repo = 'rogest-network/HRSystem-Setup'
$zipRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$cache = Join-Path $env:LOCALAPPDATA 'HRSystem-Setup'
$tokenFile = Join-Path $env:APPDATA 'HRSystem\setup-token.dat'

# ------------------------------------------------------------------ the little window
function Rgb([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
$form = New-Object System.Windows.Forms.Form
$form.Text = 'HRSystem · Setup'; $form.ClientSize = New-Object System.Drawing.Size(460, 190); $form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false; $form.MinimizeBox = $false; $form.BackColor = [System.Drawing.Color]::White
$fN = New-Object System.Drawing.Font('Segoe UI', 10); $fB = New-Object System.Drawing.Font('Segoe UI Semibold', 11); $fS = New-Object System.Drawing.Font('Segoe UI', 9)
$logo = New-Object System.Windows.Forms.Label; $logo.Text = 'HR'; $logo.Font = $fB; $logo.ForeColor = [System.Drawing.Color]::White; $logo.BackColor = Rgb '#4F46E5'; $logo.TextAlign = 'MiddleCenter'
$logo.Location = New-Object System.Drawing.Point(24, 24); $logo.Size = New-Object System.Drawing.Size(44, 44); $form.Controls.Add($logo)
$title = New-Object System.Windows.Forms.Label; $title.Text = 'HRSystem Setup'; $title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 15); $title.Location = New-Object System.Drawing.Point(82, 22); $title.Size = New-Object System.Drawing.Size(360, 30); $form.Controls.Add($title)
$status = New-Object System.Windows.Forms.Label; $status.Font = $fN; $status.ForeColor = Rgb '#475569'; $status.Location = New-Object System.Drawing.Point(24, 88); $status.Size = New-Object System.Drawing.Size(412, 44); $form.Controls.Add($status)
$bar = New-Object System.Windows.Forms.ProgressBar; $bar.Style = 'Marquee'; $bar.MarqueeAnimationSpeed = 28; $bar.Location = New-Object System.Drawing.Point(24, 142); $bar.Size = New-Object System.Drawing.Size(412, 8); $form.Controls.Add($bar)
$sub = New-Object System.Windows.Forms.Label; $sub.Text = 'Merret versioni i fundit nga interneti'; $sub.Font = $fS; $sub.ForeColor = Rgb '#64748B'; $sub.Location = New-Object System.Drawing.Point(84, 52); $sub.Size = New-Object System.Drawing.Size(360, 20); $form.Controls.Add($sub)
function Say([string]$text) { $status.Text = $text; [System.Windows.Forms.Application]::DoEvents() }

function Ask-Token {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = 'HRSystem · Setup'; $dlg.ClientSize = New-Object System.Drawing.Size(460, 170); $dlg.StartPosition = 'CenterScreen'; $dlg.FormBorderStyle = 'FixedDialog'; $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false
    $l = New-Object System.Windows.Forms.Label; $l.Text = 'Ngjit tokenin GitHub vetëm-lexim (ai hap setup-in dhe merr programin e klientit; vetëm herën e parë në këtë kompjuter):'; $l.Font = $fN; $l.Location = New-Object System.Drawing.Point(16, 14); $l.Size = New-Object System.Drawing.Size(428, 44); $dlg.Controls.Add($l)
    $t = New-Object System.Windows.Forms.TextBox; $t.UseSystemPasswordChar = $true; $t.Font = $fN; $t.Location = New-Object System.Drawing.Point(16, 66); $t.Size = New-Object System.Drawing.Size(428, 28); $dlg.Controls.Add($t)
    $ok = New-Object System.Windows.Forms.Button; $ok.Text = 'Vazhdo'; $ok.Location = New-Object System.Drawing.Point(344, 116); $ok.Size = New-Object System.Drawing.Size(100, 34); $ok.DialogResult = 'OK'; $dlg.Controls.Add($ok); $dlg.AcceptButton = $ok
    if ($dlg.ShowDialog() -eq 'OK') { return $t.Text.Trim() }
    return ''
}
function Get-SetupToken {
    if ($env:HRSYSTEM_SETUP_TOKEN) { return $env:HRSYSTEM_SETUP_TOKEN.Trim() }
    $file = Join-Path $zipRoot 'setup-token.txt'
    if (Test-Path $file) { $v = (Get-Content $file | Where-Object { $_.Trim() } | Select-Object -First 1); if ($v) { return $v.Trim() } }
    if (Test-Path $tokenFile) {
        try { return [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String((Get-Content $tokenFile -Raw).Trim()), $null, 'CurrentUser')) } catch { }
    }
    # No token is asked here (owner, 2026-10-23): the token is optional and is typed in the setup window itself. Without one the newest setup is tried anonymously and,
    # when the repo is private or there is no internet, the copy of the setup that is inside this zip (setup\) is used.
    return ''
}
# GitHub sends the file from another address; the token must not follow it, so the redirect is followed by hand.
function Save-Asset([string]$url, [string]$token, [string]$target) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $req = [Net.HttpWebRequest]::Create($url); $req.AllowAutoRedirect = $false; $req.UserAgent = 'hrsystem-bootstrap'; $req.Accept = 'application/octet-stream'; if ($token) { $req.Headers.Add('Authorization', "Bearer $token") }
    $res = $req.GetResponse()
    try {
        if ([int]$res.StatusCode -in 301, 302, 303, 307, 308) { $loc = $res.Headers['Location']; $res.Close(); Invoke-WebRequest -UseBasicParsing -Uri $loc -OutFile $target | Out-Null }
        else { $f = [IO.File]::Create($target); try { $res.GetResponseStream().CopyTo($f) } finally { $f.Close() } }
    } finally { $res.Close() }
}
function Open-Setup([string]$folder) {
    $bat = Join-Path $folder 'Install.bat'
    if (-not (Test-Path $bat)) { throw 'Install.bat nuk u gjet te setup-i i shkarkuar.' }
    if ($NoLaunch) { Write-Output ('SETUP_FOLDER=' + $folder); return }
    Start-Process -FilePath $bat -WorkingDirectory $folder
}

$form.Show(); Say 'Po kontrollohet versioni i fundit...'
try {
    $token = Get-SetupToken
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{ 'User-Agent' = 'hrsystem-bootstrap'; Accept = 'application/vnd.github+json' }
    if ($token) { $headers.Authorization = "Bearer $token" }
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers $headers -TimeoutSec 30
    $asset = $rel.assets | Where-Object { $_.name -match '-Setup\.zip$' } | Select-Object -First 1
    if (-not $asset) { throw 'Release-i i fundit nuk ka skedarin e setup-it.' }
    $folder = Join-Path $cache ($rel.tag_name -replace '[^A-Za-z0-9._-]', '_')
    $stamp = Join-Path $folder '.asset'
    $mark = "$($asset.id):$($asset.updated_at)"
    if (-not ((Test-Path (Join-Path $folder 'Install.bat')) -and (Test-Path $stamp) -and ((Get-Content $stamp -Raw).Trim() -eq $mark))) {
        Say ('Po shkarkohet ' + $asset.name + ' (' + [math]::Round($asset.size / 1MB, 1) + ' MB)...')
        $tmp = Join-Path $env:TEMP $asset.name
        Save-Asset $asset.url $token $tmp
        if ((Get-Item $tmp).Length -ne $asset.size) { throw 'Shkarkimi nuk u plotësua.' }
        Say 'Po hapet setup-i...'
        if (Test-Path $folder) { Remove-Item $folder -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $folder | Out-Null
        Expand-Archive -Path $tmp -DestinationPath $folder -Force
        Remove-Item $tmp -Force
        Set-Content -Path $stamp -Value $mark -Encoding ascii
        # only the newest unpacked setup is kept
        Get-ChildItem $cache -Directory -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $folder } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    } else { Say 'Setup-i i fundit është tashmë këtu. Po hapet...' }
    $form.Close()
    # The same read-only token also lets the installer fetch the client's program from the client's own repo (the repo is found from the token),
    # so nothing has to be asked again in the setup window.
    if ($token) { $env:HRSYSTEM_GITHUB_TOKEN = $token }
    Open-Setup $folder
}
catch {
    $reason = $_.Exception.Message
    $form.Hide()
    # private repo, no token or no internet: the last unpacked setup, else the copy inside this zip (setup\), opens without asking anything
    $old = Get-ChildItem $cache -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'Install.bat') } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $bundled = Join-Path $zipRoot 'setup'
    if (-not $old -and (Test-Path (Join-Path $bundled 'Install.bat'))) { $old = Get-Item $bundled }
    if ($old) {
        if ($token) { $env:HRSYSTEM_GITHUB_TOKEN = $token }
        Open-Setup $old.FullName
    } else {
        if ($NoLaunch) { Write-Output ('GABIM: ' + $reason) } else { [void][System.Windows.Forms.MessageBox]::Show("Setup-i nuk u mor: $reason`r`n`r`nKontrollo internetin dhe tokenin.", 'HRSystem Setup', 'OK', 'Error') }
    }
}
finally { try { $form.Dispose() } catch { } }
