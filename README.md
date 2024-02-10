# dotfiles
These are all my dotfiles and configurations that are meant to be interoporable between all machines that I use. I use Windows, macOS, and Linux (Arch and Ubuntu) often. This repository is intended to setup and configure itself.


## Supported OS
- Windows 10/11
- macOS
- ArchLinux
- Ubuntu (WSL2 and full OS)


## Requirements
- git (control node)
- Python (control node and managed node)


## Installation
Windows, macOS, and Ubuntu will need some pre-install commands run to install
git.

!!! NOTE IMPORTANT: Windows will need to be run remotely as Windows is not supported as a control for Ansible. All other operating systems install should be run locally.


### Windows Client Pre-Install
Copy and paste the code below into your PowerShell terminal to get your Windows machine ready to work with Ansible.

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$url = "https://raw.githubusercontent.com/nightconcept/dotfiles/main/setup-windows-client.ps1"
$file = "$env:temp\setup-windows-client.ps1"

(New-Object -TypeName System.Net.WebClient).DownloadFile($url, $file)
powershell.exe -ExecutionPolicy ByPass -File $file -Verbose
```

### macOS Client Pre-Install
!!! NOTE UNTESTED SECTION
Install git with XCode Command Line Tools:
```
xcode-select --install
```

### Run the Install on Control Node
First, check out the dotfiles repo in your $HOME directory using git.

1. Download
```sh
git clone https://github.com/nightconcept/dotfiles.git
cd dotfiles
```
2. Install Ansible
```sh
./install
```

3. Run Playbook
```sh
# Bootstrap development environntment in Linux, WSL and macOS
ansible-playbook bootstrap.yml
```


## Inspiration dotfiles
- [AlexNabokikh/windows-playbook](https://github.com/AlexNabokikh/windows-playbook) - For configuration on Windows.
- [phelipetls/dotfiles](https://github.com/phelipetls/dotfiles) - For multi-configuration setups and great documentation at [his blog](https://phelipetls.github.io/posts/introduction-to-ansible/).
- [pigmonkey/spark](https://github.com/pigmonkey/spark) - For references on some package installs for ArchLinux