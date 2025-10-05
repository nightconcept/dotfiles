# Take ownership of all Git repositories in the current directory
# Must be run as Administrator

$gitRepos = Get-ChildItem -Directory | Where-Object { Test-Path (Join-Path $_.FullName ".git") }

foreach ($repo in $gitRepos) {
    Write-Host "Taking ownership of: $($repo.Name)" -ForegroundColor Cyan

    # Take ownership
    takeown /F $repo.FullName /R /D Y | Out-Null

    # Grant full control to current user
    icacls $repo.FullName /grant "${env:USERNAME}:F" /T /C | Out-Null

    Write-Host "✓ Completed: $($repo.Name)" -ForegroundColor Green
}

Write-Host "`nAll Git repositories have been updated." -ForegroundColor Green
