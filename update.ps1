# leads-background update script (Windows / PowerShell)
# Pulls the latest SKILL.md and README.md from GitHub and overwrites the local copy.
# Usage:  powershell -ExecutionPolicy Bypass -File update.ps1
$ErrorActionPreference = "Stop"
$Repo = "DennisTOS/leads-background"
$Branch = "main"
$Base = "https://raw.githubusercontent.com/$Repo/$Branch"
$TargetDir = "$env:USERPROFILE\.workbuddy\skills\leads-background"

Write-Host "leads-background update script"
Write-Host "  repo: $Repo ($Branch)"

if (-not (Test-Path $TargetDir)) { New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null }

$files = @("SKILL.md", "README.md")
foreach ($f in $files) {
    $localPath = Join-Path $TargetDir $f
    $remote = "$Base/$f"
    $oldSize = 0
    if (Test-Path $localPath) { $oldSize = (Get-Item $localPath).Length }
    Write-Host ""
    Write-Host "Downloading $f (local $oldSize bytes)..."
    try {
        Invoke-WebRequest -Uri $remote -OutFile $localPath -UseBasicParsing
    } catch {
        Write-Host "ERROR: failed to download $f - $_" -ForegroundColor Red
        exit 1
    }
    $newSize = (Get-Item $localPath).Length
    if ($newSize -lt 100) {
        Write-Host "WARNING: downloaded file too small ($newSize bytes), network may be restricted" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "OK: $f updated -> $newSize bytes"
}
Write-Host ""
Write-Host "Done! Restart WorkBuddy to load the new version."
Write-Host "Path: $TargetDir"
