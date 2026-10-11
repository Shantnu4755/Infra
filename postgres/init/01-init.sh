#!/bin/bash
set -euo pipefail

for app in kavach hisaab dwaarpal karya sutra sanjeevani; do
  var="$(echo "${app}_DB_PASSWORD" | tr '[:lower:]' '[:upper:]')"
  password="${!var}"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<EOSQL
CREATE USER ${app} WITH PASSWORD '${password}';
CREATE DATABASE ${app} OWNER ${app};
EOSQL
done

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname sutra \
  -c "CREATE EXTENSION IF NOT EXISTS vector;"
