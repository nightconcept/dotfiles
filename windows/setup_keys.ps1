#!/usr/bin/env pwsh
#
# One-time SSH key setup script for Windows
#
# Extracts encrypted keys from the bootstrap archive and deploys them.
# Configures git for SSH commit signing.
#
# Requirements: gpg (via scoop: `scoop install gpg` or winget: `winget install GnuPG.GnuPG`)
#

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Colors
function Write-Info    { param($msg) Write-Host "[INFO] $msg"    -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[WARNING] $msg" -ForegroundColor Yellow }
function Write-Err     { param($msg) Write-Host "[ERROR] $msg"   -ForegroundColor Red }

# Configuration
$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir      = Split-Path -Parent $ScriptDir
$BootstrapDir = Join-Path $RepoDir "scripts\bootstrap"
$KeysArchive  = Join-Path $BootstrapDir "keys.tar.gz.gpg"
$WorkDir      = Join-Path $env:TEMP "dotfiles-key-setup-$PID"

$SshDir       = Join-Path $HOME ".ssh"
$SshKeyPath   = Join-Path $SshDir "id_sdev"
$SshPubPath   = Join-Path $SshDir "id_sdev.pub"
$AllowedSignersPath = Join-Path $SshDir "allowed_signers"
$AgeDir       = Join-Path $HOME ".config\sops\age"
$AgeKeyPath   = Join-Path $AgeDir "keys.txt"

function Set-SshKeyPermissions {
    param([string]$Path)
    # Remove inherited permissions and grant only the current user full control
    # This is required by OpenSSH on Windows — keys with loose permissions are rejected
    icacls $Path /inheritance:r | Out-Null
    icacls $Path /grant:r "${env:USERNAME}:(F)" | Out-Null
}

function Test-GpgAvailable {
    return [bool](Get-Command gpg -ErrorAction SilentlyContinue)
}

function Remove-WorkDir {
    if (Test-Path $WorkDir) {
        Remove-Item -Path $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "SSH and Age Key Setup (Windows)"
Write-Host "================================"
Write-Host ""

# Check for gpg
if (-not (Test-GpgAvailable)) {
    Write-Err "gpg not found. Install it first:"
    Write-Host "  scoop install gpg"
    Write-Host "  # or"
    Write-Host "  winget install GnuPG.GnuPG"
    exit 1
}

# Check if keys already exist
$keysExist = (Test-Path $SshKeyPath) -and (Test-Path $AgeKeyPath)
if ($keysExist) {
    Write-Warn "Keys already exist!"
    Write-Host "  $SshKeyPath"
    Write-Host "  $AgeKeyPath"
    Write-Host ""
    $reply = Read-Host "Overwrite existing keys? (y/N)"
    if ($reply -notmatch "^[Yy]$") {
        Write-Info "Setup cancelled"
        exit 0
    }
}

# Check for archive
if (-not (Test-Path $KeysArchive)) {
    Write-Err "Keys archive not found at: $KeysArchive"
    Write-Info "This script requires the bootstrap keys archive to exist."
    exit 1
}

# Create work dir
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null

try {
    # Decrypt and extract archive
    Write-Info "Decrypting key archive..."
    $bootstrapPassword = Read-Host "Enter bootstrap password" -AsSecureString
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($bootstrapPassword)
    )

    # gpg decrypt to a .tar.gz, then extract
    $tarPath = Join-Path $WorkDir "keys.tar.gz"
    $gpgArgs = @(
        "--batch", "--yes",
        "--passphrase", $plainPassword,
        "--output", $tarPath,
        "--decrypt", $KeysArchive
    )
    & gpg @gpgArgs 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Failed to decrypt archive. Wrong password?"
        exit 1
    }
    Write-Success "Archive decrypted successfully"

    # Extract (tar is built-in on Windows 10+)
    & tar -xzf $tarPath -C $WorkDir
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Failed to extract archive"
        exit 1
    }

    # Verify expected files exist
    $extractedKey = Join-Path $WorkDir "id_sdev_extracted"
    $extractedAge = Join-Path $WorkDir "age_keys_extracted"
    if (-not (Test-Path $extractedKey) -or -not (Test-Path $extractedAge)) {
        Write-Err "Missing expected keys in archive. Contents:"
        Get-ChildItem $WorkDir | Format-Table Name
        exit 1
    }

    Write-Info "Found keys:"
    Write-Host "  + SSH private key (id_sdev_extracted)"
    Write-Host "  + Age key (age_keys_extracted)"
    Write-Host ""

    # Deploy SSH private key
    New-Item -ItemType Directory -Path $SshDir -Force | Out-Null
    Copy-Item -Path $extractedKey -Destination $SshKeyPath -Force
    Set-SshKeyPermissions $SshKeyPath
    Write-Success "Deployed SSH private key to $SshKeyPath"

    # Generate public key from private key (needed for git signing config)
    & ssh-keygen -y -f $SshKeyPath | Out-File -FilePath $SshPubPath -Encoding ascii -NoNewline
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Could not generate public key — you may need to do this manually: ssh-keygen -y -f $SshKeyPath > $SshPubPath"
    } else {
        Write-Success "Generated SSH public key at $SshPubPath"
    }

    # Deploy age key
    New-Item -ItemType Directory -Path $AgeDir -Force | Out-Null
    Copy-Item -Path $extractedAge -Destination $AgeKeyPath -Force
    icacls $AgeKeyPath /inheritance:r | Out-Null
    icacls $AgeKeyPath /grant:r "${env:USERNAME}:(F)" | Out-Null
    Write-Success "Deployed age key to $AgeKeyPath"

    # Create allowed_signers file for git SSH signing verification
    $allowedSignersContent = "dark@nightconcept.net ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMJKTm63zFmYfGauCBlUWq7lvHFq+NVPT5RqIfjLM7MN danny@solivan.dev"
    Set-Content -Path $AllowedSignersPath -Value $allowedSignersContent -Encoding ascii
    Write-Success "Created allowed signers file at $AllowedSignersPath"

    # Configure git for SSH signing
    Write-Info "Configuring git for SSH commit signing..."
    $sshPubPathForwardSlash = $SshPubPath -replace "\\", "/"
    $allowedSignersForwardSlash = $AllowedSignersPath -replace "\\", "/"

    git config --global user.name "Danny Solivan"
    git config --global user.email "dark@nightconcept.net"
    git config --global gpg.format ssh
    git config --global user.signingkey $sshPubPathForwardSlash
    git config --global gpg.ssh.allowedSignersFile $allowedSignersForwardSlash
    git config --global commit.gpgsign true
    git config --global tag.gpgsign true
    Write-Success "Git configured for SSH signing"

    Write-Host ""
    Write-Success "Key setup complete!"
    Write-Host ""
    Write-Info "Verify signing works with: git log --show-signature"
}
finally {
    # Scrub password from memory
    if ($plainPassword) { $plainPassword = $null }
    Remove-WorkDir
}
