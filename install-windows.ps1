##################
# Helper functions
##################
function Get-ScriptDirectory
{
  $Invocation = (Get-Variable MyInvocation -Scope 1).Value
  Split-Path $Invocation.MyCommand.Path
}

##################################################
# Configure permissions for the rest of the script
##################################################

# Set PowerShell execution policy to RemoteSigned for the current user
$ExecutionPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($ExecutionPolicy -eq "RemoteSigned") {
    Write-Verbose "Execution policy is already set to RemoteSigned for the current user, skipping..." -Verbose
}
else {
    Write-Verbose "Setting execution policy to RemoteSigned for the current user..." -Verbose
    Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
}
###############
# Install Scoop
###############
if ([bool](Get-Command -Name 'scoop' -ErrorAction SilentlyContinue)) {
    Write-Verbose "Scoop is already installed, skip installation." -Verbose
}
else {
    Write-Verbose "Installing Scoop..." -Verbose
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser; Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
}

####################################
# Install Scoop managed applications
####################################
$url = "https://raw.githubusercontent.com/nightconcept/dotfiles/main/scoop-install-script.ps1"
$file = "${HOME}\scoop-install-script.ps1"
(New-Object -TypeName System.Net.WebClient).DownloadFile($url, $file)
$file

$scoopInstallScript = ".\scoop-install-script.ps1"
Write-Host "Calling $pathToSecondScript..."
$result = & $scoopInstallScript


#######
# Interactive section where the user is expected to interact or things won't work right
# Manually edited scripts
#######

# interactive scoop installs
scoop install nonportable/k-lite-codec-pack-full-np
scoop install anderlli0053_DEV-tools/freefilesync
# freefilsync will fail the first time because there will be a hash mismatch
# it just needs to be run again to install
scoop install anderlli0053_DEV-tools/freefilesync

# install contexts (interactive)
Invoke-Item "$HOME/scoop/apps/vscode/current/install-context.reg" -Confirm
Invoke-Item "$HOME/scoop/apps/vscode/current/install-associations.reg" -Confirm
Invoke-Item "$HOME/scoop/apps/7zip/current/install-context.reg" -Confirm

# install PowerShell7
winget install --id Microsoft.Powershell --source winget

#########################
# Install non-Scoop tools
#########################

# install pyenv-win
Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/pyenv-win/pyenv-win/master/pyenv-win/install-pyenv-win.ps1" -OutFile "./install-pyenv-win.ps1"; &"./install-pyenv-win.ps1"
$pyenv_cmd = "$HOME/.pyenv/pyenv-win/bin/pyenv" 
$pyenv_args = @("install", "3.11.5")
& $pyenv_cmd $pyenv_args

##################################
# Install Powershell configuration
##################################
# install Oh-My-Posh
scoop install https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/oh-my-posh.json

# Powershell config
# reference: https://github.com/ChrisTitusTech/powershell-profile
#If the file does not exist, create it.
if (!(Test-Path -Path $PROFILE -PathType Leaf)) {
    try {
        # Detect Version of Powershell & Create Profile directories if they do not exist.
        if ($PSVersionTable.PSEdition -eq "Core" ) { 
            if (!(Test-Path -Path ($env:userprofile + "\Documents\Powershell"))) {
                New-Item -Path ($env:userprofile + "\Documents\Powershell") -ItemType "directory"
            }
        }
        elseif ($PSVersionTable.PSEdition -eq "Desktop") {
            if (!(Test-Path -Path ($env:userprofile + "\Documents\WindowsPowerShell"))) {
                New-Item -Path ($env:userprofile + "\Documents\WindowsPowerShell") -ItemType "directory"
            }
        }

        Invoke-RestMethod https://github.com/nightconcept/automatic-os-setup/raw/main/windows/powershell/Microsoft.PowerShell_profile.ps1 -OutFile $PROFILE
        Write-Host "The profile @ [$PROFILE] has been created."
        write-host "if you want to add any persistent components, please do so at
        [$HOME\Documents\PowerShell\Profile.ps1] as there is an updater in the installed profile 
        which uses the hash to update the profile and will lead to loss of changes"
    }
    catch {
        throw $_.Exception.Message
    }
}
# If the file already exists, show the message and do nothing.
 else {
		 Get-Item -Path $PROFILE | Move-Item -Destination oldprofile.ps1 -Force
		 Invoke-RestMethod https://github.com/nightconcept/dotfiles/raw/main/windows/powershell/Microsoft.PowerShell_profile.ps1 -OutFile $PROFILE
		 Write-Host "The profile @ [$PROFILE] has been created and old profile removed."
         write-host "Please back up any persistent components of your old profile to [$HOME\Documents\PowerShell\Profile.ps1]
         as there is an updater in the installed profile which uses the hash to update the profile 
         and will lead to loss of changes"
 }
