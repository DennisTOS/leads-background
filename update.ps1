# leads-background update script (Windows / PowerShell) with version check + quiet mode
# Compares local vs remote byte size; skips files that are already up to date.
# Usage:
#   powershell -ExecutionPolicy Bypass -File update.ps1          normal mode
#   powershell -ExecutionPolicy Bypass -File update.ps1 -q       quiet mode (output only on real update)
$ErrorActionPreference = "Stop"
$Repo = "DennisTOS/leads-background"
$Branch = "main"
$Base = "https://raw.githubusercontent.com/$Repo/$Branch"
$Api = "https://api.github.com/repos/$Repo/contents"
$TargetDir = "$env:USERPROFILE\.workbuddy\skills\leads-background"

$Quiet = $false
foreach ($a in $args) { if ($a -eq "-q" -or $a -eq "--quiet") { $Quiet = $true } }
function Info($m) { if (-not $Quiet) { Write-Host $m } }

Write-Host "leads-background update script"
Write-Host "  repo: $Repo ($Branch)"

if (-not (Test-Path $TargetDir)) { New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null }

function RemoteSize($f) {
    try {
        $r = Invoke-WebRequest -Uri "$Base/$f" -Method Head -UseBasicParsing -ErrorAction SilentlyContinue
        $cl = $r.Headers["Content-Length"]
        if ($cl) { return $cl }
    } catch {}
    try {
        $j = Invoke-RestMethod -Uri "$Api/$f" -UseBasicParsing -ErrorAction SilentlyContinue
        if ($j.size) { return $j.size }
    } catch {}
    return $null
}

$files = @("SKILL.md", "README.md")
$changed = $false
foreach ($f in $files) {
    $localPath = Join-Path $TargetDir $f
    $oldSize = 0
    if (Test-Path $localPath) { $oldSize = (Get-Item $localPath).Length }
    $rsize = RemoteSize $f
    if ($rsize -and ($oldSize -eq [int]$rsize)) {
        Info "OK: $f already up to date ($oldSize bytes), skipped"
        continue
    }
    Write-Host "Downloading $f (local $oldSize -> remote $rsize)..."
    try {
        Invoke-WebRequest -Uri "$Base/$f" -OutFile $localPath -UseBasicParsing
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
    $changed = $true
}
Write-Host ""
if (-not $changed) {
    Info "All files are up to date, nothing to do."
} else {
    Write-Host "Done! Restart WorkBuddy to load the new version."
}
Write-Host "Path: $TargetDir"
