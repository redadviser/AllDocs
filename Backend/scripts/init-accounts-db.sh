#!/bin/bash
# The official postgres image only auto-creates the database named in
# $POSTGRES_DB (alldocs). This creates the second, local-only stand-in for
# the shared accounts database and loads its schema, so a single local
# container mirrors the production topology: same server, two databases.
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE allphotos;
EOSQL

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname allphotos \
  -f /docker-entrypoint-initdb.d/accounts-schema.sql
