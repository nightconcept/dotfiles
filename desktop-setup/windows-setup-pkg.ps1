# Install scoop
Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://get.scoop.sh')

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
scoop install ungoogled-chromium
scoop install vlc
scoop install discord
scoop install github
scoop install 7zip
scoop install gpg
# set up 7zip context as well
scoop install obsidian
scoop install extras/vscode
scoop install hexchat
scoop install anderlli0053_DEV-tools/eyeleo-chs-portable
scoop install notepadplusplus
scoop install fnm
fnm install --lts
scoop install pnpm
scoop install windows-terminal
scoop install starship
scoop install FiraCode-NF
scoop install FiraCode-NF-Mono
scoop install calibre
scoop install obs-studio
scoop install plex-desktop
scoop install typora
scoop install zoom
scoop install k-lite-codec-pack-full-np
scoop install qbittorrent

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