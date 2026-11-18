# HRSystem: closing a folder tree safely, without ever following a link (security review, 2026-11-18/19).
# Loaded by hr-common.ps1 (the folder lock of the setup and the updater) and by uninstall.ps1 (before it deletes anything).
#
# Why: the app runs as SYSTEM from the install folder, which inherited "Authenticated Users: Modify" from C:\. Any ordinary user of the PC could
# change those files, and could also plant links there: icacls /T, takeown /R, robocopy /MIR and Remove-Item -Recurse follow junctions and
# symbolic links out of the folder, and a hard link shares the permissions of a file that may live elsewhere on the disk (changing the top
# folder's permissions spreads them through a hard link to that outside file: seen in a test). So nothing here uses a recursive Windows tool:
#   1. Remove-HrLinks: every link already inside is removed (only the link, never what it points to).
#   2. The top folder gets its final permissions: from now on an ordinary user can only write where an explicit entry of his own still allows it.
#   3. One walk, top down, that never enters a link: each folder is closed (owner, explicit entries) BEFORE its content is read, every link found
#      is removed, and every file is closed too. An item an ordinary user closed to everyone else is taken over by Administrators (takeown /A on
#      that item alone). HRSystem itself makes no links (npm does not on Windows).
# Residual (documented): a link planted in the few milliseconds between steps 1 and 2, or inside a folder that still had an ordinary user's own
# explicit entry while the walk had not reached it, can still receive the top folder's inherited entries: an outside file reached through such a
# hard link gets its inherited permissions REPLACED by HRSystem's (other users may lose access to that one file); nothing is deleted or taken over
# through it. Handles a user's process opened BEFORE the lock keep their access until that process closes them (sign-out or restart).

# Add-Type can be blocked (AppLocker, Constrained Language): then nothing here runs a step and Protect-HrTree answers "not Ok" (never a crash
# of the setup or the updater that loaded this file).
if (-not ('HrLinkInfo' -as [type])) { try {
  Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class HrLinkInfo {
  [StructLayout(LayoutKind.Sequential, Pack = 4)]   // BY_HANDLE_FILE_INFORMATION: FILETIMEs are two DWORDs, no 8-byte alignment
  struct BHFI { public uint Attr; public long Created, Accessed, Written; public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow; }
  [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
  static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool GetFileInformationByHandle(SafeFileHandle handle, out BHFI info);
  // The number of names (hard links) of a file, -1 when it cannot be read. Opened for attributes only, without following a reparse point.
  public static int Links(string path) {
    string p = path.StartsWith(@"\\") ? path : @"\\?\" + path;
    using (SafeFileHandle h = CreateFileW(p, 0x80, 7, IntPtr.Zero, 3, 0x02000000 | 0x00200000, IntPtr.Zero)) {
      if (h.IsInvalid) return -1;
      BHFI info;
      if (!GetFileInformationByHandle(h, out info)) return -1;
      return (int)info.Links;
    }
  }
}
'@
} catch { } }

$script:HrSidSystem = 'S-1-5-18'
$script:HrSidAdmins = 'S-1-5-32-544'
$script:HrSidUsers = 'S-1-5-32-545'

function New-HrSid([string]$Sid) { New-Object Security.Principal.SecurityIdentifier($Sid) }
function Test-HrLink([IO.FileSystemInfo]$Item) { [bool]($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) }

# Removes one link (junction / symbolic link: the link; hard link: this name, unless -KeepHardLinks, used for the data folder where the file may be
# a database file: then it is only reported). Returns a note, or $null when the item is not a link. A note with "(NUK U HOQ ...)" is a failure.
function Remove-HrLinkItem([IO.FileSystemInfo]$Item, [switch]$KeepHardLinks) {
  $isDir = $Item -is [IO.DirectoryInfo]
  if (Test-HrLink $Item) {
    # RemoveDirectory / DeleteFile on a junction or symbolic link remove the link, never its target.
    try { if ($isDir) { [IO.Directory]::Delete($Item.FullName, $false) } else { [IO.File]::Delete($Item.FullName) }; return "$($Item.FullName) (lidhje, u hoq)" }
    catch { return "$($Item.FullName) (NUK U HOQ: $($_.Exception.Message))" }
  }
  if (-not $isDir -and [HrLinkInfo]::Links($Item.FullName) -gt 1) {
    if ($KeepHardLinks) { return "$($Item.FullName) (NUK U HOQ: hard link, skedari ka edhe nje emer tjeter; kontrolloje me dore)" }
    # A second name of a file that may live outside: deleting this name leaves the other one and the file untouched.
    try { [IO.File]::Delete($Item.FullName); return "$($Item.FullName) (hard link, u hoq)" }
    catch { return "$($Item.FullName) (NUK U HOQ: $($_.Exception.Message))" }
  }
  return $null
}

# Step 1 alone (also used by the uninstall's last check): every link inside, without entering one. Returns the notes.
function Remove-HrLinks([string]$Path, [switch]$KeepHardLinks) {
  $found = @()
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $found }
  if (-not ('HrLinkInfo' -as [type])) { return @("$Path (NUK U HOQ: Add-Type u bllokua ne kete kompjuter)") }
  $queue = New-Object 'System.Collections.Generic.Queue[string]'
  $queue.Enqueue($Path)
  while ($queue.Count -gt 0) {
    $dir = $queue.Dequeue()
    $di = New-Object IO.DirectoryInfo($dir)
    $items = $null
    # A folder Administrators cannot read may hide a link: taken over (that folder only) and read again.
    try { $items = $di.GetFileSystemInfos() } catch { Grant-HrAdminAccess $dir; try { $items = $di.GetFileSystemInfos() } catch { $found += "$dir (NUK U HOQ: dosja nuk u lexua)"; continue } }
    foreach ($it in $items) {
      # A file whose number of names cannot be read may be a hard link: never taken over (takeown would change the owner of the linked file
      # outside), only reported. Reading it needs only the right to list the folder, which Administrators have here, so this should not happen.
      if (-not ($it -is [IO.DirectoryInfo]) -and -not (Test-HrLink $it) -and [HrLinkInfo]::Links($it.FullName) -lt 0) {
        $found += "$($it.FullName) (NUK U HOQ: skedari nuk u kontrollua)"; continue
      }
      $note = Remove-HrLinkItem $it -KeepHardLinks:$KeepHardLinks
      if ($note) { $found += $note } elseif ($it -is [IO.DirectoryInfo]) { $queue.Enqueue($it.FullName) }
    }
  }
  return $found
}

