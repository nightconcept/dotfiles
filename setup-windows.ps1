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
}

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
scoop install main/neofetch
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

# gui_tools_windows (or would be if this could be in ansible)
scoop install extras/ungoogled-chromium
scoop install extras/vlc
scoop install extras/github
scoop install extras/nextcloud
scoop install extras/obsidian
scoop install extras/vscode
scoop install extras/hexchat
scoop install anderlli0053_DEV-tools/eyeleo-chs-portable
scoop install anderlli0053_DEV-tools/freefilesync
scoop install extras/notepadplusplus
scoop install extras/calibre
scoop install extras/obs-studio
scoop install extras/plex-desktop
scoop install extras/typora
scoop install extras/zoom
scoop install nonportable/k-lite-codec-pack-full-np
scoop install extras/qbittorrent
scoop install extras/rufus
scoop install extras/slack
scoop install extras/ferdium
scoop install extras/windowsspyblocker
scoop install extras/cpu-z
scoop install extras/kitty
scoop install extras/windows-terminal
scoop install extras/wezterm
scoop install extras/sharex

# install contexts
Invoke-Item "$HOME/scoop/apps/vscode/current/install-context.reg" -Confirm
Invoke-Item "$HOME/scoop/apps/vscode/current/install-associations.reg" -Confirm
Invoke-Item "$HOME/scoop/apps/7zip/current/install-context.reg" -Confirm
Invoke-Item "$HOME/scoop/apps/windows-terminal/current/install-context.reg" -Confirm

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

# install pyenv
Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/pyenv-win/pyenv-win/master/pyenv-win/install-pyenv-win.ps1" -OutFile "./install-pyenv-win.ps1"; &"./install-pyenv-win.ps1"
$pyenv_cmd = "$HOME/.pyenv/pyenv-win/bin/pyenv" 
$pyenv_args = @("install", "3.11.5")
& $pyenv_cmd $pyenv_args

# PowerShell setup
scoop install https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/oh-my-posh.json
# (May not be needed in W11) Need newer version (most likely default isn't new enough) for oh-my-posh themes
# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser; Install-Module -Force PSReadLine

# Create PowerShell settings and config
if (!(Test-Path -Path $PROFILE)) {
  New-Item -ItemType File -Path $PROFILE -Force
}
$FNM = 'fnm env --use-on-cd | Out-String | Invoke-Expression'
$OMP_CONFIG = "oh-my-posh init pwsh --config 'https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/powerlevel10k_rainbow.omp.json' | Invoke-Expression"
Add-Content -Path $PROFILE -Value $FNM
Add-Content -Path $PROFILE -Value $OMP_CONFIG

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$url = "https://raw.githubusercontent.com/nightconcept/dotfiles/main/windows/winutil-config.json"
$file = "$env:temp\winutil-config.json"

(New-Object -TypeName System.Net.WebClient).DownloadFile($url, $file)
Invoke-RestMethod https://christitus.com/win -Config ./winutil-config.json -Run | Invoke-Expression