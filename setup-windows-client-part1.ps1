# Set PowerShell execution policy to RemoteSigned for the current user
$ExecutionPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($ExecutionPolicy -eq "RemoteSigned") {
    Write-Verbose "Execution policy is already set to RemoteSigned for the current user, skipping..." -Verbose
}
else {
    Write-Verbose "Setting execution policy to RemoteSigned for the current user..." -Verbose
    Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
}

# Install Scoop
if ([bool](Get-Command -Name 'scoop' -ErrorAction SilentlyContinue)) {
    Write-Verbose "Scoop is already installed, skip installation." -Verbose
}
else {
    Write-Verbose "Installing Scoop..." -Verbose
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser; Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    # Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
}

# Install chocolatey
if ([bool](Get-Command -Name 'choco' -ErrorAction SilentlyContinue)) {
  Write-Verbose "Chocolatey is already installed, skip installation." -Verbose
}
else {
  Write-Verbose "Installing Chocolatey..." -Verbose
  Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
}