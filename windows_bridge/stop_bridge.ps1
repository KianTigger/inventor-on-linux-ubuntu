$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$PidFile = Join-Path $Root "bridge.pid"
if (-not (Test-Path $PidFile)) {
    Write-Host "No bridge.pid file exists."
    exit 0
}
$pidValue = Get-Content $PidFile -ErrorAction SilentlyContinue
if ($pidValue) {
    Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
}
Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
Write-Host "Inventor VM Bridge stopped. Inventor itself is left running by default."
