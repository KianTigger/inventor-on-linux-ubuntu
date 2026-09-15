$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnvFile = Join-Path $Root ".env"
if (-not (Test-Path $EnvFile)) { throw "Missing $EnvFile" }

$values = @{}
Get-Content $EnvFile | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]*)=(.*)$') {
        $values[$matches[1].Trim()] = $matches[2].Trim()
    }
}
$port = if ($values['INVENTOR_BRIDGE_PORT']) { $values['INVENTOR_BRIDGE_PORT'] } else { '8765' }
$token = $values['INVENTOR_BRIDGE_TOKEN']
if (-not $token) { throw "INVENTOR_BRIDGE_TOKEN is missing from .env" }

$health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 10
Write-Host "Bridge health: $($health.status)"
$status = Invoke-RestMethod -Uri "http://127.0.0.1:$port/v1/status" -Headers @{ 'X-Inventor-Bridge-Token' = $token } -TimeoutSec 60
$status | ConvertTo-Json -Depth 4
