#!/bin/bash
# Inject optional API keys into oss-advisor creds store at container startup.
# Keys are passed as env vars (never baked into the image).
set -e

if [ -n "${GITHUB_TOKEN:-}" ]; then
  bash /app/oss-advisor/scripts/creds.sh set github "$GITHUB_TOKEN"
fi

if [ -n "${LIBRARIESIO_KEY:-}" ]; then
  bash /app/oss-advisor/scripts/creds.sh set librariesio "$LIBRARIESIO_KEY"
fi

if [ -n "${SNYK_KEY:-}" ]; then
  bash /app/oss-advisor/scripts/creds.sh set snyk "$SNYK_KEY"
fi

if [ -n "${SOCKET_KEY:-}" ]; then
  bash /app/oss-advisor/scripts/creds.sh set socket "$SOCKET_KEY"
fi

exec "$@"
