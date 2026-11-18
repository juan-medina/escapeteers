# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

param(
    [ValidateSet("perf", "balance", "matrix", "watch")]
    [string]$Mode = "perf",
    [string]$Build = "balanced",
    [string]$Leader = "knight",
    [int]$Seeds = 0,
    [int]$Seed = 0,
    [int]$MaxDepth = 12,
    [int]$MaxFrames = -1,
    [double]$Speed = 0.0,
    [string]$Immortal = "",
    [string]$Out = "",
    [switch]$Gpu
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

if ($MaxFrames -ge 0) {
    $userArgs += "--max_frames=$MaxFrames"
} elseif ($Gpu) {
    $userArgs += "--max_frames=3600"
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

Push-Location $repoRoot
try {
    $classCache = Join-Path $repoRoot "src\.godot\global_script_class_cache.cfg"
    if (-Not (Test-Path $classCache) -or -Not (Select-String -Path $classCache -Pattern "AutoplayRunner" -Quiet)) {
        Write-Host "Refreshing Godot script class cache..." -ForegroundColor Yellow
        & godot --headless --path src --audio-driver Dummy --import | Out-Null
    }
    Write-Host "Running Autoplay [$Mode] (leader=$Leader build=$Build seeds=$effectiveSeeds seed=$effectiveSeed)..." -ForegroundColor Cyan
    & godot @godotArgs
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