# Administrators take over ONE item an ordinary user closed to everyone else (takeown enables the privilege; no /R, no /T).
function Grant-HrAdminAccess([string]$Path) {
  $ErrorActionPreference = 'Continue'
  & takeown.exe /F $Path /A 2>&1 | Out-Null
  & icacls.exe $Path /grant '*S-1-5-32-544:F' /C /Q 2>&1 | Out-Null
}

# The owner and the explicit entries of ONE item (never a link: callers check first). Owner: Administrators unless it is already Administrators,
# SYSTEM or the owner's account. Explicit entries of anyone else are removed; an item left closed to Administrators inherits again.
# Returns $null, or the reason it failed.
function Set-HrItemSecurity([IO.FileSystemInfo]$Item, [string]$OwnerSid, [switch]$UsersRead) {
  $sidT = [Security.Principal.SecurityIdentifier]
  $owners = @($script:HrSidSystem, $script:HrSidAdmins)
  if ($OwnerSid) { $owners += $OwnerSid }
  $allowed = $owners
  if ($UsersRead) { $allowed += $script:HrSidUsers }
  for ($try = 0; $try -lt 2; $try++) {
    try {
      $acl = $Item.GetAccessControl()
      $changed = $false
      if ($owners -notcontains $acl.GetOwner($sidT).Value) { $acl.SetOwner((New-HrSid $script:HrSidAdmins)); $changed = $true }
      # Every Deny entry goes too (HRSystem sets none; one could shut Administrators out), and every entry of anyone else.
      foreach ($r in @($acl.GetAccessRules($true, $false, $sidT))) {
        if ($r.AccessControlType -eq 'Deny' -or $allowed -notcontains $r.IdentityReference.Value) { [void]$acl.RemoveAccessRuleSpecific($r); $changed = $true }
      }
      if ($acl.AreAccessRulesProtected -and -not (@($acl.GetAccessRules($true, $false, $sidT)) | Where-Object { $_.IdentityReference.Value -eq $script:HrSidAdmins -and $_.AccessControlType -eq 'Allow' })) {
        $acl.SetAccessRuleProtection($false, $false); $changed = $true
      }
      if ($UsersRead -and -not (@($acl.GetAccessRules($true, $false, $sidT)) | Where-Object { $_.IdentityReference.Value -eq $script:HrSidUsers })) {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-HrSid $script:HrSidUsers), 'ReadAndExecute, Synchronize', 'Allow'))); $changed = $true
      }
      # .NET writes only the parts that changed: an owner-only change does not touch the permissions below a folder.
      if ($changed) { $Item.SetAccessControl($acl) }
      return $null
    } catch {
      if ($try -eq 0) { Grant-HrAdminAccess $Item.FullName; $Item.Refresh(); continue }
      return "$($Item.FullName) (NUK U MBYLL: $($_.Exception.Message))"
    }
  }
}

