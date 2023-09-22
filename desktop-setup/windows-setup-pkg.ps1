# Install scoop
Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://get.scoop.sh')

# install Windows only apps
scoop install git
scoop bucket add main
scoop bucket add versions
scoop bucket add extras
scoop bucket add nerd-fonts
scoop bucket add nonportable
scoop update
scoop install firefox
scoop install ungoogled-chromium
scoop install vlc
scoop install discord
scoop install github
scoop install 7zip
scoop install gpg
# set up 7zip context as well
scoop install obsidian
scoop install vscodium
# TODO: add registry stuff
Write-Output "Add VSCodium as a context menu option by running: 'C:\Users\dark\scoop\apps\vscodium\current\install-context.reg'"
Write-Output "# For VSCodium file associations, run 'C:\Users\dark\scoop\apps\vscodium\current\install-associations.reg'"
scoop install hexchat
scoop install stretchly
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
scoop install python310
scoop install qbittorrent

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