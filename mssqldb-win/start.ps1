<#
.SYNOPSIS
    Starts SQL Server, initialises the CompanyData database on first run,
    then keeps the container alive by tailing the SQL Server event log.

.DESCRIPTION
    Windows equivalent of the Linux entrypoint.sh found in mssqldb/.
    Reads SA_PASSWORD and MSSQL_APP_PASSWORD from environment variables
    (injected by docker-compose via the .env file).
#>

$SA_PASSWORD       = $env:SA_PASSWORD
$APP_PASSWORD      = $env:MSSQL_APP_PASSWORD
$ACCEPT_EULA       = $env:ACCEPT_EULA
$INIT_SQL          = 'C:\init.sql'

if ($ACCEPT_EULA -ne 'Y' -and $ACCEPT_EULA -ne 'y') {
    Write-Error 'ERROR: You must accept the EULA. Set ACCEPT_EULA=Y.'
    exit 1
}

# ---------------------------------------------------------------------------
# Start SQL Server service
# ---------------------------------------------------------------------------
Write-Host 'Starting SQL Server...'
Start-Service MSSQLSERVER

# ---------------------------------------------------------------------------
# Wait until SQL Server accepts connections using Windows auth (up to 120 s)
# sqlinstall.ps1 adds BUILTIN\Administrators as sysadmin, so -E always works.
# We wait here BEFORE touching SA so SQL Server is ready to accept commands.
# ---------------------------------------------------------------------------
Write-Host 'Waiting for SQL Server to be ready...'
$retries = 0
do {
    Start-Sleep -Seconds 2
    $retries++
    & sqlcmd -S localhost -E -Q 'SELECT 1' 2>&1 | Out-Null
    if ($retries -ge 60) {
        Write-Error 'ERROR: SQL Server did not become ready within 120 seconds.'
        exit 1
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  Attempt $retries/60 — retrying..."
    }
} until ($LASTEXITCODE -eq 0)

Write-Host 'SQL Server is ready.'

# ---------------------------------------------------------------------------
# Enable mixed-mode auth and configure SA (idempotent)
# ---------------------------------------------------------------------------
Write-Host 'Configuring SA login...'
& sqlcmd -S localhost -E -Q "
    -- Enable SQL Server + Windows authentication mode
    EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE',
        N'Software\Microsoft\MSSQLServer\MSSQLServer',
        N'LoginMode', REG_DWORD, 2;
    -- Enable and set SA password
    ALTER LOGIN sa WITH PASSWORD=N'$SA_PASSWORD', CHECK_POLICY=OFF, CHECK_EXPIRATION=OFF;
    ALTER LOGIN sa ENABLE;
"
# Restart so the LoginMode registry change takes effect
Write-Host 'Restarting SQL Server to apply mixed-mode auth...'
Restart-Service MSSQLSERVER
Start-Sleep -Seconds 5

# Brief re-wait after restart
$retries = 0
do {
    Start-Sleep -Seconds 2
    $retries++
    & sqlcmd -S localhost -U SA -P $SA_PASSWORD -Q 'SELECT 1' 2>&1 | Out-Null
    if ($retries -ge 30) {
        Write-Error 'ERROR: SQL Server did not restart within 60 seconds.'
        exit 1
    }
} until ($LASTEXITCODE -eq 0)
Write-Host 'SQL Server ready with mixed-mode auth.'

# ---------------------------------------------------------------------------
# First-run initialisation (skipped if CompanyData already has tables)
# ---------------------------------------------------------------------------
$tableCount = ( & sqlcmd -S localhost -U SA -P $SA_PASSWORD -h -1 -W `
    -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.databases WHERE name = N'CompanyData'" `
    2>&1 | Out-String ).Trim()

if ($tableCount -eq '0') {
    Write-Host 'Creating CompanyData database...'
    & sqlcmd -S localhost -U SA -P $SA_PASSWORD -Q `
        "CREATE DATABASE CompanyData;"
}

# Create application login if it does not exist
& sqlcmd -S localhost -U SA -P $SA_PASSWORD -Q `
    "IF NOT EXISTS (SELECT name FROM sys.server_principals WHERE name = N'companydata')
         CREATE LOGIN [companydata] WITH PASSWORD = N'$APP_PASSWORD',
         CHECK_POLICY = OFF, CHECK_EXPIRATION = OFF;"

# Create DB-level user and grant read access
& sqlcmd -S localhost -U SA -P $SA_PASSWORD -d CompanyData -Q `
    "IF NOT EXISTS (SELECT name FROM sys.database_principals WHERE name = N'companydata')
     BEGIN
         CREATE USER [companydata] FOR LOGIN [companydata];
         ALTER ROLE db_datareader ADD MEMBER [companydata];
     END"

# Run schema + data script only once (guard: Companies table must not exist)
$schemaExists = ( & sqlcmd -S localhost -U SA -P $SA_PASSWORD -d CompanyData -h -1 -W `
    -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.tables WHERE name = N'Companies'" `
    2>&1 | Out-String ).Trim()

if ($schemaExists -eq '0') {
    Write-Host 'Running schema and data initialisation...'
    & sqlcmd -S localhost -U SA -P $SA_PASSWORD -d CompanyData -i $INIT_SQL
    Write-Host 'Initialisation complete.'
} else {
    Write-Host 'Schema already present — skipping init.sql.'
}

# ---------------------------------------------------------------------------
# Keep the container alive — tail SQL Server application events
# ---------------------------------------------------------------------------
Write-Host 'Container ready. Tailing SQL Server events...'
$lastCheck = (Get-Date).AddSeconds(-2)
while ($true) {
    Get-EventLog -LogName Application -Source 'MSSQL*' -After $lastCheck `
        -ErrorAction SilentlyContinue |
        Select-Object TimeGenerated, EntryType, Message
    $lastCheck = Get-Date
    Start-Sleep -Seconds 5
}
