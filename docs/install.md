# Installing

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
  engineering: Engineering
  sensors: Sensors
  flight_ops: Leadership
```

These must be abilities your game's FS3 config actually defines. Any that
don't exist will roll a flat untrained pool instead — which works, but
means nobody's skill matters at that station. After starting the game,
run `manage/checkconfig`: this plugin reports every station mapped to an
ability FS3 doesn't know, along with unknown weapons and bad firing arcs
in your ship classes.

## 4. Restart

Restart the game, or `manage/load space` if you prefer.

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
