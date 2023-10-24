# Setup scoop
Set-ExecutionPolicy RemoteSigned -scope CurrentUser
Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://get.scoop.sh')

# Setup scoop buckets
scoop bucket add main
scoop bucket add versions
scoop bucket add extras
scoop bucket add nonportable
scoop bucket add nerd-fonts

# Install development apps
scoop install heidisql
scoop install extras/vscode
scoop install extras/pycharm
scoop install gitextensions
scoop install fnm
fnm install --lts
scoop install pnpm
scoop install gpg
scoop install github
scoop install windows-terminal
scoop install FiraCode-NF
scoop install FiraCode-NF-Mono

# Install productivity apps
scoop install stretchly
scoop install caffeine
scoop install extras/obsidian

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