param(
    [switch]$NoFirewall,
    [switch]$NoScheduledTask
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host "Run this script once from an Administrator PowerShell window." -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    $bytes = New-Object byte[] 36
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $token = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
    (Get-Content ".env") -replace '^INVENTOR_BRIDGE_TOKEN=.*$', "INVENTOR_BRIDGE_TOKEN=$token" | Set-Content ".env" -Encoding UTF8
    Write-Host "Generated windows_bridge\.env with a new API token. Copy that token to the Linux/Rishika configuration." -ForegroundColor Yellow
}

if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
    throw "Python launcher 'py' was not found. Install Python 3.11+ x64 for the current Windows user."
}

if (-not (Test-Path ".venv\Scripts\python.exe")) {
    py -3 -m venv .venv
}

& ".venv\Scripts\python.exe" -m pip install --upgrade pip
& ".venv\Scripts\python.exe" -m pip install -r requirements.txt

$PortLine = Get-Content ".env" | Where-Object { $_ -match '^INVENTOR_BRIDGE_PORT=' } | Select-Object -First 1
$Port = if ($PortLine) { [int]($PortLine -split '=',2)[1] } else { 8765 }

if (-not $NoFirewall) {
    $ruleName = "Inventor VM Bridge TCP $Port"
    Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port | Out-Null
    Write-Host "Windows Firewall rule installed for TCP $Port."
}

if (-not $NoScheduledTask) {
    $taskName = "Inventor VM Bridge"
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$Root\start_bridge.ps1`""
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    Write-Host "Scheduled task '$taskName' installed for the current interactive Windows user."
}

& "$Root\start_bridge.ps1"
Start-Sleep -Seconds 2
& "$Root\test_bridge.ps1"

Write-Host ""
Write-Host "Installation complete." -ForegroundColor Green
Write-Host "Keep this Windows user logged in. Inventor may be minimized/locked, but do not run the bridge as Session 0 service."
