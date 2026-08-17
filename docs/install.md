# Installing

## Option A — the built-in installer (recommended)

AresMUSH can install a plugin straight from its GitHub repo. As an
admin, in-game:

```
plugin/install https://github.com/mscottkey/ares-space-plugin
```

This clones the repo on the server and copies:

- `plugin/` → `plugins/space/`
- `game/*` → `game/` (the `space*.yml` files merge into your existing
  `game/config/`, and `_space.scss` into `game/styles/`)
- `webportal/*` → `<your ares-webportal checkout>/app/` — only if that
  checkout exists on the server at the path configured in
  `website.website_code_path`; otherwise it warns and skips

It then loads the plugin automatically — no separate `load space` needed
for a first install.

**Requires:** the repo name to match `ares-<name>-plugin` (this one does:
plugin name resolves to `space`), and `git` reachable from the server.

**Not handled automatically — see "Web portal" below:**
- `game/styles/custom_style.scss` needs one `@import "space";` line, since
  it's the game's shared CSS hook. Without it the stylesheet is copied but
  never compiled, and the map draws plain and motionless.
- `custom_files/custom-routes.js` needs manual merging, since it's a
  hook shared by every plugin that adds portal pages.
- Rebuilding the Ember portal (`ember build`), once, for the routes.

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

## 2. Config and style files

```
cp game/config/space.yml         /path/to/aresmush/game/config/
cp game/config/space_ships.yml   /path/to/aresmush/game/config/
cp game/config/space_weapons.yml /path/to/aresmush/game/config/
cp game/config/space_systems.yml /path/to/aresmush/game/config/
cp game/styles/_space.scss       /path/to/aresmush/game/styles/
```

The stylesheet needs one line in `game/styles/custom_style.scss` to be
compiled at all — see "Styles" under "Web portal" below.

## 3. Match the station skills to your game

`space.yml` maps each crew station to an ability:

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
mapping to match. Anything that doesn't resolve to a real ability rolls a
flat untrained pool instead — which works, but means nobody's skill
matters at that station. After loading the plugin, run `config/check`: it
reports every station mapped to an ability the dice system doesn't know,
along with unknown weapons and bad firing arcs in your ship classes.

### Using a dice system other than FS3

`space.yml`'s `dice_system` decides which system resolves crew actions.
It defaults to `fs3` — core FS3 — and a game that leaves it alone behaves
exactly as this plugin always has.

Everything else in the plugin (ships, arcs, sections, silhouette, the
round structure) is system-agnostic; only the dice are not. A game on
another system supplies an adapter — four small methods — and names it
here. `config/check` reports an unknown name (and lists what *is*
installed), an adapter missing part of the contract, and one that isn't
available.

The contract, and an honest account of what a non-FS3 system does and
doesn't get, is in [docs/architecture.md](architecture.md) §14. The short
version: writing an adapter is a small job, but the tuning values in
`space.yml` are sized to FS3's success curve, so a different system will
want them retuned.

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

**`plugin/install` copies all of it**: `webportal/*` (routes,
controllers, templates, colocated components) into the portal's `app/`,
and `game/*` — including `game/styles/_space.scss` — into your `game/`.
There is no file to move by hand.

What it can't touch are the two hook files owned by the game rather than
by this plugin, because every plugin adding pages shares them:

| File | Why it's left alone |
|---|---|
| `game/styles/custom_style.scss` | the game's CSS hook, and the admin's own — editable in the portal under *Theme → Custom Styles* |
| `<portal>/app/custom-routes.js` | one hook, many plugins — overwriting it deletes someone else's pages |

Both are one line each and covered below. Or do them at once — note this
takes the **aresmush root**, and finds the portal itself from
`website_code_path`:

```
bash tools/finish-portal-install.sh /path/to/aresmush
```

It also warns if `plugin/install`'s copy didn't land, and is safe to
re-run.

### Register the routes

`custom_files/custom-routes.js` goes to
`aresmush/webportal/app/custom-routes.js`. It sits outside `webportal/`
at the repo root precisely so it is *never* auto-copied. **Always merge,
never overwrite.** The three lines that matter, inside the exported
function's body:

