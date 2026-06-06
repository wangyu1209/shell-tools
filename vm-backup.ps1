# ============================================================
# VMware Shutdown Backup Script
# VM: Control
# ============================================================

# ---- Config ----
$VMRUN       = "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe"
$VMX         = "C:\Users\WY\Documents\Virtual Machines\Control\control.vmx"
$VMName      = "Control"
$BackupRoot  = "D:\VM-Backups"
$RetainCount = 7
$LogFile     = "D:\VM-Backups\backup.log"

$SevenZip    = "C:\Program Files\7-Zip\7z.exe"
if (-not (Test-Path $SevenZip)) {
    $SevenZip = "C:\Program Files (x86)\7-Zip\7z.exe"
}

$SevenZipUrl       = "https://www.7-zip.org/a/7z2409-x64.exe"
$SevenZipInstaller = "$env:TEMP\7z-install.exe"

# ---- Log Function ----
function Write-Log {
    param([string]$Msg)
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $Msg"
    Write-Host $line
    $logDir = Split-Path $LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

# ---- Install 7-Zip ----
$UseCompress = $true

function Install-7Zip {
    if (Test-Path $SevenZip) {
        Write-Log "7-Zip already installed: $SevenZip"
        return $true
    }

    $altPath = "C:\Program Files (x86)\7-Zip\7z.exe"
    if (Test-Path $altPath) {
        $script:SevenZip = $altPath
        Write-Log "7-Zip already installed: $altPath"
        return $true
    }

    Write-Log "7-Zip not found, downloading and installing..."

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Write-Log "Downloading from: $SevenZipUrl"
        Invoke-WebRequest -Uri $SevenZipUrl -OutFile $SevenZipInstaller -UseBasicParsing
        Write-Log "Download complete"

        Write-Log "Installing 7-Zip silently..."
        Start-Process -FilePath $SevenZipInstaller -ArgumentList "/S" -Wait -NoNewWindow

        Remove-Item -Path $SevenZipInstaller -Force -ErrorAction SilentlyContinue

        Start-Sleep -Seconds 3
        if (Test-Path $SevenZip) {
            Write-Log "7-Zip installed successfully: $SevenZip"
            return $true
        } else {
            Write-Log "WARN: 7-Zip installation failed"
            return $false
        }
    } catch {
        Write-Log "WARN: Failed to install 7-Zip: $($_.Exception.Message)"
        return $false
    }
}

# ---- Pre-check ----
if (-not (Test-Path $VMRUN)) {
    Write-Log "ERROR: vmrun not found: $VMRUN"
    exit 1
}

if (-not (Test-Path $VMX)) {
    Write-Log "ERROR: VMX file not found: $VMX"
    exit 1
}

if (-not (Install-7Zip)) {
    Write-Log "WARN: 7-Zip not available, will backup without compression"
    $UseCompress = $false
}

# ---- Main ----
$startTime = Get-Date
$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$backupDir = Join-Path $BackupRoot "$VMName\$timestamp"

Write-Log "========== Backup Start: $VMName =========="
Write-Log "Mode    : Shutdown"
Write-Log "Compress: $UseCompress"
Write-Log "Target  : $backupDir"

# Check if VM is running
$listOutput = & $VMRUN -T ws list 2>$null
$wasRunning = $false
if ($listOutput -match [regex]::Escape($VMX)) {
    $wasRunning = $true
}

# Shutdown if running
if ($wasRunning) {
    Write-Log "VM is running, sending shutdown command..."
    & $VMRUN -T ws stop $VMX soft 2>&1 | Out-Null

    $elapsed = 0
    $timeout = 120
    $stillRunning = $true

    while ($stillRunning -and $elapsed -lt $timeout) {
        Start-Sleep -Seconds 5
        $elapsed += 5
        $check = & $VMRUN -T ws list 2>$null
        if ($check -match [regex]::Escape($VMX)) {
            $stillRunning = $true
            Write-Log "  Waiting... ($elapsed / $timeout sec)"
        } else {
            $stillRunning = $false
        }
    }

    if ($stillRunning) {
        Write-Log "Graceful shutdown timed out, forcing power off..."
        & $VMRUN -T ws stop $VMX hard 2>$null | Out-Null
        Start-Sleep -Seconds 10
    }

    Write-Log "VM shutdown complete"
} else {
    Write-Log "VM is not running, skipping shutdown"
}

