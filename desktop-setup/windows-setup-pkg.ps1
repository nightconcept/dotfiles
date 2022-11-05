# Install Chocolatey and scoop
Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://get.scoop.sh')

# Install Ubuntu-20.04 LTS onto WSL
# wsl --install -d Ubuntu-20.04
# can this be integrated into 1 command instead of two?
# wsl --set-version Ubuntu-20.04 2

# install Windows only apps
scoop bucket add main
scoop bucket add versions
scoop bucket add extras
scoop bucket add nerd-fonts
scoop update
scoop install firefox-developer
scoop install ungoogled-chromium
scoop install vlc
scoop install discord
scoop install git
scoop install gh
scoop install github
scoop install 7zip
# set up 7zip context as well
scoop install obsidian
scoop install vscodium
Write-Output "Add VSCodium as a context menu option by running: 'C:\Users\dark\scoop\apps\vscodium\current\install-context.reg'"
Write-Output "# For VSCodium file associations, run 'C:\Users\dark\scoop\apps\vscodium\current\install-associations.reg'"
scoop install hexchat
scoop install stretchly
scoop install notepadplusplus
scoop install fnm
fnm install --lts
scoop install pnpm
scoop install hyper
scoop install FiraCode-NF
scoop install FiraCode-NF-Mono
scoop install calibre
scoop install obs-studio
scoop install plex-desktop
scoop install spotify
scoop install typora
scoop install zoom
scoop install k-lite-codec-pack-full-np
scoop install python38
scoop install qbittorrent