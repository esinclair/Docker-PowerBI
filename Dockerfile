FROM mcr.microsoft.com/windows/servercore:ltsc2019
LABEL Name=PowerBI Version=0.1.15 maintainer="John Hall"
# Download Link:
ENV SQL "https://go.microsoft.com/fwlink/?linkid=866662"
ENV sa_password="_" \
    attach_dbs="[]" \
    ACCEPT_EULA="_" \
    sa_password_path="C:\ProgramData\Docker\secrets\sa-password" \
    pbirs_user="_" \
    pbirs_password="_" \
    pbirs_edition="EVAL" \
    pbirs_password_path="C:\ProgramData\Docker\secrets\pbirs-password"

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

WORKDIR /

# Copy scripts that rarely change first for layer caching
COPY sqlinstall.ps1 sqlstart.ps1 pbiinstall.ps1 configurePBIRS.ps1 start.ps1 newadmin.ps1 /

# Install SQL Server 2019
RUN .\sqlinstall
# Install PowerBI Report Server
RUN .\pbiinstall

# ── Custom cookie-based authentication extension ──────────────────────────────
# Copy extension installer and source (changes here won't invalidate SQL/PBI layers)
COPY installextension.ps1 /
COPY CustomAuthExtension/ /CustomAuthExtension/

# Install the .NET SDK (script-based, no MSI required) so we can run dotnet build
RUN [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; \
    Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' \
        -OutFile C:\dotnet-install.ps1; \
    & C:\dotnet-install.ps1 -Channel 8.0 -InstallDir C:\dotnet -NoPath; \
    $env:PATH = 'C:\dotnet;' + $env:PATH; \
    Set-Location C:\CustomAuthExtension; \
    C:\dotnet\dotnet.exe build CustomAuthExtension.csproj -c Release; \
    & C:\installextension.ps1; \
    Remove-Item -Recurse -Force C:\CustomAuthExtension\obj, \
        C:\CustomAuthExtension\bin, \
        C:\dotnet-install.ps1; \
    # hostfxr.dll may still be locked by the runtime; cleanup is best-effort
    try { Remove-Item -Recurse -Force C:\dotnet } catch {}; exit 0

# Forms auth returns 302/401 without a cookie, so just verify the port is listening.
HEALTHCHECK --interval=15s --start-period=120s \
 CMD powershell -command "try { $c = New-Object Net.Sockets.TcpClient('localhost',80); $c.Close(); exit 0 } catch { exit 1 }"

CMD .\start -sa_password $env:sa_password -ACCEPT_EULA $env:ACCEPT_EULA -attach_dbs \"$env:attach_dbs\" -pbirs_user $env:pbirs_user -pbirs_password $env:pbirs_password -Verbose
