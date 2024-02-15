# Powershell config
$SOURCE_PS_CONFIG = "${HOME}\dotfiles\windows\powershell\Microsoft.PowerShell_profile.ps1"
$DESTINATION_PS5_CONFIG = "${HOME}\Documents\WindowsPowerShell"
$DESTINATION_PS7_CONFIG = "${HOME}\Documents\PowerShell"
Copy-Item $SOURCE_PS_CONFIG -Destination $DESTINATION_PS5_CONFIG -Force
Copy-Item $SOURCE_PS_CONFIG -Destination $DESTINATION_PS7_CONFIG -Force

##############
# Run winutils
##############
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-RestMethod https://christitus.com/win | Invoke-Expression