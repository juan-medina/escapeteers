# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

param(
    [Parameter(Mandatory=$true, Position=0, ValueFromRemainingArguments=$true)]
    [string[]]$Files
)

$repoRoot = Split-Path $PSScriptRoot -Parent
$python = Join-Path $repoRoot ".venv\Scripts\python.exe"
if (-Not (Test-Path $python)) {
    $python = "python"
}

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

Push-Location $repoRoot
try {
    foreach ($file in $Files) {
        Write-Host "Verifying $file..." -ForegroundColor Cyan

        # 1. Format
        & $python -m gdtoolkit.formatter -l 150 $file
        if ($LASTEXITCODE -ne 0) {
            Write-Error "gdformat failed on $file"
            exit $LASTEXITCODE
        }

        $fullPath = (Resolve-Path $file).Path
        $content = [System.IO.File]::ReadAllText($fullPath)
        if ($content.Contains("`r`n")) {
            [System.IO.File]::WriteAllText($fullPath, $content.Replace("`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))
        }

        # 2. Lint
        & $python -m gdtoolkit.linter $file
        if ($LASTEXITCODE -ne 0) {
            Write-Error "gdlint failed on $file"
            exit $LASTEXITCODE
        }
    }

    # 3. Godot class cache refresh + check-only (run once for the project)
    Write-Host "Refreshing Godot class cache..." -ForegroundColor Cyan
    "quit" | godot --headless --path src --audio-driver Dummy --import --quit
    if ($LASTEXITCODE -ne 0) {
        Write-Error "godot --import failed"
        exit $LASTEXITCODE
    }

    Write-Host "Running Godot compiler check..." -ForegroundColor Cyan
    $checkOutput = "quit" | godot --headless --path src --audio-driver Dummy --check-only -d --quit 2>&1
    $checkExit = $LASTEXITCODE
    foreach ($line in $checkOutput) {
        Write-Host $line
    }
    $checkText = ($checkOutput | Out-String)
    if ($checkExit -ne 0 -or $checkText -match "Debugger Break|Parser Error|SCRIPT ERROR:") {
        Write-Error "godot check-only failed"
        if ($checkExit -ne 0) {
            exit $checkExit
        }
        exit 1
    }

    Write-Host "All files verified successfully!" -ForegroundColor Green
} finally {
    Pop-Location
}

