fnm env --use-on-cd | Out-String | Invoke-Expression
oh-my-posh init pwsh --config 'https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/powerlevel10k_rainbow.omp.json' | Invoke-Expression
Invoke-Expression (& { (zoxide init powershell | Out-String) })
Import-Module -Name Terminal-Icons
