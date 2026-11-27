# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

param(
    [ValidateSet("perf", "balance", "matrix", "watch", "audit")]
    [string]$Mode = "perf",
    [ValidateSet("all", "balanced", "mono", "comps")]
    [string]$MatrixSet = "all",
    [string]$Build = "balanced",
    [string]$Leader = "knight",
    [int]$Seeds = 0,
    [int]$Seed = 0,
    [int]$MaxDepth = 12,
    [int]$MaxFrames = -1,
    [double]$Speed = 0.0,
    [string]$Immortal = "",
    [int]$Jobs = 0,
    [string]$Out = "",
    [switch]$Gpu,
    [switch]$FullCombat
)

$repoRoot = Split-Path $PSScriptRoot -Parent
$cacheDir = Join-Path $repoRoot ".venv\cache"
$appDataDir = Join-Path $cacheDir "appdata"
$localAppDataDir = Join-Path $cacheDir "localappdata"

if (-Not (Test-Path $appDataDir)) {
    New-Item -ItemType Directory -Path $appDataDir -Force | Out-Null
}
if (-Not (Test-Path $localAppDataDir)) {
    New-Item -ItemType Directory -Path $localAppDataDir -Force | Out-Null
}

$env:LOCALAPPDATA = $localAppDataDir
$env:APPDATA = $appDataDir

$effectiveSeeds = $Seeds
if ($effectiveSeeds -le 0) {
    if ($Seed -gt 0) {
        $effectiveSeeds = 1
    } elseif ($Mode -eq "audit") {
        $effectiveSeeds = 50
    } elseif ($Mode -eq "perf") {
        $effectiveSeeds = 3
    } elseif ($Mode -eq "watch") {
        $effectiveSeeds = 1
    } elseif ($Mode -eq "matrix") {
        $effectiveSeeds = 10
    } else {
        $effectiveSeeds = 20
    }
}

$effectiveSeed = if ($Seed -gt 0) { $Seed } else { 12345 }

$userArgs = @(
    "--mode=$Mode",
    "--build=$Build",
    "--leader=$Leader",
    "--seeds=$effectiveSeeds",
    "--seed=$effectiveSeed",
    "--max_depth=$MaxDepth"
)
if ($Mode -eq "matrix") {
    $userArgs += "--matrix_set=$MatrixSet"
}

if ($MaxFrames -ge 0) {
    $userArgs += "--max_frames=$MaxFrames"
}
if ($Speed -gt 0.0) {
    $userArgs += "--speed=$Speed"
}
if ($Immortal -ne "") {
    $userArgs += "--immortal=$Immortal"
}
if ($Out -ne "") {
    $resolvedOut = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $repoRoot $Out }
    $outParent = Split-Path $resolvedOut -Parent
    if ($outParent -and -Not (Test-Path $outParent)) {
        New-Item -ItemType Directory -Path $outParent -Force | Out-Null
    }
    $userArgs += "--out=$resolvedOut"
}
if ($FullCombat) {
    $userArgs += "--full_combat=true"
}

$godotArgs = @()
if ($Mode -ne "watch") {
    if (-Not $Gpu) {
        $godotArgs += "--headless"
    }
    $godotArgs += "--audio-driver"
    $godotArgs += "Dummy"
    $godotArgs += "--fixed-fps"
    $godotArgs += "60"
}
$godotArgs += "--path"
$godotArgs += "src"
$godotArgs += "res://autoplay/autoplay_runner.tscn"
$godotArgs += "--"
$godotArgs += $userArgs

$effectiveJobs = if ($Jobs -gt 0) {
    $Jobs
} elseif ($Mode -eq "matrix" -and -Not $Gpu) {
    [Math]::Min(8, [Environment]::ProcessorCount)
} else {
    1
}

Push-Location $repoRoot
try {
    $classCache = Join-Path $repoRoot "src\.godot\global_script_class_cache.cfg"
    if (-Not (Test-Path $classCache) -or -Not (Select-String -Path $classCache -Pattern "AutoplayRunner" -Quiet)) {
        Write-Host "Refreshing Godot script class cache..." -ForegroundColor Yellow
        & godot --headless --path src --audio-driver Dummy --import | Out-Null
    }
    if ($effectiveJobs -gt 1 -and ($Mode -eq "balance" -or $Mode -eq "matrix") -and -Not $Gpu) {
        $python = Join-Path $repoRoot ".venv\Scripts\python.exe"
        if (-Not (Test-Path $python)) {
            $python = "python"
        }
        $godotBin = (Get-Command godot).Source
        $parallelScript = Join-Path $PSScriptRoot "autoplay_parallel.py"
        $pyArgs = @(
            $parallelScript,
            "--mode", $Mode,
            "--matrix-set", $MatrixSet,
            "--leader", $Leader,
            "--build", $Build,
            "--seeds", $effectiveSeeds,
            "--seed", $effectiveSeed,
            "--max-depth", $MaxDepth,
            "--jobs", $effectiveJobs,
            "--godot-bin", $godotBin
        )
        if ($MaxFrames -ge 0) {
            $pyArgs += @("--max-frames", $MaxFrames)
        }
        if ($Speed -gt 0.0) {
            $pyArgs += @("--speed", $Speed)
        }
        if ($Immortal -ne "") {
            $pyArgs += @("--immortal", $Immortal)
        }
        if ($Out -ne "") {
            $resolvedOut = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $repoRoot $Out }
            $pyArgs += @("--out", $resolvedOut)
        }
        Write-Host "Running Autoplay Parallel [$Mode/$MatrixSet] (jobs=$effectiveJobs seeds=$effectiveSeeds seed=$effectiveSeed)..." -ForegroundColor Cyan
        & $python @pyArgs
        exit $LASTEXITCODE
    }
    if ($Mode -eq "audit") {
        Write-Host "Running Autoplay [audit] (seeds=$effectiveSeeds seed=$effectiveSeed max_depth=$MaxDepth)..." -ForegroundColor Cyan
    } else {
        Write-Host "Running Autoplay [$Mode] (leader=$Leader build=$Build seeds=$effectiveSeeds seed=$effectiveSeed)..." -ForegroundColor Cyan
    }
    & godot @godotArgs
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
