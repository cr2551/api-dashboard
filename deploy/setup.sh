#!/bin/sh
# Prepares deploy/ on the server and starts (or updates) the stack. Safe to
# re-run: it never overwrites an existing .env or services.json.
#
# Usage, from the repo root on the server: sh deploy/setup.sh <domain>
set -eu
cd "$(dirname "$0")"

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker with the compose plugin is required (deploy/README.md, step 3)." >&2
  exit 1
fi

if [ ! -f .env ]; then
  if [ $# -ne 1 ]; then
    echo "usage: sh deploy/setup.sh <domain>" >&2
    exit 64
  fi
  token=$(openssl rand -hex 32)
  # Created unreadable for other users.
  (
    umask 077
    sed -e "s/^DOMAIN=.*/DOMAIN=$1/" -e "s/^API_TOKEN=.*/API_TOKEN=$token/" \
      .env.example >.env
  )
  echo "Created deploy/.env with a new API_TOKEN."
  echo "Read it when you need it: grep API_TOKEN deploy/.env"
fi
chmod 600 .env

if [ ! -f services.json ]; then
  cp ../services.example.json services.json
  echo "Created deploy/services.json from services.example.json."
fi

if grep -q '"type": *"stripe"' services.json &&
  ! grep -q '^STRIPE_API_KEY=..*' .env; then
  echo "services.json has a stripe service but .env has no STRIPE_API_KEY." >&2
  echo "Add your sk_test_ key to deploy/.env, or remove the stripe entry" >&2
  echo "from deploy/services.json, then run this again." >&2
  exit 1
fi

docker compose up -d --build
docker compose ps
