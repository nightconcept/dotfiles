$ErrorActionPreference = 'Stop'
$runnerDirectory = 'C:\ForgejoRunner'
Set-Location $runnerDirectory
try {
    $share = '\\host.lan\Data'
    if (-not (Test-Path "$share\forgejo-runner.exe")) {
        throw 'Provisioning share is unavailable; the scheduled task will retry'
    }
    Copy-Item "$share\forgejo-runner.exe" "$runnerDirectory\forgejo-runner.exe" -Force
    $connection = Get-Content "$share\connection.yml" -Raw
    if ([string]::IsNullOrWhiteSpace($connection)) {
        throw 'Populate the host connection.yml file, then retry'
    }
    $configuration = (Get-Content "$share\config.yml" -Raw) + "`n" + $connection
    [IO.File]::WriteAllText("$runnerDirectory\config.yml", $configuration, (New-Object Text.UTF8Encoding($false)))
    Copy-Item "$share\run.ps1" "$runnerDirectory\run.ps1" -Force

    if (-not (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $installer = Invoke-WebRequest -UseBasicParsing 'https://community.chocolatey.org/install.ps1'
        Invoke-Expression $installer.Content
    }
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    & choco.exe install git powershell-core nodejs-lts --yes --no-progress --limit-output
    if ($LASTEXITCODE -notin @(0, 1641, 3010)) { throw 'Build tool installation failed' }
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    & git.exe config --system core.longpaths true

    $runner = Start-Process -FilePath "$runnerDirectory\forgejo-runner.exe" -ArgumentList 'daemon', '--config', "$runnerDirectory\config.yml" -RedirectStandardOutput "$runnerDirectory\runner.out.log" -RedirectStandardError "$runnerDirectory\runner.err.log" -Wait -PassThru
    if ($runner.ExitCode -ne 0) { throw "Runner daemon stopped with exit code $($runner.ExitCode)" }
} catch {
    Write-Error $_
    exit 1
}
