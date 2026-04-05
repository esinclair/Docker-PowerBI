#!/bin/bash
# entrypoint.sh — starts SQL Server then runs the one-time init script.
# SA_PASSWORD and MSSQL_APP_PASSWORD are read from environment variables.
set -e

# Locate sqlcmd — path differs between mssql-tools and mssql-tools18
if [ -x "/opt/mssql-tools18/bin/sqlcmd" ]; then
    SQLCMD="/opt/mssql-tools18/bin/sqlcmd -C"   # -C = trust self-signed cert
elif [ -x "/opt/mssql-tools/bin/sqlcmd" ]; then
    SQLCMD="/opt/mssql-tools/bin/sqlcmd"
else
    echo "ERROR: sqlcmd not found." >&2
    exit 1
fi

# Start SQL Server in the background
echo "Starting SQL Server..."
/opt/mssql/bin/sqlservr &
SQL_PID=$!

# Wait for SQL Server to accept connections (up to 120 s)
echo "Waiting for SQL Server to be ready..."
RETRIES=0
until $SQLCMD -S localhost -U SA -P "$SA_PASSWORD" -Q "SELECT 1" > /dev/null 2>&1; do
    RETRIES=$((RETRIES + 1))
    if [ $RETRIES -ge 60 ]; then
        echo "ERROR: SQL Server did not become ready within 120 seconds." >&2
        exit 1
    fi
    echo "  Attempt $RETRIES/60 — retrying in 2 s..."
    sleep 2
done

echo "SQL Server is ready. Creating database and application user..."

# Create the CompanyData database if it does not already exist
$SQLCMD -S localhost -U SA -P "$SA_PASSWORD" -Q \
    "IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = N'CompanyData') CREATE DATABASE CompanyData;"

# Create the companydata login if it does not already exist
$SQLCMD -S localhost -U SA -P "$SA_PASSWORD" -Q \
    "IF NOT EXISTS (SELECT name FROM sys.server_principals WHERE name = N'companydata') CREATE LOGIN [companydata] WITH PASSWORD = N'${MSSQL_APP_PASSWORD}';"

# Create the DB-level user and add to db_datareader role
$SQLCMD -S localhost -U SA -P "$SA_PASSWORD" -d CompanyData -Q \
    "IF NOT EXISTS (SELECT name FROM sys.database_principals WHERE name = N'companydata')
     BEGIN
         CREATE USER [companydata] FOR LOGIN [companydata];
         ALTER ROLE db_datareader ADD MEMBER [companydata];
     END"

echo "Running schema and data initialization..."
$SQLCMD -S localhost -U SA -P "$SA_PASSWORD" -d CompanyData -i /usr/src/app/init.sql
echo "Initialization complete."

# Hand off to the SQL Server process so the container stays alive
wait $SQL_PID
