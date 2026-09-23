<#
.SYNOPSIS
  Write a bootable image to a USB stick on Windows, then optionally copy the
  GopForge-Live bundle onto its FAT data partition.

.EXAMPLE
  # Run in an ELEVATED (Administrator) PowerShell:
  .\write-image-windows.ps1 -Image C:\path\grml-flash.img
  .\write-image-windows.ps1 -Image C:\path\grml-flash.img -DiskNumber 3 -NoInstall

.NOTES
  UNTESTED. Writing to the wrong disk destroys data. If you prefer a GUI, use
  balenaEtcher or Rufus to write the image, then run tools/install-to-usb.sh
  from within the booted GRML environment (or copy the repo onto the FAT
  partition manually). See flash-usb/README.md.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Image,
  [int]$DiskNumber = -1,
  [switch]$NoInstall,
  [switch]$Force   # allow a non-USB target (dangerous)
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Assert-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this in an elevated (Administrator) PowerShell."
  }
}

Assert-Admin
if (-not (Test-Path -LiteralPath $Image)) { throw "Image not found: $Image" }
$imgSize = (Get-Item -LiteralPath $Image).Length

Write-Host "== USB disks ==" -ForegroundColor Cyan
Get-Disk | Where-Object BusType -eq 'USB' |
  Select-Object Number,
    @{N='Size(GB)';E={[math]::Round($_.Size/1GB,1)}},
    FriendlyName, OperationalStatus | Format-Table -AutoSize
Write-Host "(all disks - for reference only:)"
Get-Disk | Select-Object Number, BusType,
    @{N='Size(GB)';E={[math]::Round($_.Size/1GB,1)}},
    FriendlyName, IsSystem, IsBoot | Format-Table -AutoSize

if ($DiskNumber -lt 0) { $DiskNumber = [int](Read-Host "target disk NUMBER") }
$disk = Get-Disk -Number $DiskNumber
if (-not $disk) { throw "no disk number $DiskNumber" }

# --- safety gates ---
if ($disk.IsSystem -or $disk.IsBoot) { throw "REFUSING: disk $DiskNumber is the system/boot disk." }
if ($disk.BusType -ne 'USB' -and -not $Force) {
  throw "REFUSING: disk $DiskNumber is $($disk.BusType), not USB. Re-run with -Force only if you are certain."
}

Write-Host ""
Write-Host "About to ERASE and write:" -ForegroundColor Yellow
Write-Host ("  image : {0}  ({1:N0} bytes)" -f $Image, $imgSize)
Write-Host ("  target: disk {0}  {1}  {2:N1} GB  [{3}]" -f `
  $DiskNumber, $disk.FriendlyName, ($disk.Size/1GB), $disk.BusType)
$confirm = Read-Host "type the disk number again to confirm ($DiskNumber)"
if ($confirm -ne "$DiskNumber") { throw "mismatch - aborted." }

# Clear partitions so the physical device can be opened exclusively, then offline+RW.
Write-Host "> clearing + offlining disk $DiskNumber ..." -ForegroundColor Cyan
Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction SilentlyContinue
Set-Disk  -Number $DiskNumber -IsOffline $true  -ErrorAction SilentlyContinue
Set-Disk  -Number $DiskNumber -IsReadOnly $false -ErrorAction SilentlyContinue

$devPath = "\\.\PhysicalDrive$DiskNumber"
$src = $null; $dst = $null
try {
  $src = [System.IO.File]::OpenRead($Image)
  $dst = New-Object System.IO.FileStream($devPath, [System.IO.FileMode]::Open,
           [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
  $bufSize = 4MB
  $buf = New-Object byte[] $bufSize
  [long]$done = 0
  Write-Host "> writing $devPath ..." -ForegroundColor Cyan
  while (($read = $src.Read($buf, 0, $bufSize)) -gt 0) {
    # pad the final block up to a 512-byte sector boundary for raw device writes
    $w = $read
    if ($w % 512 -ne 0) { $w = [int]([math]::Ceiling($w / 512.0) * 512) }
    $dst.Write($buf, 0, $w)
    $done += $read
    $pct = [int](($done / $imgSize) * 100)
    Write-Progress -Activity "Writing image" -Status "$([math]::Round($done/1MB)) MB" -PercentComplete ([math]::Min($pct,100))
  }
  $dst.Flush()
  Write-Progress -Activity "Writing image" -Completed
  Write-Host "OK image written" -ForegroundColor Green
}
finally {
  if ($dst) { $dst.Dispose() }
  if ($src) { $src.Dispose() }
}

# Bring the disk back so Windows re-reads the new partition table.
Set-Disk -Number $DiskNumber -IsOffline $false -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

if (-not $NoInstall) {
  Write-Host "> installing GopForge-Live bundle onto the FAT partition ..." -ForegroundColor Cyan
  $vol = Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue |
         Get-Volume -ErrorAction SilentlyContinue |
         Where-Object { $_.DriveLetter -and $_.FileSystem -match 'FAT' } |
         Select-Object -First 1
  if ($vol) {
    $target = Join-Path "$($vol.DriveLetter):\" 'gopforge-live'
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    foreach ($d in 'bin','catalog','docs','roms') {
      $s = Join-Path $RepoRoot $d
      if (Test-Path $s) { Copy-Item $s $target -Recurse -Force }
    }
    $gf = Join-Path $RepoRoot 'vendor\gopforge'
    if (Test-Path $gf) {
      New-Item -ItemType Directory -Force -Path (Join-Path $target 'vendor') | Out-Null
      Copy-Item $gf (Join-Path $target 'vendor') -Recurse -Force
    }
    Copy-Item (Join-Path $RepoRoot 'README.md') $target -Force -ErrorAction SilentlyContinue
    # POSIX launcher for use inside the booted GRML environment.
    $run = "#!/usr/bin/env bash`ncd `"`$(dirname `"`$0`")`"`nexec sudo bash bin/gopwizard.sh `"`$@`"`n"
    [System.IO.File]::WriteAllText((Join-Path $target 'run.sh'), $run)
    $n = (Get-ChildItem (Join-Path $target 'roms') -Recurse -Filter *.rom -ErrorAction SilentlyContinue).Count
    Write-Host "OK bundle copied to $target  ($n ROMs)" -ForegroundColor Green
    if ($n -eq 0) { Write-Host "! roms/ was empty - run tools/fetch-roms.sh (on Linux/macOS/WSL) before writing." -ForegroundColor Yellow }
  } else {
    Write-Host "! no FAT partition with a drive letter found on disk $DiskNumber." -ForegroundColor Yellow
    Write-Host "  Reinsert the USB, then copy this repo's bin/catalog/docs/roms into <USB>\gopforge-live\ manually."
  }
}

Write-Host "Done. Safely eject, then boot the target Mac from this USB (hold Option at power-on)."
