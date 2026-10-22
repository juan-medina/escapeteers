$repoRoot = Split-Path $PSScriptRoot -Parent
$venvPath = Join-Path $repoRoot ".venv"
$python = Join-Path $venvPath "Scripts\python.exe"
$requirements = Join-Path $PSScriptRoot "requirements.txt"

Write-Host "Setting up Python virtual environment..."

if (-Not (Test-Path $venvPath)) {
    Write-Host "Creating .venv directory..."
    Push-Location $repoRoot
    try {
        python -m venv .venv
    } finally {
        Pop-Location
    }
} else {
    Write-Host ".venv already exists."
}

if (Test-Path $requirements) {
    Write-Host "Installing dependencies from $requirements..."
    & $python -m pip install -U pip
    & $python -m pip install -r $requirements
}

Write-Host "Environment setup complete!" -ForegroundColor Green
