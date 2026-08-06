#!/bin/bash
# Copies this plugin's web portal files into an ares-webportal checkout.
#
#   bash tools/install-portal.sh /path/to/aresmush/webportal
#
# `plugin/install` already does this, but only when it can find the portal
# checkout at the path in `website.website_code_path`. When it can't, it
# warns and skips - and this is the manual equivalent.
#
# Safe to re-run. The one file it will not overwrite is custom-routes.js,
# which is shared with every other plugin that adds portal pages; it
# prints the lines to merge instead.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORTAL="${1:-}"

if [ -z "$PORTAL" ]; then
  echo "usage: bash tools/install-portal.sh /path/to/aresmush/webportal" >&2
  exit 1
fi
if [ ! -d "$PORTAL/app" ]; then
  echo "error: $PORTAL/app does not exist - is that the webportal checkout?" >&2
  exit 1
fi

for dir in routes controllers templates components styles; do
  mkdir -p "$PORTAL/app/$dir"
done

# webportal/ mirrors the portal's app/ directory exactly, which is what
# lets plugin/install copy it straight across - so this is a flat copy.
for dir in routes controllers templates components styles; do
  for file in "$REPO/webportal/$dir"/*; do
    [ -e "$file" ] || continue
    echo "  app/$dir/$(basename "$file")"
    cp "$file" "$PORTAL/app/$dir/"
  done
done

# ---------------------------------------------------------------------
# Shared with every other plugin, so merged rather than overwritten.
# ---------------------------------------------------------------------
ROUTES="$PORTAL/app/custom-routes.js"
if [ ! -f "$ROUTES" ]; then
  echo "  app/custom-routes.js (created)"
  cp "$REPO/custom_files/custom-routes.js" "$ROUTES"
elif grep -q "space-system" "$ROUTES"; then
  echo "  app/custom-routes.js already has the space routes - left alone"
else
  echo
  echo "!! app/custom-routes.js exists and has no space routes."
  echo "!! Add these three lines inside its setupCustomRoutes(router) body:"
  echo
  echo "     router.route('space-system',   { path: '/space' });"
  echo "     router.route('space-sectors',  { path: '/space/sectors' });"
  echo "     router.route('space-tactical', { path: '/space/sector/:id' });"
  echo
fi

# ---------------------------------------------------------------------
# The stylesheet does nothing until custom.scss imports it. This is the
# step that gets forgotten, and the map is noticeably plainer without it.
# ---------------------------------------------------------------------
CUSTOM="$PORTAL/app/styles/custom.scss"
touch "$CUSTOM"
if grep -q "space" "$CUSTOM"; then
  echo "  app/styles/custom.scss already imports it - left alone"
else
  echo "  app/styles/custom.scss (added @import 'space')"
  printf "\n@import 'space';\n" >> "$CUSTOM"
fi

echo
echo "Done. Now rebuild the portal:"
echo "    cd $PORTAL && ember build --environment=production"
