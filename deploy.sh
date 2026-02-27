#!/usr/bin/env bash
# deploy.sh — Build Flutter web, inject AUTH_HASH from Vercel env, deploy to production.
set -euo pipefail

echo "▶ Building Flutter web..."
flutter build web --release

echo "▶ Pulling production env vars from Vercel..."
vercel env pull .env.deploy --environment production --yes 2>/dev/null

# Extract AUTH_HASH value
AUTH_HASH=$(grep '^AUTH_HASH=' .env.deploy | cut -d'=' -f2- | tr -d '"')
rm -f .env.deploy

if [[ -z "$AUTH_HASH" ]]; then
  echo "✗ AUTH_HASH not found in Vercel env. Aborting."
  exit 1
fi

echo "▶ Injecting AUTH_HASH into build/web/index.html..."
python3 -c "
import sys
with open('build/web/index.html', 'r') as f:
    c = f.read()
c = c.replace('__AUTH_HASH__', sys.argv[1])
with open('build/web/index.html', 'w') as f:
    f.write(c)
" "$AUTH_HASH"

echo "▶ Deploying to Vercel (production)..."
vercel deploy build/web --prod --yes

echo "✅ Done!"
