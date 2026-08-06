#!/bin/bash
# The two portal steps `plugin/install` deliberately does not do.
#
#   bash tools/finish-portal-install.sh /path/to/aresmush/webportal
#
# plugin/install copies webportal/* straight into the portal's app/, so
# the routes, controllers, templates, components and _space.scss are all
# already in place. What it leaves alone are the two files that belong to
# the portal rather than to this plugin, and that every plugin adding
# pages has to share:
#
#   app/custom-routes.js    - one hook, many plugins; overwriting it
#                             would delete someone else's pages
#   app/styles/custom.scss  - likewise, and _space.scss does nothing at
#                             all until something imports it
#
# Safe to re-run: both steps are skipped if already done.
set -euo pipefail

PORTAL="${1:-}"

if [ -z "$PORTAL" ]; then
  echo "usage: bash tools/finish-portal-install.sh /path/to/aresmush/webportal" >&2
  exit 1
fi
if [ ! -d "$PORTAL/app" ]; then
  echo "error: $PORTAL/app does not exist - is that the webportal checkout?" >&2
  exit 1
fi

# Sanity check that plugin/install actually landed, so a missing page
# later isn't mistaken for a problem with these two steps.
missing=0
for f in app/templates/space-system.hbs \
         app/components/space-system-map.js \
         app/components/space-system-map.hbs \
         app/styles/_space.scss; do
  if [ ! -f "$PORTAL/$f" ]; then
    echo "!! missing: $f"
    missing=1
  fi
done
if [ "$missing" = "1" ]; then
  echo
  echo "Those come from plugin/install. If they're absent it either hasn't"
  echo "run, or it couldn't find this checkout at website.website_code_path"
  echo "and skipped the webportal copy. Re-run it, or copy webportal/* from"
  echo "the repo into $PORTAL/app/ by hand."
  echo
fi

# ---------------------------------------------------------------------
# 1. Routes
# ---------------------------------------------------------------------
ROUTES="$PORTAL/app/custom-routes.js"

if [ ! -f "$ROUTES" ]; then
  echo "custom-routes.js: creating (no other plugin has claimed it)"
  cat > "$ROUTES" <<'EOF'
// Registers this game's extra portal pages. Shared by every plugin that
// adds one, so merge into it rather than replacing it.
export default function (router) {
  // The system map - the standard view of space, no combat required.
  router.route('space-system', { path: '/space' });

  // Combat. Sectors are the tactical grids, only live during a fight.
  router.route('space-sectors', { path: '/space/sectors' });
  router.route('space-tactical', { path: '/space/sector/:id' });
}
EOF
elif grep -q "space-system" "$ROUTES"; then
  echo "custom-routes.js: space routes already present, left alone"
else
  echo
  echo "custom-routes.js: exists and has no space routes - MERGE BY HAND."
  echo "Add these inside the setupCustomRoutes / exported function body:"
  echo
  echo "    router.route('space-system',   { path: '/space' });"
  echo "    router.route('space-sectors',  { path: '/space/sectors' });"
  echo "    router.route('space-tactical', { path: '/space/sector/:id' });"
  echo
  echo "Current contents, for reference:"
  echo "---------------------------------------------------------------"
  cat "$ROUTES"
  echo "---------------------------------------------------------------"
  echo
fi

# ---------------------------------------------------------------------
# 2. Styles
# ---------------------------------------------------------------------
CUSTOM="$PORTAL/app/styles/custom.scss"
touch "$CUSTOM"

if grep -qE "@import\s+['\"]space['\"]" "$CUSTOM"; then
  echo "custom.scss:      already imports 'space', left alone"
else
  printf "\n@import 'space';\n" >> "$CUSTOM"
  echo "custom.scss:      added @import 'space'"
fi

echo
echo "Now rebuild the portal:"
echo "    cd $PORTAL && ember build --environment=production"
