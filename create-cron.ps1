# 备份任务
$action    = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument '-NoProfile -ExecutionPolicy Bypass -File "D:\Scripts\vm-backup.ps1"'
$trigger   = New-ScheduledTaskTrigger -Daily -At "04:00PM"
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 4)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" `
    -LogonType ServiceAccount -RunLevel Highest

Register-ScheduledTask -TaskName "VMware-AutoBackup" `
    -Action $action -Trigger $trigger -Settings $settings `
    -Principal $principal -Description "VMware Control Daily Backup"

# 启动任务
$action    = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "D:\Scripts\vm-start.ps1"'
$trigger   = New-ScheduledTaskTrigger -AtLogOn
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName "VMware-AutoStart" `
    -Action $action -Trigger $trigger -Settings $settings `
    -Description "Start Control VM at Windows boot"
