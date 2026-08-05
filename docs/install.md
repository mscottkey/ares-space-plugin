# Installing

## Option A — the built-in installer (recommended)

AresMUSH can install a plugin straight from its GitHub repo. As an
admin, in-game:

```
plugin/install https://github.com/mscottkey/ares-space-plugin
```

This clones the repo on the server and copies:

- `plugin/` → `plugins/space/`
- `game/*` → `game/` (merges `space.yml`, `space_ships.yml`,
  `space_weapons.yml` into your existing `game/config/`)
- `webportal/*` → `<your ares-webportal checkout>/app/` — only if that
  checkout exists on the server at the path configured in
  `website.website_code_path`; otherwise it warns and skips

It then loads the plugin automatically — no separate `load space` needed
for a first install.

**Requires:** the repo name to match `ares-<name>-plugin` (this one does:
plugin name resolves to `space`), and `git` reachable from the server.

**Not handled automatically — see "Web portal" below:**
- `custom_files/custom-routes.js` needs manual merging, since it's a
  hook shared by every plugin that adds portal pages.
- Rebuilding the Ember portal (`ember build`).

**Updating an existing install:** re-running `plugin/install` refreshes
`plugins/space/` but does **not** re-copy `game/config/space*.yml` once
they already exist (it warns and tells you to copy them by hand if you
want to overwrite your tuning). Fine for picking up code fixes; if a
release changes the shipped defaults and you want those too, copy the
config files over manually.

## Option B — manual copy (SFTP, or no server-side git)

## 1. Plugin files

Copy the `plugin/` directory into your game as `plugins/space`:

```
cp -r plugin /path/to/aresmush/game/plugins/space
```

**The folder must be named `space`.** Core resolves a plugin's module by
matching the upcased folder name against `AresMUSH` constants, so a
folder named `space_combat` would look for `AresMUSH::SPACE_COMBAT` and
fail at boot with `SystemNotFoundException`.

## 2. Config files

Copy the three config files into your game config:

```
cp game/config/space.yml         /path/to/aresmush/game/config/
cp game/config/space_ships.yml   /path/to/aresmush/game/config/
cp game/config/space_weapons.yml /path/to/aresmush/game/config/
```

## 3. Match the station skills to your game

`space.yml` maps each crew station to an FS3 ability:

```yaml
station_skills:
  pilot: Piloting
  helm: Piloting
  gunnery: Gunnery
  engineering: Technician
  sensors: Alertness
  flight_ops: Composure
```

The shipped defaults are stock FS3 ability names (`Piloting`, `Gunnery`,
`Technician`, `Alertness`, `Composure`), so a fresh game works with no
changes. If your game has renamed or replaced any of these, update the
mapping to match. Anything that doesn't resolve to a real FS3 ability
rolls a flat untrained pool instead — which works, but means nobody's
skill matters at that station. After loading the plugin, run
`config/check`: it reports every station mapped to an ability FS3
doesn't know, along with unknown weapons and bad firing arcs in your
ship classes.

## 4. Load it

Restart the game, or load the plugin without restarting:

```
load space
```

(not `manage/load` — the command's root is just `load`.) Confirm it
took with `plugins`, which lists everything currently loaded. Both
`load` and `config/check` require Admin or the `manage_game`
permission.

Option A (`plugin/install`) already does this step for you on first
install.

## 5. Smoke test

```
space/sector Test Sector=20x20
space/spawn Test Sector/Talon=Talon One
space/spawn Test Sector/Swarm Mote=Mote Alpha
space/place Talon One=5,5/S
space/place Mote Alpha=5,6/N
space/crew Talon One/pilot=YourCharacter
space/start Test Sector
space/tac
space/fire Mote Alpha=0
space/resolve Test Sector
```

## 6. Web portal (optional)

The portal files are plain Ember — no React, no separate bundle, no
webpack. `webportal/` mirrors the layout of `ares-webportal`'s `app/`
directory directly (`webportal/routes/`, `webportal/templates/`, etc.),
which is what lets `plugin/install` copy it straight across; `custom_files/`
sits outside `webportal/` at the repo root for exactly the opposite
reason — it's never auto-copied, because it holds files meant to be
merged by hand.

If you used Option A and the auto-copy skipped (checkout not found) or
you're doing this by SFTP, copy into your portal checkout:

| From | To |
|---|---|
| `webportal/routes/space-sectors.js` | `aresmush/webportal/app/routes/` |
| `webportal/routes/space-tactical.js` | `aresmush/webportal/app/routes/` |
| `webportal/controllers/space-tactical.js` | `aresmush/webportal/app/controllers/` |
| `webportal/templates/space-sectors.hbs` | `aresmush/webportal/app/templates/` |
| `webportal/templates/space-tactical.hbs` | `aresmush/webportal/app/templates/` |
| `webportal/components/space-plot.js` | `aresmush/webportal/app/components/` |
| `webportal/components/space-plot.hbs` | `aresmush/webportal/app/components/` |

Component JS and HBS are **colocated** in `app/components/` — that is the
current portal's layout, not `app/templates/components/`.

### Register the routes

`custom_files/custom-routes.js` goes to
`aresmush/webportal/app/custom-routes.js`. **Always merge, never
overwrite** — it's one hook shared by every plugin that adds pages, and
`plugin/install` never touches it automatically for that reason. The two
lines that matter:

```js
router.route('space-sectors', { path: '/space' });
router.route('space-tactical', { path: '/space/:id' });
```

Note the file must export a **function** taking the router. (An older
form exporting an array will throw `setupCustomRoutes is not a function`
on current portal versions.)

### Styles

Append `webportal/styles/_space.scss` to
`aresmush/webportal/app/styles/custom.scss`, or drop it in `styles/` and
`@import 'space';` from custom.scss.

### Navigation link (optional)

In `game/config/website.yml`:

```yaml
top_navbar:
  - title: Space
    route: space-sectors
```

### Rebuild the portal

```
cd aresmush/webportal
npm install      # first time only
ember build --environment=production
```

### What the page does

- `/space` lists sectors you can see — your ship's, or all of them for staff.
- `/space/:id` is the tactical plot: an SVG grid (square or hex, matching
  the sector), terrain, contacts drawn from **your ship's sensors only**,
  your own ship with a facing indicator, and panels for orders.
- Clicking a contact targets it; the weapon buttons queue fire orders.
- Orders go through the same `Orders.issue` path the in-game commands
  use, so the browser and the telnet console validate identically and
  produce the same warnings.
- When a round resolves, the report is pushed over the portal's existing
  websocket and the plot refreshes itself. No polling.
- Staff see a "Resolve Round" button and a list of ships still owing
  orders.

Unidentified contacts send position and nothing else — the browser never
receives a name or hull state the crew hasn't resolved.

## Running the specs

The specs run the rules against an in-memory harness — no Redis, no
EventMachine, no game server:

```
bundle install
rspec
```

`ruby tools/demo.rb` prints a scripted engagement's console and round
report, which is the quickest way to eyeball tuning changes.

## Uninstalling

1. `space/uninstall confirm` — deletes every sector, ship and engagement.
2. Delete `plugins/space/` and the three `game/config/space*.yml` files.
3. Remove `space` from `game/config/plugins.yml` if you listed it there.
4. Restart.
