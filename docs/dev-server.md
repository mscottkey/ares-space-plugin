# Standing up a throwaway Ares game to test this plugin

This is the exact path used to smoke-test the plugin against a real
AresMUSH instance. It skips `bin/install` entirely — that script
provisions a whole server (RVM, nginx, systemd) and is far more than a
local test needs.

Two gotchas below cost real time; both are called out.

## 1. Prerequisites

Ruby 3.3.x, Redis, and a compiler (several gems build native
extensions).

```
redis-server --daemonize yes
redis-cli ping        # expect PONG
```

## 2. Clone and bundle

```
git clone https://github.com/aresmush/aresmush
cd aresmush
bundle install
```

## 3. Create the game directory

```
cp -r install/game.distr game
bundle exec rake configure "host_name=localhost~mush_name=Test Game~server_port=4201"
```

If `rake` isn't resolvable through bundler, the templates are trivial —
`install/templates/*.erb` generate `game/config/{database,server,game,secrets}.yml`
and you can write them by hand.

### Gotcha 1: Redis AUTH

Ares always builds its connection string as
`redis://:<password>@<host>`, so it sends `AUTH` even when the password
is blank. A default Redis with no password rejects that:

```
ERR AUTH <password> called without any password configured for the
default user.
```

Everything downstream then fails with confusing `nil` errors. Set a
password on both sides:

```
redis-cli CONFIG SET requirepass "devpass"
```

and put the same value in `game/config/secrets.yml` under
`secrets: database: password`.

### Gotcha 2: initialize the database

A fresh Redis has no `Game.master` and no rooms, so character creation
fails with `undefined method 'ic_start_room' for nil`. Run Ares' DB
init once:

```ruby
# init_db.rb
$LOAD_PATH.unshift(File.join(Dir.pwd, "engine"))
require 'aresmush'
require_relative 'install/init_db.rb'

b = AresMUSH::Bootstrapper.new
b.config_reader.load_game_config
AresMUSH::Global.plugin_manager.load_all
b.db.load_config
AresMUSH::Install.init_db
```

```
bundle exec ruby init_db.rb
```

## 4. Install this plugin

```
cp -r /path/to/ares-space-plugin/plugin plugins/space
cp /path/to/ares-space-plugin/game/config/space*.yml game/config/
```

The folder **must** be named `space` — core resolves a plugin's module
by upcased folder name.

## 5. Boot and check

Either run the server (`bundle exec rake startares`) and connect on
port 4201, or drive it headlessly, which is faster for iterating:

```ruby
# boot.rb
$LOAD_PATH.unshift(File.join(Dir.pwd, "engine"))
require 'aresmush'

b = AresMUSH::Bootstrapper.new
b.config_reader.load_game_config
b.locale.setup                              # engine locale strings
AresMUSH::Global.plugin_manager.load_all
b.locale.reload                             # plugin locale strings
b.db.load_config

puts AresMUSH::Global.plugin_manager.plugins.map(&:to_s).grep(/Space/).inspect
puts AresMUSH::Global.plugin_manager.check_plugin_config
```

**Load the locales.** `minimal_boot` in Ares' own Rakefile doesn't, so
engine strings like `dispatcher.not_allowed` come back as
`Translation missing:` and you'll chase a bug that isn't there.

`check_plugin_config` is worth reading — this plugin reports any crew
station mapped to an FS3 ability the game doesn't define.

## 6. Driving commands headlessly

Commands only need a client that responds to a few methods, so you can
exercise them without a telnet session:

```ruby
class FakeClient
  attr_reader :out
  def initialize; @out = []; end
  def logged_in?; true; end
  def emit(m); @out << m; end
  def emit_success(m); @out << "OK  #{m}"; end
  def emit_failure(m); @out << "ERR #{m}"; end
  def emit_ooc(m); @out << "!!  #{m}"; end
end

client = FakeClient.new
cmd = AresMUSH::Command.new("space/tac")
handler = AresMUSH::Space.get_cmd_handler(client, cmd, enactor)
handler.new(client, cmd, enactor).on_command
puts client.out
```

Web request handlers are the same shape — build an object responding to
`cmd`, `args` and `enactor`, and call
`AresMUSH::Space.get_web_request_handler(request).new.handle(request)`.

You'll see EventMachine warnings (`eventmachine not initialized`) when
driving things headlessly. That's the logger's async writer with no
reactor running; a real server has one and it doesn't appear.

## 7. Smoke test

```
space/sector Test Sector=20x14
space/spawn Test Sector/Talon=Talon One
space/spawn Test Sector/Swarm Mote=Mote Alpha
space/place Talon One=5,5/S
space/place Mote Alpha=5,7/N
space/crew Talon One/pilot=YourCharacter
space/start Test Sector
space/tac
space/helm S=2
space/fire Mote Alpha=0
space/resolve Test Sector
space/uninstall confirm
```
