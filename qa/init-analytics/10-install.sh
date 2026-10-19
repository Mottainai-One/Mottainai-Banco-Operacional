#!/bin/sh
set -eu

if [ -z "${QA_ANALYTICS_READER_PASSWORD:-}" ]; then
  echo 'QA_ANALYTICS_READER_PASSWORD is required' >&2
  exit 1
fi

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -f /schema/install.sql
psql -v ON_ERROR_STOP=1 -v qa_reader_password="$QA_ANALYTICS_READER_PASSWORD" \
  --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -f /qa/analytics-reader.sql
