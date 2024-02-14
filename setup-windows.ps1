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

# install Windows only apps
scoop install git

# install official and unofficial scoop buckets
scoop bucket add main
scoop bucket add versions
scoop bucket add extras
scoop bucket add nerd-fonts
scoop bucket add nonportable
scoop bucket add anderlli0053_DEV-tools https://github.com/anderlli0053/DEV-tools
scoop update

# add apps
scoop install extras/ungoogled-chromium
scoop install extras/vlc
scoop install extras/github
scoop install main/7zip
scoop install main/gpg
# set up 7zip context as well
scoop install extras/obsidian
scoop install extras/vscode
scoop install extras/hexchat
scoop install anderlli0053_DEV-tools/eyeleo-chs-portable
scoop install anderlli0053_DEV-tools/freefilesync
scoop install extras/notepadplusplus
scoop install main/fnm
fnm install --lts
scoop install main/pnpm
scoop install extras/windows-terminal
scoop install main/starship
scoop install nerd-fonts/FiraCode-NF
scoop install nerd-fonts/FiraCode-NF-Mono
scoop install extras/calibre
scoop install extras/obs-studio
scoop install extras/plex-desktop
scoop install extras/typora
scoop install extras/zoom
scoop install nonportable/k-lite-codec-pack-full-np
scoop install qbittorrent
scoop install extras/rufus
scoop install extras/slack
scoop install extras/eartrumpet
scoop install extras/ferdium
scoop install extras/windowsspyblocker
scoop install extras/hwinfo
scoop install extras/cpu-z
scoop install extras/kitty

# install pyenv
Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/pyenv-win/pyenv-win/master/pyenv-win/install-pyenv-win.ps1" -OutFile "./install-pyenv-win.ps1"; &"./install-pyenv-win.ps1"
pyenv install 3.11.5

# PowerShell setup
scoop install https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/oh-my-posh.json
# Need newer version (most likely default isn't new enough) for oh-my-posh themes
Install-Module -Force PSReadLine

# Create PowerShell settings and config
if (!(Test-Path -Path $PROFILE)) {
  New-Item -ItemType File -Path $PROFILE -Force
}
$FNM = 'fnm env --use-on-cd | Out-String | Invoke-Expression'
$OMP_CONFIG = "oh-my-posh init pwsh --config 'https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/star.omp.json' | Invoke-Expression"
Add-Content -Path $PROFILE -Value $FNM
Add-Content -Path $PROFILE -Value $OMP_CONFIG