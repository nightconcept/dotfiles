# dotfiles
These are all my dotfiles and configurations that are meant to be interoporable between all machines that I use. I use Windows, macOS, and Linux (Arch and Ubuntu) often. This repository is intended to setup and configure everything needed locally based off the OS.

## Supported OS
- Windows 10/11 (See separate [Windows installation instructions](#run-the-install-windows))
- macOS
- Arch Linux
- Ubuntu (WSL2 and full OS)

Any other OS may have bits of code that may support it, but is not intended to be fully maintained and can diappear at any time.

## Requirements
- git >= 2.35 (macOS/Arch/Ubuntu) - To pull this repo before running it. Usually 
- Python >= 3.11 (macOS/Arch/Ubuntu) - To run Ansible which will do all of the setup.
- Homebrew >= 4.2.9 (macOS) - Order of events require Homebrew to be installed before running `install.sh`.

## Installation
macOS and Ubuntu will need some bootstrapping commands run to `install.sh`.

### Ubuntu Bootstrapping
Install pre-requisites:
```sh
sudo apt install git -y
sudo apt install python -y
```

### macOS Bootstrapping
!!! NOTE This script should be run once and once only.
```sh
./install/bootstrap-mac.sh
```

### Run the Install (macOS/Arch/Ubuntu)
First, check out the dotfiles repo in your $HOME directory using git.

1. Download
```sh
cd ~
git clone https://github.com/nightconcept/dotfiles.git
cd dotfiles
```
2. Install Applications
```sh
chmod +x ./install.sh
./install.sh
```

3. Install dotfiles
```sh
chmod +x ./dot.sh
./dots.sh
```

### Run the Install (Windows)
Copy and paste the code below into your PowerShell terminal to get your Windows installed.

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$url = "https://raw.githubusercontent.com/nightconcept/dotfiles/main/install/install-windows.ps1"
$file = "${HOME}\install-windows.ps1"
(New-Object -TypeName System.Net.WebClient).DownloadFile($url, $file)
$file
```

## References
- [AlexNabokikh/windows-playbook](https://github.com/AlexNabokikh/windows-playbook) - For configuration on Windows.
- [phelipetls/dotfiles](https://github.com/phelipetls/dotfiles) - For multi-configuration setups and great documentation at [his blog](https://phelipetls.github.io/posts/introduction-to-ansible/).
- [pigmonkey/spark](https://github.com/pigmonkey/spark) - For references on some package installs for ArchLinux
- [ChrisTitusTech/winutil: Chris Titus Tech's Windows Utility - Install Programs, Tweaks, Fixes, and Updates](https://github.com/ChrisTitusTech/winutil) - For additional tools to debloat and configure Windows 11. This tool is called in the setup-windows.ps1 script.
- [craftzdog/dotfiles-public](https://github.com/craftzdog/dotfiles-public) - For nvim and tmux configuration.
- [atomantic/dotfiles](https://github.com/atomantic/dotfiles) - For install scripts.
- [xero/dotfiles](https://github.com/xero/dotfiles) - For just a lot of dotfile information in general.