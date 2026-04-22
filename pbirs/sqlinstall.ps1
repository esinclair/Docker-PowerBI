$ErrorActionPreference = 'Stop'
function Write-Log { param([string]$Msg) Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Msg" }

# --- Network connectivity check ---
Write-Log "ENV:SQL = $ENV:SQL"
Write-Log "Checking DNS resolution for go.microsoft.com..."
try { $dns = [Net.Dns]::GetHostAddresses("go.microsoft.com"); Write-Log "DNS OK: $($dns.IPAddressToString -join ', ')" }
catch { Write-Log "DNS FAILED: $_" }

Write-Log "Testing TCP 443 to go.microsoft.com..."
try { $tc = New-Object Net.Sockets.TcpClient; $tc.Connect("go.microsoft.com", 443); $tc.Close(); Write-Log "TCP 443 OK" }
catch { Write-Log "TCP 443 FAILED: $_" }

Write-Log "Resolving redirect for bootstrapper URL..."
try {
    $req = [Net.HttpWebRequest]::Create($ENV:SQL)
    $req.AllowAutoRedirect = $false
    $req.Timeout = 15000
    $req.Method = "HEAD"
    $resp = $req.GetResponse()
    Write-Log "Redirect -> $($resp.Headers['Location'])"
    $resp.Close()
} catch [Net.WebException] {
    if ($_.Exception.Response) {
        Write-Log "Redirect (from exception) -> $($_.Exception.Response.Headers['Location'])"
    } else {
        Write-Log "Redirect check FAILED: $_"
    }
}

# --- SQL Server bootstrapper (use local copy if available) ---
$localBootstrapper = 'C:\installers\SQL2022-SSEI-Dev.exe'
if (Test-Path $localBootstrapper) {
    Write-Log "Using cached bootstrapper: $localBootstrapper"
    Copy-Item $localBootstrapper 'c:\SQL.exe'
} else {
    Write-Log "Downloading SQL Server bootstrapper from: $ENV:SQL"
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($ENV:SQL, "c:\SQL.exe")
        Write-Log "Bootstrapper download complete. Size: $((Get-Item c:\SQL.exe).Length) bytes"
    } catch {
        Write-Log "Bootstrapper download FAILED: $_"
        throw
    }
}

Write-Log "Extracting SQL media..."
Start-Process -Wait -FilePath .\SQL.exe -ArgumentList /Q, /MT:CAB, /ACTION:Download, /Mediapath:c:\setup
Write-Log "Media extraction complete. Contents of c:\setup:"
Get-ChildItem c:\setup | ForEach-Object { Write-Log "  $($_.Name)" }

Write-Log "Running SQL Server media installer..."
Start-Process -Wait -FilePath c:\setup\SQLServer2022-DEV-x64-ENU.exe -ArgumentList /Q
Write-Log "Media installer complete."

# --- Installing SQL Server RTM ---
Write-Log "Installing SQL Server RTM..."
$configContent = @"
[OPTIONS]
ACTION="Install"
FEATURES=SQLEngine
INSTANCENAME="MSSQLSERVER"
QUIET="True"
UPDATEENABLED="False"
SQLSVCACCOUNT="NT AUTHORITY\NETWORK SERVICE"
SQLSYSADMINACCOUNTS="BUILTIN\ADMINISTRATORS"
TCPENABLED="1"
NPENABLED="0"
IACCEPTSQLSERVERLICENSETERMS="True"
"@
$configPath = 'C:\setup_config.ini'
$configContent | Out-File -FilePath $configPath -Encoding ASCII
Write-Log "Config file contents:"
Get-Content $configPath | ForEach-Object { Write-Log "  $_" }
$proc = Start-Process -Wait -PassThru -FilePath 'C:\SQLServer2022-DEV-x64-ENU\setup.exe' -ArgumentList "/ConfigurationFile=$configPath"
Write-Log "SQL Server RTM installation complete. Exit code: $($proc.ExitCode)"
if ($proc.ExitCode -ne 0) {
    $summaryPath = Get-ChildItem 'C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\Log' -Recurse -Filter 'Summary.txt' | Select-Object -First 1
    if ($summaryPath) { Get-Content $summaryPath.FullName | Write-Host }
    throw "SQL Server RTM setup failed with exit code $($proc.ExitCode)"
}

# --- Clean up ---
Write-Log "Cleaning up..."
Remove-Item -Recurse -Force SQL.exe, Setup, SQLServer2022-DEV-x64-ENU, setup_config.ini, 'C:\Program Files\Microsoft SQL Server\160\Setup Bootstrap\Update Cache', 'C:\Users\ContainerAdministrator\AppData\Local\Temp' -ErrorAction SilentlyContinue
Write-Log "Done."