#!/bin/bash
# 02_grants.sh — Grant SYSTEM-level privileges to the companydata app user.
# Executed by the gvenzl/oracle-free entrypoint (alphabetically after 01_init.sql).
#
# Why a separate shell script?
#   SQL files in /docker-entrypoint-initdb.d/ run as APP_USER (companydata).
#   An owner cannot grant its own object privileges to itself in Oracle, and
#   system-level grants (roles, dictionary access) require a DBA connection.
#   This script connects as SYSTEM to apply those grants.
set -e

echo ">> [02_grants] Granting SYSTEM-level privileges to ${APP_USER:-companydata}..."

sqlplus -S "SYSTEM/${ORACLE_PASSWORD}@//localhost/FREEPDB1" << SQL
-- SELECT_CATALOG_ROLE grants read access to all DBA_* data-dictionary views.
-- This enables:
--   * DESCRIBE on any object in any schema
--   * Power BI / Oracle connector schema discovery (DBA_TABLES, DBA_TAB_COLUMNS)
--   * Querying ALL_* and DBA_* views for metadata
GRANT SELECT_CATALOG_ROLE TO ${APP_USER:-companydata};
EXIT;
SQL

echo ">> [02_grants] Done."