```js
router.route('space-system', { path: '/space' });
router.route('space-sectors', { path: '/space/sectors' });
router.route('space-tactical', { path: '/space/sector/:id' });
```

Note the file must export a **function** taking the router. (An older
form exporting an array will throw `setupCustomRoutes is not a function`
on current portal versions.)

### Styles

**These are game styles, not portal styles.** `ares-webportal` has no
customization hook in `app/styles/` — its `app.scss` `@use`s a fixed list
and nothing else gets compiled. The hook is on the game side:

- Ares compiles `engine/styles/ares.scss`, which ends with
  `@import "custom_style"`, through SassC with `game/styles` on the load
  path, writing `game/styles/ares.css`.
- The portal's `index.html` links `/game/styles/ares.css` **last**, after
  its own bundle — so these rules win without needing `!important`.

There are two ways in, and they end at the same file. **Pick one** —
doing both just duplicates every rule.

#### Paste it (no shell, no files)

Open the portal as an admin, go to **Theme → Custom Styles**, and paste
the entire contents of `game/styles/_space.scss` at the bottom of
whatever's already there. That box *is* `game/styles/custom_style.scss`,
and it's SCSS, so the file goes in as-is — nesting, `@keyframes`, media
queries and all.

Nothing to upload and nothing to import. Your existing styles are
untouched; ours land after them.

#### Or import it (one line)

`plugin/install` already put `_space.scss` in `game/styles/`. Sass skips a
leading-underscore partial unless something imports it, so add one line —
either in that same **Theme → Custom Styles** box, or from a shell:

```
echo '@import "space";' >> aresmush/game/styles/custom_style.scss
```

Tidier, and it keeps your CSS box uncluttered.

#### Either way

Then, in-game:

```
load styles
```

That's the whole thing — **no `ember build` for CSS.** `load styles` calls
`Website.rebuild_css`, and the browser picks it up on a hard refresh.

**On updates**, note that re-running `plugin/install` does *not* refresh
`game/` once the plugin exists — `PluginImporter` skips `import_game`
entirely on a reinstall. So a new release's CSS needs either a re-paste,
or `_space.scss` copied over by hand. Neither route gets it for free.

This step is easy to miss because nothing errors without it. It no longer
breaks the map — both pages carry presentation attributes as a fallback,
so an unstyled build draws a correct-but-plain map rather than a black
smear — but you lose the hover states, the engagement pulse and the orbit
animation, which is what "the orbits don't move" looks like.

> If you followed an earlier version of these instructions and created
> `<portal>/app/styles/_space.scss` and `app/styles/custom.scss`, delete
> both. Nothing compiles them; they were the wrong hook.

### Navigation link (optional)

In `game/config/website.yml`:

```yaml
top_navbar:
  - title: Space
    menu:
      - title: Map
        route: space-system
      - title: Sectors
        route: space-sectors
```

`route:` takes the **route name, not the URL path**. The system map is
named `space-system` even though it lives at `/space`, so `route: space`
throws inside `LinkTo` and breaks the whole menu.

Don't put `space-tactical` in the navbar - it needs an `:id` and a
`LinkTo` without one fails the same way. It's reached by clicking a
sector, or from a body's engagement link on the system map.

Run `load config` in-game afterwards. The link only resolves once the
routes are actually built into the portal, so do this after the rebuild
below.

### Rebuild the portal

```
cd aresmush/webportal
npm install      # first time only
ember build --environment=production
```

### What the page does

- `/space` is the system map, and it's the standard view — no ship and no
  combat required. Star, orbital rings, worlds coloured by classification
  with faction halos, your ship and its course, and a pulsing marker on
  any body with a fight going on. `?system=<key>` picks another system.
  Click a body for detail and a "set course" button.
- `/space/sectors` lists sectors you can see — your ship's, or all of
  them for staff.
- `/space/sector/:id` is the tactical plot: an SVG grid (square or hex,
  matching the sector), terrain, contacts from **your ship's sensors only**,
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
