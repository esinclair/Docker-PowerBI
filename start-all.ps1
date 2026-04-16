# =============================================================================
# start-all.ps1
# Two-phase Docker startup:
#   Phase 1 — Linux engine  : OracleDB
#   Phase 2 — Windows engine: Power BI Report Server + MSSQL (Windows container)
# =============================================================================

$ErrorActionPreference = 'Stop'
$DockerCli = 'C:\Program Files\Docker\Docker\DockerCli.exe'
$ComposeFile = Join-Path $PSScriptRoot 'docker-compose.yml'

function Wait-DockerReady {
    param([string]$Label, [int]$TimeoutSeconds = 120)
    Write-Host "Waiting for Docker ($Label) to be ready..." -ForegroundColor Cyan
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $info = docker info 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Docker ($Label) is ready." -ForegroundColor Green
            return
        }
        Start-Sleep -Seconds 3
    }
    throw "Docker did not become ready within $TimeoutSeconds seconds ($Label)."
}

function Switch-DockerEngine {
    param(
        [ValidateSet('Linux','Windows')]
        [string]$Engine,
        [int]$TimeoutSeconds = 120
    )

    Write-Host "`nSwitching Docker to $Engine engine..." -ForegroundColor Yellow

    $flag = if ($Engine -eq 'Linux') { '-SwitchLinuxEngine' } else { '-SwitchWindowsEngine' }

    # Check if already on the desired engine to avoid an unnecessary restart
    $osType = (docker info --format '{{.OSType}}' 2>$null)
    if ($Engine -eq 'Linux'   -and $osType -eq 'linux')   { Write-Host "Already on Linux engine."   -ForegroundColor DarkGray; return }
    if ($Engine -eq 'Windows' -and $osType -eq 'windows') { Write-Host "Already on Windows engine." -ForegroundColor DarkGray; return }

    & $DockerCli $flag
    # Docker Desktop restarts the engine; give it a moment before polling
    Start-Sleep -Seconds 5
    Wait-DockerReady -Label $Engine -TimeoutSeconds $TimeoutSeconds
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase 1 — Linux engine: OracleDB
# ─────────────────────────────────────────────────────────────────────────────
Switch-DockerEngine -Engine Linux

Write-Host "`n[Phase 1] Starting OracleDB (Linux container)..." -ForegroundColor Cyan
docker compose --file $ComposeFile up -d oracledb
if ($LASTEXITCODE -ne 0) { throw "Failed to start oracledb." }
Write-Host "OracleDB started." -ForegroundColor Green

# ─────────────────────────────────────────────────────────────────────────────
# Phase 2 — Windows engine: Power BI Report Server + MSSQL (Windows container)
# ─────────────────────────────────────────────────────────────────────────────
Switch-DockerEngine -Engine Windows

Write-Host "`n[Phase 2] Starting PBIRS + MSSQL Windows containers..." -ForegroundColor Cyan
docker compose --file $ComposeFile up -d pbirs mssqldb-win
if ($LASTEXITCODE -ne 0) { throw "Failed to start pbirs / mssqldb-win." }
Write-Host "PBIRS and MSSQL-Win started." -ForegroundColor Green

Write-Host "`nAll services are up." -ForegroundColor Green
Write-Host "  OracleDB  : localhost:1521  (Linux engine)"
Write-Host "  PBIRS     : http://localhost/reports  (Windows engine)"
Write-Host "  MSSQL-Win : localhost,1435  (Windows engine)"
