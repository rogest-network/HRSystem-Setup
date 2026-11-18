# HRSystem: remove links inside a folder before anything walks it recursively (security review, 2026-11-18/19).
# Loaded by hr-common.ps1 (the folder lock of the setup and the updater) and by uninstall.ps1.
#
# icacls /T, takeown /R, robocopy /MIR and Remove-Item -Recurse follow junctions and symbolic links out of the folder, and a hard link shares the
# permissions and owner of a file that may live elsewhere on the disk. Until the setup closes the install folder, any ordinary user of the PC can
# write in it, so a link planted there (to C:\Windows\System32, say) would make an ELEVATED lock or uninstall change or delete files outside
# HRSystem. HRSystem itself makes no links (npm does not on Windows). Remove-HrLinks deletes every link it finds, only the link (the name), never
# what it points to, and does not walk into linked folders. It returns what it found; an entry ending in "(NUK U HOQ ...)" means a link could
# not be removed or a folder/file could not be checked: callers then skip their recursive steps.

if (-not ('HrLinkInfo' -as [type])) {
  Add-Type -TypeDefinition @'
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
}

function Remove-HrLinks([string]$Path) {
  $found = @()
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $found }
  $queue = New-Object 'System.Collections.Generic.Queue[string]'
  $queue.Enqueue($Path)
  while ($queue.Count -gt 0) {
    $dir = $queue.Dequeue()
    try { $items = (New-Object IO.DirectoryInfo($dir)).GetFileSystemInfos() } catch { $found += "$dir (NUK U HOQ: dosja nuk u lexua)"; continue }
    foreach ($it in $items) {
      $isDir = $it -is [IO.DirectoryInfo]
      if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        # RemoveDirectory / DeleteFile on a junction or symbolic link remove the link, never its target.
        try { if ($isDir) { [IO.Directory]::Delete($it.FullName, $false) } else { [IO.File]::Delete($it.FullName) }; $found += "$($it.FullName) (lidhje)" }
        catch { $found += "$($it.FullName) (NUK U HOQ: $($_.Exception.Message))" }
      } elseif ($isDir) {
        $queue.Enqueue($it.FullName)
      } else {
        $n = [HrLinkInfo]::Links($it.FullName)
        if ($n -gt 1) {
          # A second name of a file that may live outside: deleting this name leaves the other one and the file untouched.
          try { [IO.File]::Delete($it.FullName); $found += "$($it.FullName) (hard link)" }
          catch { $found += "$($it.FullName) (NUK U HOQ: $($_.Exception.Message))" }
        } elseif ($n -lt 0) { $found += "$($it.FullName) (NUK U HOQ: skedari nuk u kontrollua)" }
      }
    }
  }
  return $found
}
