# dotfiles
These are all my dotfiles and configurations that are meant to be interoporable between all machines that I use. I use Windows, macOS, and Linux (Arch and Ubuntu) often. This repository is intended to setup and configure everything needed locally.


## Supported OS
- macOS
- ArchLinux
- Ubuntu (WSL2 and full OS)
- Windows 10/11 (See separate [Windows installation instructions](#run-the-install-windows))

## Requirements
- git
- Python


## Installation
macOS and Ubuntu will need some pre-install commands run to install
git.


### Ubuntu Client/Host Pre-Install
Install git with XCode Command Line Tools:
```sh
sudo apt install git -y
```


### macOS Client/Host Pre-Install
!!! UNTESTED SECTION
Install git with XCode Command Line Tools:
```sh
xcode-select --install
```


### Run the Install (Archlinux, Ubuntu, and macOS)
First, check out the dotfiles repo in your $HOME directory using git.

1. Download
```sh
git clone https://github.com/nightconcept/dotfiles.git
cd dotfiles
```
2. Install dotfiles
```sh
./install
```

### Run the Install (Windows)
Copy and paste the code below into your PowerShell terminal to get your Windows installed.

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$url = "https://raw.githubusercontent.com/nightconcept/dotfiles/main/setup-windows.ps1"
$file = "${HOME}\setup-windows.ps1"

(New-Object -TypeName System.Net.WebClient).DownloadFile($url, $file)
powershell.exe -ExecutionPolicy ByPass -File $file -Verbose
```


## References
- [AlexNabokikh/windows-playbook](https://github.com/AlexNabokikh/windows-playbook) - For configuration on Windows.
- [phelipetls/dotfiles](https://github.com/phelipetls/dotfiles) - For multi-configuration setups and great documentation at [his blog](https://phelipetls.github.io/posts/introduction-to-ansible/).
- [pigmonkey/spark](https://github.com/pigmonkey/spark) - For references on some package installs for ArchLinux
- [ChrisTitusTech/winutil: Chris Titus Tech's Windows Utility - Install Programs, Tweaks, Fixes, and Updates](https://github.com/ChrisTitusTech/winutil) - For additional tools to debloat and configure Windows 11. This tool is called in the setup-windows.ps1 script.