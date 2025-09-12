#!/bin/bash
set -e

# Remove a potentially pre-existing server.pid for Rails.
rm -f /lafiga-api/tmp/pids/server.pid

# Ensure gems are installed into the mounted bundle dir
if ! bundle check > /dev/null 2>&1; then
  echo "Installing missing gems..."
  bundle config set path '/usr/local/bundle'
  bundle install
fi

# Wait for Postgres
if [ -n "$DATABASE_URL" ]; then
  echo "Waiting for database..."
  until pg_isready -h ${PGHOST:-db} -p ${PGPORT:-5432} -U ${PGUSER:-lafiga_api} >/dev/null 2>&1; do
    sleep 1
  done
fi

# Then exec the container's main process (what's set as CMD in the Dockerfile).
exec "$@"
