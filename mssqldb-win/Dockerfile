# Microsoft SQL Server 2019 (Windows Server Core) — standalone data container
#
# Build context must be the repo root (context: .) so both sqlinstall.ps1
# and mssqldb/init.sql are reachable.
#
# This image installs only SQL Server — no Power BI Report Server —
# so it is small enough to run alongside pbirs in Windows container mode
# on the same Docker NAT network, enabling direct name-based connections:
#
#   Server=mssqldb-win,1433;Database=CompanyData;User Id=companydata;Password=<pw>;
#
# Host-side port 1435 is exposed for DBA / VSCode tooling.

FROM mcr.microsoft.com/windows/servercore:ltsc2019
LABEL Name=mssqldb-win Version=0.1.0 maintainer="John Hall"

ENV SQL="https://go.microsoft.com/fwlink/?linkid=866662" \
    SA_PASSWORD="_" \
    MSSQL_APP_PASSWORD="_" \
    ACCEPT_EULA="_"

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# Install SQL Server 2019 (reuses the same script that pbirs uses)
COPY sqlinstall.ps1 /
RUN .\sqlinstall

# Copy initialisation artefacts
COPY mssqldb-win/start.ps1 /
COPY mssqldb/init.sql      /

HEALTHCHECK --interval=10s --timeout=5s --start-period=180s --retries=15 \
  CMD powershell -command \
    "try { & sqlcmd -S localhost -E -Q 'SELECT 1' -l 2 | Out-Null; return 0 } catch { return 1 }"

CMD .\start
