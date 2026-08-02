# leads-background update script (Windows / PowerShell) with version check, quiet mode, multi-Agent support
# Compares local vs remote byte size; skips files that are already up to date.
# Primary source (raw.githubusercontent.com) fails -> auto fallback to GitHub Proxy mirrors.
# Usage:
#   powershell -ExecutionPolicy Bypass -File update.ps1            update all installed Agents
#   powershell -ExecutionPolicy Bypass -File update.ps1 -q         quiet mode (output only on real update)
#   powershell -ExecutionPolicy Bypass -File update.ps1 codex      update only the specified Agent (workbuddy/codex/claude/cursor)
#   powershell -ExecutionPolicy Bypass -File update.ps1 -dir C:\custom\path
$ErrorActionPreference = "Stop"
$Repo = "DennisTOS/leads-background"
$Branch = "main"
$Base = "https://raw.githubusercontent.com/$Repo/$Branch"
$Api = "https://api.github.com/repos/$Repo/contents"

# Known Agent skill directories (only existing ones are updated; add a line for new Agents)
$AgentDirs = @{
    "workbuddy" = "$env:USERPROFILE\.workbuddy\skills\leads-background"
    "codex"     = "$env:USERPROFILE\.codex\skills\leads-background"
    "claude"    = "$env:USERPROFILE\.claude\skills\leads-background"
    "cursor"    = "$env:USERPROFILE\.cursor\skills\leads-background"
}

# candidate sources: primary + GitHub Proxy mirrors (fallback in order)
$CandidateBases = @($Base, "https://ghproxy.com/$Base", "https://ghproxy.net/$Base", "https://mirror.ghproxy.com/$Base")

$Quiet = $false
$Targets = @()

# Parse args: -q/--quiet | -dir <path> | <agent name>
$i = 0
while ($i -lt $args.Count) {
    $a = $args[$i]
    if ($a -eq "-q" -or $a -eq "--quiet") {
        $Quiet = $true
    } elseif ($a -eq "-dir" -or $a -eq "--dir") {
        $i++
        if ($i -lt $args.Count) { $Targets += $args[$i] }
    } elseif ($AgentDirs.ContainsKey($a)) {
        $Targets += $AgentDirs[$a]
    } else {
        Write-Host "WARNING: unknown Agent: $a (available: $($AgentDirs.Keys -join ', '))" -ForegroundColor Yellow
    }
    $i++
}

# No args: collect all installed Agent directories; fall back to workbuddy if none exists
if ($Targets.Count -eq 0) {
    foreach ($name in $AgentDirs.Keys) {
        if (Test-Path $AgentDirs[$name]) { $Targets += $AgentDirs[$name] }
    }
    if ($Targets.Count -eq 0) { $Targets += $AgentDirs["workbuddy"] }
}

function Info($m) { if (-not $Quiet) { Write-Host $m } }

Write-Host "leads-background update script"
Write-Host "  repo: $Repo ($Branch)"
Write-Host "  targets: $($Targets -join '; ')"

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

$files = @("SKILL.md", "README.md", "update.sh", "update.ps1")
$overallChanged = $false

foreach ($target in $Targets) {
    Write-Host ""
    Write-Host "==> $target"
    $changed = $false
    New-Item -ItemType Directory -Force -Path $target | Out-Null

    foreach ($f in $files) {
        $localPath = Join-Path $target $f
        $oldSize = 0
        if (Test-Path $localPath) { $oldSize = (Get-Item $localPath).Length }
        $rsize = RemoteSize $f
        if ($rsize -and ($oldSize -eq [int]$rsize)) {
            Info "  OK: $f already up to date ($oldSize bytes), skipped"
            continue
        }
        Write-Host "  Downloading $f (local $oldSize -> remote $rsize)..."
        $dlOk = $false
        foreach ($cb in $CandidateBases) {
            try {
                Invoke-WebRequest -Uri "$cb/$f" -OutFile $localPath -UseBasicParsing -ErrorAction Stop
                $dlOk = $true
                break
            } catch {}
        }
        if (-not $dlOk) {
            Write-Host "  ERROR: all sources (incl. GitHub Proxy mirrors) failed to download $f" -ForegroundColor Red
            exit 1
        }
        $newSize = (Get-Item $localPath).Length
        if ($newSize -lt 100) {
            Write-Host "  WARNING: downloaded file too small ($newSize bytes), network may be restricted" -ForegroundColor Yellow
            exit 1
        }
        Write-Host "  OK: $f updated -> $newSize bytes"
        $changed = $true
    }

    if ($changed) {
        Write-Host "  $target updated. Restart the corresponding Agent conversation to load the new version."
        $overallChanged = $true
    } else {
        Info "  $target all up to date."
    }
}

Write-Host ""
if (-not $overallChanged) {
    Info "All targets are up to date, nothing to do."
}
