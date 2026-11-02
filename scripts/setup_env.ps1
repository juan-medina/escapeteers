Write-Host "Setting up Python virtual environment..."

if (-Not (Test-Path ".\.venv")) {
    Write-Host "Creating .venv directory..."
    python -m venv .venv
} else {
    Write-Host ".venv already exists."
}

Write-Host "Installing dependencies from requirements.txt..."
& .\.venv\Scripts\python.exe -m pip install -U pip
& .\.venv\Scripts\python.exe -m pip install -r requirements.txt

Write-Host "Environment setup complete!" -ForegroundColor Green
