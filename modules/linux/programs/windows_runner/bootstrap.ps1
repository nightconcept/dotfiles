$ErrorActionPreference = 'Stop'
$winlogon = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty $winlogon -Name AutoAdminLogon -Value '0'
Remove-ItemProperty $winlogon -Name DefaultPassword -ErrorAction SilentlyContinue
$updateSettings = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
foreach ($property in @('PauseFeatureUpdatesStartTime', 'PauseFeatureUpdatesEndTime', 'PauseQualityUpdatesStartTime', 'PauseQualityUpdatesEndTime', 'PauseUpdatesStartTime', 'PauseUpdatesExpiryTime')) {
    Remove-ItemProperty $updateSettings -Name $property -ErrorAction SilentlyContinue
}
$runnerDirectory = 'C:\ForgejoRunner'
New-Item -ItemType Directory -Force -Path $runnerDirectory | Out-Null
Copy-Item 'C:\OEM\run.ps1' "$runnerDirectory\run.ps1" -Force
& icacls.exe $runnerDirectory /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'Administrators:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not protect runner credentials' }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\ForgejoRunner\run.ps1' -WorkingDirectory $runnerDirectory
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable
Register-ScheduledTask -TaskName 'ForgejoRunner' -Action $action -Trigger $trigger -Settings $settings -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName 'ForgejoRunner'
