function Get-ScriptDirectory
{
  $Invocation = (Get-Variable MyInvocation -Scope 1).Value
  Split-Path $Invocation.MyCommand.Path
}
$SOURCE_PS_CONFIG = "${HOME}\windows\powershell\Microsoft.PowerShell_profile"
Write-Output $SOURCE_PS_CONFIG