# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$ExtraArgs
)

$repoRoot = Split-Path $PSScriptRoot -Parent
$python = Join-Path $repoRoot ".venv\Scripts\python.exe"
if (-Not (Test-Path $python)) {
    $python = "python"
}

Push-Location $repoRoot
try {
    & $python "scripts\build_sounds.py" @ExtraArgs
} finally {
    Pop-Location
}
