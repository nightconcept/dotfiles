##################
# Helper functions
##################
function Get-ScriptDirectory
{
  $Invocation = (Get-Variable MyInvocation -Scope 1).Value
  Split-Path $Invocation.MyCommand.Path
}


##################################################
# Configure permissions for the rest of the script
##################################################

# Set PowerShell execution policy to RemoteSigned for the current user
$ExecutionPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($ExecutionPolicy -eq "RemoteSigned") {
    Write-Verbose "Execution policy is already set to RemoteSigned for the current user, skipping..." -Verbose
}
else {
    Write-Verbose "Setting execution policy to RemoteSigned for the current user..." -Verbose
    Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
}
###############
# Install Scoop
###############
if ([bool](Get-Command -Name 'scoop' -ErrorAction SilentlyContinue)) {
    Write-Verbose "Scoop is already installed, skip installation." -Verbose
}
else {
    Write-Verbose "Installing Scoop..." -Verbose
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser; Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
}

####################################
# Install Scoop managed applications
####################################

# install official and unofficial scoop buckets
scoop bucket add versions
scoop bucket add extras
scoop bucket add nerd-fonts
scoop bucket add nonportable
scoop bucket add anderlli0053_DEV-tools https://github.com/anderlli0053/DEV-tools
scoop update

# cli_tools_common from /group_vars/all.yml
scoop install main/bat
scoop install main/fzf
scoop install main/zoxide
scoop install main/vim
scoop install extras/hwinfo
scoop install main/winfetch
scoop install main/duf
scoop install main/speedtest-cli
scoop install main/wget
scoop install main/curl
scoop install main/nmap

# cli_tools_windows (or would be if this could be in ansible)
scoop install main/eza
scoop install main/fd
scoop install main/gh
scoop install main/git
scoop install main/gpg
scoop install main/fnm
fnm install --lts
scoop install main/pnpm
scoop install main/starship
scoop isntall extras/terminal-icons

# gui_tools_windows (or would be if this could be in ansible)
scoop install extras/ungoogled-chromium
scoop install extras/vlc
scoop install extras/github
scoop install extras/nextcloud
scoop install extras/obsidian
scoop install extras/vscode
scoop install extras/hexchat
scoop install anderlli0053_DEV-tools/eyeleo-chs-portable
scoop install extras/notepadplusplus
scoop install extras/calibre
scoop install extras/obs-studio
scoop install extras/plex-desktop
scoop install extras/typora
scoop install extras/zoom
scoop install extras/qbittorrent
scoop install extras/rufus
scoop install extras/slack
scoop install extras/ferdium
scoop install extras/windowsspyblocker
scoop install extras/cpu-z
scoop install extras/kitty
scoop install extras/wezterm
scoop install extras/sharex

# install fonts, dual maintained with font/vars/main.yml
scoop install nerd-fonts/SourceCodePro-NF
scoop install nerd-fonts/SourceCodePro-NF-Mono
scoop install nerd-fonts/SourceCodePro-NF-Propo
scoop install nerd-fonts/Noto-NF
scoop install nerd-fonts/Noto-NF-Mono
scoop install nerd-fonts/Noto-NF-Propo
scoop install nerd-fonts/FiraCode-NF
scoop install nerd-fonts/FiraCode-NF-Mono
scoop install nerd-fonts/FiraCode-NF-Propo
scoop install nerd-fonts/DroidSansMono-NF
scoop install nerd-fonts/DroidSansMono-NF-Mono
scoop install nerd-fonts/DroidSansMono-NF-Propo
scoop install nerd-fonts/Inconsolata-NF
scoop install nerd-fonts/Inconsolata-NF-Mono
scoop install nerd-fonts/Inconsolata-NF-Propo
scoop install nerd-fonts/Ubuntu-NF
scoop install nerd-fonts/Ubuntu-NF-Mono
scoop install nerd-fonts/Ubuntu-NF-Propo

#######
# Interactive section where the user is expected to interact or things won't work right
#######

# interactive scoop installs
scoop install nonportable/k-lite-codec-pack-full-np
scoop install anderlli0053_DEV-tools/freefilesync
# freefilsync will fail the first time because there will be a hash mismatch
# it just needs to be run again to install
scoop install anderlli0053_DEV-tools/freefilesync

# install contexts (interactive)
Invoke-Item "$HOME/scoop/apps/vscode/current/install-context.reg" -Confirm
Invoke-Item "$HOME/scoop/apps/vscode/current/install-associations.reg" -Confirm
Invoke-Item "$HOME/scoop/apps/7zip/current/install-context.reg" -Confirm

# install PowerShell7
winget install --id Microsoft.Powershell --source winget

#########################
# Install non-Scoop tools
#########################

# install pyenv-win
Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/pyenv-win/pyenv-win/master/pyenv-win/install-pyenv-win.ps1" -OutFile "./install-pyenv-win.ps1"; &"./install-pyenv-win.ps1"
$pyenv_cmd = "$HOME/.pyenv/pyenv-win/bin/pyenv" 
$pyenv_args = @("install", "3.11.5")
& $pyenv_cmd $pyenv_args

# install PowerShell stuff

# install Oh-My-Posh
scoop install https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/oh-my-posh.json
# (May not be needed in W11) Need newer version (most likely default isn't new enough) for oh-my-posh themes

# install latest version that may be required for some addons to run in PowerShell 5.1
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser; Install-Module -Force PSReadLine

###########################
# Apply dotfiles equivalent
###########################

# get dotfiles
Set-Location $HOME
git clone https://github.com/nightconcept/dotfiles.git

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