# Steps 1-3 for one folder. -UsersTop: ordinary users may list the top folder itself (nothing below); -UsersFiles: names of files directly in
# the top folder they may read and run (Dashboard.bat). Returns @{ Ok; Notes }: Ok is $false when anything could not be closed or removed.
# -KeepHardLinks (the data folder): a hard-linked file is reported and NOTHING is changed (step 2 would spread through it to the outside file).
function Protect-HrTree([string]$Path, [string]$OwnerSid = '', [switch]$UsersTop, [string[]]$UsersFiles = @(), [switch]$KeepHardLinks) {
  $res = [pscustomobject]@{ Ok = $true; Notes = (New-Object 'System.Collections.Generic.List[string]') }
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $res }
  if (-not ('HrLinkInfo' -as [type])) { $res.Ok = $false; $res.Notes.Add("$Path (NUK U MBYLL: Add-Type u bllokua ne kete kompjuter)"); return $res }
  $top = New-Object IO.DirectoryInfo($Path)
  if (Test-HrLink $top) { $res.Ok = $false; $res.Notes.Add("$Path (NUK U MBYLL: dosja vete eshte lidhje drejt nje vendi tjeter)"); return $res }

  # 1. links already inside. ANY failure here (a link that could not be removed, a kept hard link, a folder or file that could not be checked even
  # after a takeover) stops everything: step 2 spreads the top folder's entries through whatever is left. Nothing is changed in that case.
  foreach ($n in @(Remove-HrLinks $Path -KeepHardLinks:$KeepHardLinks)) {
    $res.Notes.Add($n)
    if ($n -like '*(NUK U HOQ*') { $res.Ok = $false }
  }
  if (-not $res.Ok) { return $res }

  # 2. the top folder: exactly these entries, owner Administrators (or kept when already Administrators/SYSTEM/the owner's account)
  $inh = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
  $none = [Security.AccessControl.InheritanceFlags]::None
  $p0 = [Security.AccessControl.PropagationFlags]::None
  $rule = { param($sid, $rights, $flags) New-Object Security.AccessControl.FileSystemAccessRule((New-HrSid $sid), $rights, $flags, $p0, 'Allow') }
  $topDone = $false
  for ($try = 0; $try -lt 2 -and -not $topDone; $try++) {
    try {
      $cur = $top.GetAccessControl()
      $sec = New-Object Security.AccessControl.DirectorySecurity
      $sec.SetAccessRuleProtection($true, $false)
      $sec.AddAccessRule((& $rule $script:HrSidSystem 'FullControl' $inh))
      $sec.AddAccessRule((& $rule $script:HrSidAdmins 'FullControl' $inh))
      if ($OwnerSid) { $sec.AddAccessRule((& $rule $OwnerSid 'Modify, Synchronize' $inh)) }
      if ($UsersTop) { $sec.AddAccessRule((& $rule $script:HrSidUsers 'ReadAndExecute, Synchronize' $none)) }
      $curOwner = $cur.GetOwner([Security.Principal.SecurityIdentifier]).Value
      if (@($script:HrSidAdmins, $script:HrSidSystem, $OwnerSid) -notcontains $curOwner) { $sec.SetOwner((New-HrSid $script:HrSidAdmins)) }
      $top.SetAccessControl($sec)
      $topDone = $true
    } catch {
      if ($try -eq 0) { Grant-HrAdminAccess $Path; $top.Refresh() } else { $res.Ok = $false; $res.Notes.Add("$Path (NUK U MBYLL: $($_.Exception.Message))"); return $res }
    }
  }

  # 3. the walk: each folder closed before it is read, links removed, files closed; never into a link
  $queue = New-Object 'System.Collections.Generic.Queue[string]'
  $queue.Enqueue($Path)
  while ($queue.Count -gt 0) {
    $dir = $queue.Dequeue()
    $di = New-Object IO.DirectoryInfo($dir)
    $items = $null
    try { $items = $di.GetFileSystemInfos() } catch { Grant-HrAdminAccess $dir; try { $items = $di.GetFileSystemInfos() } catch { $res.Ok = $false; $res.Notes.Add("$dir (NUK U LEXUA: $($_.Exception.Message))"); continue } }
    foreach ($it in $items) {
      $note = Remove-HrLinkItem $it -KeepHardLinks:$KeepHardLinks
      if ($note) { $res.Notes.Add($note); if ($note -like '*(NUK U HOQ*') { $res.Ok = $false }; continue }
      $isDir = $it -is [IO.DirectoryInfo]
      if (-not $isDir -and [HrLinkInfo]::Links($it.FullName) -lt 0) {
        # never taken over: it may be a hard link and takeown would change the linked file outside
        $res.Ok = $false; $res.Notes.Add("$($it.FullName) (NUK U KONTROLLUA)"); continue
      }
      $usersRead = (-not $isDir) -and ($dir -eq $Path) -and ($UsersFiles -contains $it.Name)
      $err = Set-HrItemSecurity $it $OwnerSid -UsersRead:$usersRead
      if ($err) { $res.Ok = $false; $res.Notes.Add($err); continue }
      if ($isDir) { $queue.Enqueue($it.FullName) }
    }
  }
  return $res
}
