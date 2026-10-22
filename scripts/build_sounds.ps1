param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$ArgsToPass
)

$repoRoot = Split-Path $PSScriptRoot -Parent
$python = Join-Path $repoRoot ".venv\Scripts\python.exe"

if (-Not (Test-Path $python)) {
    $python = "python"
}

Write-Host "Running build_sounds.py..."
Push-Location $repoRoot
try {
    & $python "scripts\build_sounds.py" @ArgsToPass
} finally {
    Pop-Location
}
