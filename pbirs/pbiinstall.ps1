# Get latest PowerBI Report Server (January 2026, build 15.0.1120.122)
$ENV:PowerBI  = "https://aka.ms/pbireportserverexe"
# Install PowerBI
new-item -Path C:\ -Name PBIRS_TEMP -ItemType Directory

$localPBI = 'C:\installers\PowerBIReportServer.exe'
if (Test-Path $localPBI) {
    Write-Host "Using cached PBIRS installer: $localPBI"
    Copy-Item $localPBI 'c:\PBIRS_TEMP\PowerBIReportServer.exe'
} else {
    Write-Host "Downloading PBIRS installer..."
    (New-Object System.Net.WebClient).DownloadFile($ENV:PowerBI, "c:\PBIRS_TEMP\PowerBIReportServer.exe")
}
Start-Process -Wait -FilePath c:\PBIRS_TEMP\PowerBIReportServer.exe -ArgumentList /quiet, /norestart, /IAcceptLicenseTerms, /Edition=$ENV:pbirs_edition
# perform clean up
Remove-Item -Recurse -Force PBIRS_TEMP, 'C:\Users\ContainerAdministrator\AppData\Local\Temp'