& $profile

# Terminal Icons Install
Install-Module -Name Terminal-Icons -Repository PSGallery -Force

# Copy Config (TODO: UNTESTED)
$username = $env:Danny
$targetPath = "C:\Users\$username"
$githubRepoUrl = "https://github.com/nightconcept/dotfiles"
$sourceFolderInRepo = ".config"
$zipFileName = "dotfiles.zip"
$extractedFolderName = "dotfiles-main" # The name of the extracted root folder

# Construct the URL to download the repository as a ZIP file
$zipUrl = "$githubRepoUrl/archive/refs/heads/main.zip"

# Define the full path to the downloaded ZIP file
$zipFilePath = Join-Path -Path $env:TEMP -ChildPath $zipFileName

# Define the full path to the extracted source folder
$extractedSourcePath = Join-Path -Path $env:TEMP -ChildPath "$extractedFolderName/$sourceFolderInRepo"

# Define the full path to the target .config folder
$targetConfigPath = Join-Path -Path $targetPath -ChildPath ".config"

# Create the target .config directory if it doesn't exist
if (-not (Test-Path -Path $targetConfigPath -PathType Container)) {
    try {
        Write-Host "Creating target directory: '$targetConfigPath'"
        New-Item -Path $targetConfigPath -ItemType Directory -Force | Out-Null
    }
    catch {
        Write-Error "Error creating target directory: $($_.Exception.Message)"
        exit
    }
}

# Download the GitHub repository as a ZIP file
try {
    Write-Host "Downloading repository ZIP file from '$zipUrl' to '$zipFilePath'"
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipFilePath
}
catch {
    Write-Error "Error downloading ZIP file: $($_.Exception.Message)"
    exit
}

# Extract the ZIP file
try {
    Write-Host "Extracting ZIP file to '$env:TEMP'"
    Expand-Archive -Path $zipFilePath -DestinationPath $env:TEMP -Force
}
catch {
    Write-Error "Error extracting ZIP file: $($_.Exception.Message)"
    exit
}

# Copy the desired folder from the extracted location to the target
if (Test-Path -Path $extractedSourcePath -PathType Container) {
    try {
        Write-Host "Copying contents from '$extractedSourcePath' to '$targetConfigPath'"
        Get-ChildItem -Path $extractedSourcePath -Recurse | Copy-Item -Destination $targetConfigPath -Force
        Write-Host "Successfully copied contents of '$sourceFolderInRepo' to '$targetConfigPath'"
    }
    catch {
        Write-Error "Error copying files: $($_.Exception.Message)"
    }
}
else {
    Write-Warning "The folder '$sourceFolderInRepo' was not found in the extracted ZIP file."
}

# Clean up the downloaded ZIP file and extracted folder
try {
    Remove-Item -Path $zipFilePath -Force
    Remove-Item -Path (Join-Path -Path $env:TEMP -ChildPath $extractedFolderName) -Recurse -Force
    Write-Host "Cleaned up temporary files."
}
catch {
    Write-Warning "Error during cleanup: $($_.Exception.Message)"
}

##############
# Run winutils
##############
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-RestMethod https://christitus.com/win | Invoke-Expression