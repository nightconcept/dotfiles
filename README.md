# dotfiles
dotfiles and configuration for Windows setups. See dotfiles-nix for *nix based setups.

## Requirements
- Powershell 7. It might work for Powershell 5.

### Development-Only
- Python >= 3.11 - To gather applications installed by scoop before reformatting a Windows computer.

## Usage
Copy and paste the code below into your PowerShell terminal to get everything set up.

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$url = "https://raw.githubusercontent.com/nightconcept/automatic-os-setup/main/install-windows.ps1"
$file = "${HOME}\install-windows.ps1"
(New-Object -TypeName System.Net.WebClient).DownloadFile($url, $file)
```

## License

Released under [the MIT License](./LICENSE.md).