# Copy VM files
Write-Log "Copying VM files..."
$vmDir = Split-Path $VMX -Parent
New-Item -Path $backupDir -ItemType Directory -Force | Out-Null

$totalBytes = 0

Get-ChildItem -Path $vmDir -File | ForEach-Object {
    $sizeMB  = [math]::Round($_.Length / 1MB, 1)
    $sizeStr = "${sizeMB} MB"
    Write-Log "  Copy: $($_.Name) ($sizeStr)"
    Copy-Item -Path $_.FullName -Destination $backupDir -Force
    $totalBytes += $_.Length
}

Get-ChildItem -Path $vmDir -Directory | ForEach-Object {
    $subDir    = $_.FullName
    $subName   = $_.Name
    $subDest   = Join-Path $backupDir $subName
    $diskFiles = Get-ChildItem -Path $subDir -File | Where-Object { $_.Extension -eq '.vmdk' }

    if ($diskFiles) {
        New-Item -Path $subDest -ItemType Directory -Force | Out-Null
        foreach ($disk in $diskFiles) {
            $diskMB  = [math]::Round($disk.Length / 1MB, 1)
            $diskStr = "${diskMB} MB"
            Write-Log "  Copy: $subName\$($disk.Name) ($diskStr)"
            Copy-Item -Path $disk.FullName -Destination $subDest -Force
            $totalBytes += $disk.Length
        }
    }
}

$totalGB = [math]::Round($totalBytes / 1GB, 2)
Write-Log "Copy complete: ${totalGB} GB"

# Compress with 7-Zip
if ($UseCompress) {
    Write-Log "Compressing with 7-Zip..."
    $zipPath = "${backupDir}.7z"

    $argList = @(
        "a"
        "-t7z"
        "-mx=1"
        "-mmt=on"
        "`"$zipPath`""
        "`"$backupDir`""
    )

    $proc = Start-Process -FilePath $SevenZip `
        -ArgumentList $argList `
        -NoNewWindow -Wait -PassThru

    if ($proc.ExitCode -eq 0) {
        Remove-Item -Path $backupDir -Recurse -Force
        $zipSize = Get-Item $zipPath
        $zipGB   = [math]::Round($zipSize.Length / 1GB, 2)
        Write-Log "Compress done: ${zipGB} GB"
    } else {
        Write-Log "WARN: 7-Zip compression failed (ExitCode: $($proc.ExitCode))"
        Write-Log "Keeping uncompressed backup files"
    }
} else {
    Write-Log "Skipped compression (7-Zip not available)"
    Write-Log "Backup saved as uncompressed folder"
}

# Start VM
if ($wasRunning) {
    Write-Log "Starting VM..."
    & $VMRUN -T ws start $VMX 2>$null | Out-Null
    Write-Log "VM started"
}

# Rotation - delete old backups
$vmBackupDir = Join-Path $BackupRoot $VMName
if (Test-Path $vmBackupDir) {
    $backups = Get-ChildItem -Path $vmBackupDir | Sort-Object Name -Descending
    if ($backups.Count -gt $RetainCount) {
        $oldBackups = $backups[$RetainCount..($backups.Count - 1)]
        foreach ($old in $oldBackups) {
            Write-Log "Delete old backup: $($old.Name)"
            Remove-Item -Path $old.FullName -Recurse -Force
        }
    }

    $currentCount = $backups.Count
    if ($currentCount -gt $RetainCount) {
        $currentCount = $RetainCount
    }
    Write-Log "Current backup count: $currentCount"
}

$duration = (Get-Date) - $startTime
$durStr   = $duration.ToString('hh\:mm\:ss')
Write-Log "========== Backup Done: $VMName | Duration: $durStr =========="
