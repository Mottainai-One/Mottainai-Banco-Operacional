#!/bin/sh
set -eu

if [ -z "${QA_DB_APP_PASSWORD:-}" ]; then
  echo 'QA_DB_APP_PASSWORD is required' >&2
  exit 1
fi

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -f /schema/install.sql

psql -v ON_ERROR_STOP=1 -v qa_app_password="$QA_DB_APP_PASSWORD" \
  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -f /qa/app-role.sql
