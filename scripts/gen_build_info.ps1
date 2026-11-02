# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$ExtraArgs
)

if (-Not (Test-Path "scripts\gen_build_info.py")) {
    Write-Host "Error: scripts\gen_build_info.py not found!" -ForegroundColor Red
    exit 1
}

python scripts\gen_build_info.py @ExtraArgs
