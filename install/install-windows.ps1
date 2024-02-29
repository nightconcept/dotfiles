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
scoop install extras/terminal-icons

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
scoop install extras/wezterm-nightly
scoop install extras/sharex
scoop install anderlli0053_DEV-tools/googledrive-np
scoop install anderlli0053_DEV-tools/NoMachine-Install

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

##################################
# Install Powershell configuration
##################################
# install Oh-My-Posh
scoop install https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/oh-my-posh.json

# Powershell config
# reference: https://github.com/ChrisTitusTech/powershell-profile
#If the file does not exist, create it.
if (!(Test-Path -Path $PROFILE -PathType Leaf)) {
    try {
        # Detect Version of Powershell & Create Profile directories if they do not exist.
        if ($PSVersionTable.PSEdition -eq "Core" ) { 
            if (!(Test-Path -Path ($env:userprofile + "\Documents\Powershell"))) {
                New-Item -Path ($env:userprofile + "\Documents\Powershell") -ItemType "directory"
            }
        }
        elseif ($PSVersionTable.PSEdition -eq "Desktop") {
            if (!(Test-Path -Path ($env:userprofile + "\Documents\WindowsPowerShell"))) {
                New-Item -Path ($env:userprofile + "\Documents\WindowsPowerShell") -ItemType "directory"
            }
        }

        Invoke-RestMethod https://github.com/nightconcept/dotfiles/raw/main/windows/powershell/Microsoft.PowerShell_profile.ps1 -OutFile $PROFILE
        Write-Host "The profile @ [$PROFILE] has been created."
        write-host "if you want to add any persistent components, please do so at
        [$HOME\Documents\PowerShell\Profile.ps1] as there is an updater in the installed profile 
        which uses the hash to update the profile and will lead to loss of changes"
    }
    catch {
        throw $_.Exception.Message
    }
}
# If the file already exists, show the message and do nothing.
 else {
		 Get-Item -Path $PROFILE | Move-Item -Destination oldprofile.ps1 -Force
		 Invoke-RestMethod https://github.com/nightconcept/dotfiles/raw/main/windows/powershell/Microsoft.PowerShell_profile.ps1 -OutFile $PROFILE
		 Write-Host "The profile @ [$PROFILE] has been created and old profile removed."
         write-host "Please back up any persistent components of your old profile to [$HOME\Documents\PowerShell\Profile.ps1]
         as there is an updater in the installed profile which uses the hash to update the profile 
         and will lead to loss of changes"
 }
& $profile

# Terminal Icons Install
Install-Module -Name Terminal-Icons -Repository PSGallery -Force

##############
# Get dotfiles
##############
Set-Location $HOME
git clone https://github.com/nightconcept/dotfiles.git

##############
# Run winutils
##############
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-RestMethod https://christitus.com/win | Invoke-Expression