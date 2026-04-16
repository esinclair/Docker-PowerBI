# Microsoft SQL Server 2022 on Linux (official Microsoft image — no registry login required)
# Entrypoint starts SQL Server, waits for readiness, creates the CompanyData
# database + app login, then runs init.sql to build the schema and load data.
FROM mcr.microsoft.com/mssql/server:2022-latest

USER root

COPY entrypoint.sh /usr/src/app/entrypoint.sh
COPY init.sql      /usr/src/app/init.sql

RUN sed -i 's/\r$//' /usr/src/app/entrypoint.sh && \
    chmod +x /usr/src/app/entrypoint.sh

# mssql is the default non-root user provided by this base image
USER mssql

ENV ACCEPT_EULA=Y

ENTRYPOINT ["/usr/src/app/entrypoint.sh"]
