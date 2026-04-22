# Microsoft SQL Server 2022 (Windows Server Core) — standalone data container
#
# Build context must be the repo root (context: .) so both pbirs/sqlinstall.ps1
# and mssqldb/init.sql are reachable.
#
# This image installs only SQL Server — no Power BI Report Server —
# so it is small enough to run alongside pbirs in Windows container mode
# on the same Docker NAT network, enabling direct name-based connections:
#
#   Server=mssqldb-win,1433;Database=CompanyData;User Id=companydata;Password=<pw>;
#
# Host-side port 1435 is exposed for DBA / VSCode tooling.

FROM mcr.microsoft.com/windows/servercore:ltsc2022
LABEL Name=mssqldb-win Version=0.1.1 maintainer="John Hall"

ENV SQL="https://download.microsoft.com/download/c/c/9/cc9c6797-383c-4b24-8920-dc057c1de9d3/SQL2022-SSEI-Dev.exe" \
    SA_PASSWORD="_" \
    MSSQL_APP_PASSWORD="_" \
    ACCEPT_EULA="_"

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# Install SQL Server 2022 (reuses the same script that pbirs uses)
COPY pbirs/sqlinstall.ps1 /
RUN .\sqlinstall

# Copy initialisation artefacts
COPY mssqldb-win/start.ps1 /
COPY mssqldb/init.sql      /

HEALTHCHECK --interval=10s --timeout=5s --start-period=180s --retries=15 \
  CMD powershell -command \
    "try { & sqlcmd -S localhost -E -Q 'SELECT 1' -l 2 | Out-Null; return 0 } catch { return 1 }"

CMD .\start
