# Oracle Database 23c Free (community image — no registry login required)
# Init scripts in /docker-entrypoint-initdb.d/ are run automatically by the
# entrypoint when the database is first created.  SQL files execute as APP_USER
# connected to FREEPDB1.  Shell scripts execute as the oracle OS user and have
# access to $ORACLE_PASSWORD / $APP_USER / $APP_USER_PASSWORD.
FROM gvenzl/oracle-free:latest

# 01_init.sql  — creates schema objects and loads data (runs as APP_USER)
# 02_grants.sh — grants SYSTEM-level privileges to APP_USER (runs as oracle OS user)
COPY init.sql      /docker-entrypoint-initdb.d/01_init.sql
COPY 02_grants.sh  /docker-entrypoint-initdb.d/02_grants.sh
