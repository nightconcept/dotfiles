Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://get.scoop.sh')

wsl --install -d Ubuntu-20.04

# install Windows only apps
scoop bucket add main
scoop bucket add versions
scoop bucket add extras
scoop update
scoop install firefox-developer
scoop install ungoogled-chromium
scoop install vlc
scoop install discord
scoop install git
scoop install 7zip
# set up 7zip context as well
scoop install obsidian
scoop install vscodium