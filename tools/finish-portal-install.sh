#!/bin/bash
# The two steps `plugin/install` deliberately does not do.
#
#   bash tools/finish-portal-install.sh /path/to/aresmush
#
# plugin/install copies game/* into game/ and webportal/* into the
# portal's app/, so the config, the stylesheet, the routes, controllers,
# templates and components are all already in place. What it leaves alone
# are the two files owned by the game rather than by this plugin, which
# every plugin adding pages has to share:
#
#   game/styles/custom_style.scss  - the game's custom CSS hook; the
#                                    shipped _space.scss is a Sass
#                                    partial and compiles only when
#                                    something imports it
#   <portal>/app/custom-routes.js  - one hook, many plugins; overwriting
#                                    it deletes someone else's pages
#
# Safe to re-run: both steps are skipped if already done.
set -euo pipefail

ARES="${1:-}"

if [ -z "$ARES" ]; then
  echo "usage: bash tools/finish-portal-install.sh /path/to/aresmush" >&2
  exit 1
fi
if [ ! -d "$ARES/game/styles" ]; then
  echo "error: $ARES/game/styles not found - is that the aresmush root?" >&2
  exit 1
fi

# ---------------------------------------------------------------------
# 1. Styles.
#
# These are GAME styles, not portal styles. Ares compiles
# engine/styles/ares.scss (which ends with @import "custom_style") with
# game/styles on the load path, and the portal links the result last.
# ---------------------------------------------------------------------
CUSTOM="$ARES/game/styles/custom_style.scss"

if [ ! -f "$ARES/game/styles/_space.scss" ]; then
  echo "!! game/styles/_space.scss is missing - plugin/install hasn't run,"
  echo "!! or ran before this file was added. Re-run it, or copy"
  echo "!! game/styles/_space.scss from the repo by hand."
  echo
fi

touch "$CUSTOM"
if grep -qE '@import\s+["'"'"']space["'"'"']' "$CUSTOM"; then
  echo "custom_style.scss: already imports 'space', left alone"
else
  printf '\n@import "space";\n' >> "$CUSTOM"
  echo "custom_style.scss: added @import \"space\""
fi

# ---------------------------------------------------------------------
# 2. Routes. These really are portal files, so find the checkout the
#    same way plugin/install does.
# ---------------------------------------------------------------------
PORTAL="$(grep -E '^\s*website_code_path:' "$ARES/game/config/website.yml" 2>/dev/null \
          | head -1 | sed -E 's/.*website_code_path:\s*//; s/^["'"'"']//; s/["'"'"']\s*$//' || true)"

if [ -z "$PORTAL" ] || [ ! -d "$PORTAL/app" ]; then
  echo
  echo "Could not find the portal checkout (website_code_path in"
  echo "game/config/website.yml). Skipping the route step - add these"
  echo "three lines to <portal>/app/custom-routes.js by hand:"
  echo
  echo "    router.route('space-system',   { path: '/space' });"
  echo "    router.route('space-sectors',  { path: '/space/sectors' });"
  echo "    router.route('space-tactical', { path: '/space/sector/:id' });"
  echo
else
  ROUTES="$PORTAL/app/custom-routes.js"

  if [ ! -f "$ROUTES" ]; then
    echo "custom-routes.js:  creating (no other plugin has claimed it)"
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
    echo "custom-routes.js:  space routes already present, left alone"
  else
    echo
    echo "custom-routes.js:  exists and has no space routes - MERGE BY HAND."
    echo "Add these inside the exported function's body:"
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

  # An earlier version of these instructions had the stylesheet going to
  # the portal, where nothing compiles it. Clean that up if it's there.
  for stale in "$PORTAL/app/styles/_space.scss" "$PORTAL/app/styles/custom.scss"; do
    if [ -f "$stale" ]; then
      echo "stale file:        $stale (nothing compiles this - safe to delete)"
    fi
  done
fi

echo
echo "Then, in-game:"
echo "    load styles          # rebuilds game/styles/ares.css - no ember build"
echo
echo "The routes DO need a portal rebuild, but only if you changed them:"
echo "    cd \"$PORTAL\" && ember build --environment=production"
