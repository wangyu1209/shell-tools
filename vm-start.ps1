# ============================================================
# VMware Auto Start Script
# VM: Control - Start at Windows Boot
# ============================================================

$VMRUN   = "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe"
$VMX     = "C:\Users\WY\Documents\Virtual Machines\Control\control.vmx"
$LogFile = "D:\VM-Backups\autostart.log"

function Write-Log {
    param([string]$Msg)
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] $Msg"
    $logDir = Split-Path $LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

Write-Log "Auto start script triggered"

# Wait for VMware service to be ready (check every 5 seconds, max 120 seconds)
Write-Log "Waiting for VMware service..."
$ready = $false
$elapsed = 0
while (-not $ready -and $elapsed -lt 120) {
    $service = Get-Service -Name "VMwareHostd" -ErrorAction SilentlyContinue
    if ($service -and $service.Status -eq "Running") {
        $ready = $true
    } else {
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
}

if (-not $ready) {
    Write-Log "ERROR: VMware service not started within 120 seconds"
    exit 1
}

Write-Log "VMware service ready (${elapsed}s)"

# Check VMX
if (-not (Test-Path $VMX)) {
    Write-Log "ERROR: VMX not found"
    exit 1
}

# Check if already running
$listOutput = & $VMRUN -T ws list 2>$null
if ($listOutput -match [regex]::Escape($VMX)) {
    Write-Log "VM already running, skipping"
    exit 0
}

# Start VM
Write-Log "Starting VM (headless)..."
& $VMRUN -T ws start $VMX nogui 2>$null | Out-Null
Write-Log "VM started"
