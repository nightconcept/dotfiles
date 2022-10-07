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
scoop install vscodium
Write-Output "Add VSCodium as a context menu option by running: 'C:\Users\solivand\scoop\apps\vscodium\current\install-context.reg'"
Write-Output "# For VSCodium file associations, run 'C:\Users\solivand\scoop\apps\vscodium\current\install-associations.reg'"
scoop install notepadplusplus
scoop install gitextensions
scoop install fnm
fnm install --lts
scoop install pnpm
scoop install hyper
scoop install FiraCode-NF
scoop install FiraCode-NF-Mono

# Install productivity apps
scoop install stretchly
scoop install caffeine
scoop install keypirinha