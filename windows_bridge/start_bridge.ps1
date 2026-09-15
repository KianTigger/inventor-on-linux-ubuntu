$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $Root "logs"
$PidFile = Join-Path $Root "bridge.pid"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

if (Test-Path $PidFile) {
    $oldPid = Get-Content $PidFile -ErrorAction SilentlyContinue
    if ($oldPid -and (Get-Process -Id $oldPid -ErrorAction SilentlyContinue)) {
        Write-Host "Inventor VM Bridge already running as PID $oldPid."
        exit 0
    }
    Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
}

$Python = Join-Path $Root ".venv\Scripts\python.exe"
if (-not (Test-Path $Python)) {
    throw "Bridge virtual environment is missing. Run install.ps1 first."
}

$proc = Start-Process -FilePath $Python `
    -ArgumentList "run_bridge.py" `
    -WorkingDirectory $Root `
    -RedirectStandardOutput (Join-Path $LogDir "bridge.out.log") `
    -RedirectStandardError (Join-Path $LogDir "bridge.err.log") `
    -WindowStyle Hidden `
    -PassThru

Set-Content -Path $PidFile -Value $proc.Id -Encoding ASCII
Write-Host "Inventor VM Bridge started as PID $($proc.Id)."
