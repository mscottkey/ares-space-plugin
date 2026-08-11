require "yaml"

# A minimal stand-in for the parts of AresMUSH the space rules touch, so
# the resolver can be run end to end without Redis, EventMachine or a
# running game. The doubles implement the same interfaces the real engine
# does; ship behaviour itself comes from the production ShipBehavior
# module, so the specs and the game cannot drift apart.

module AresMUSH

  module TestConfig
    def self.load!
      root = File.expand_path("../../..", __dir__)
      @config = {}
      Dir[File.join(root, "game", "config", "*.yml")].each do |file|
        data = YAML.load_file(file)
        next if !data.is_a?(Hash)
        data.each do |plugin, values|
          @config[plugin] ||= {}
          @config[plugin].merge!(values) if values.is_a?(Hash)
        end
      end
      @config
    end

    def self.config
      @config ||= load!
    end

    def self.read(*path)
      path.flatten.reduce(config) do |node, key|
        break nil if !node.is_a?(Hash)
        node[key.to_s]
      end
    end
  end

  class TestLogger
    def method_missing(_name, *_args); end
    def respond_to_missing?(*_args); true; end
  end

  module Global
    def self.read_config(*path)
      TestConfig.read(*path)
    end

    def self.logger
      @logger ||= TestLogger.new
    end
  end

  # Deterministic stand-in for core FS3. The real plugin always calls out
  # to FS3Skills; here we control what it returns so the rules, not the
  # dice, are what the specs measure.
  module FS3Skills
    class RollParams
      attr_accessor :ability, :modifier, :linked_attr
      def initialize(ability, modifier = 0, linked_attr = nil)
        self.ability = ability
        self.modifier = modifier
        self.linked_attr = linked_attr
      end
    end

    class << self
      attr_accessor :scripted_successes, :roll_log

      def reset!
        self.scripted_successes = []
        self.roll_log = []
      end

      def next_successes
        value = (scripted_successes || []).shift
        value.nil? ? 0 : value
      end

      def one_shot_roll(char, roll_params)
        successes = next_successes
        roll_log << { char: char.respond_to?(:name) ? char.name : char.to_s,
                      ability: roll_params.ability,
                      modifier: roll_params.modifier,
                      successes: successes }
        { successes: successes, success_title: "Test" }
      end

      def one_shot_die_roll(dice)
        successes = next_successes
        roll_log << { char: nil, dice: dice, successes: successes }
        { successes: successes, success_title: "Test" }
      end

      def get_ability_type(ability)
        %w(Alertness Athletics Composure Demolitions Firearms Gunnery Medicine Melee Piloting Stealth Technician).include?("#{ability}") ? :action : :background
      end
    end
  end

  class TestCharacter
    attr_accessor :id, :name, :room, :current_ship
    def initialize(id, name)
      self.id = id
      self.name = name
    end

    def update(attrs)
      attrs.each { |k, v| send("#{k}=", v) }
      self
    end

    def is_admin?
      !!@is_admin
    end

    def is_admin=(val)
      @is_admin = val
    end
  end

  # Stand-ins for core's Room model and the `rooms` plugin's public
  # move_to API (plugins/rooms/public/rooms_api.rb) - Boarding calls the
  # real ones in production, exactly the same way the plugin calls out
  # to real FS3Skills above.
  class TestRoom
    attr_accessor :id, :name
    @@next_id = 1

    def initialize(name)
      self.id = (@@next_id += 1).to_s
      self.name = name
    end

    def get_exit(name)
      (Exit.registry || {}).values.find do |e|
        e.source == self && e.name.to_s.upcase == "#{name}".upcase
      end
    end
  end

  module Room
    class << self
      attr_accessor :registry

      def create(opts = {})
        room = TestRoom.new(opts[:name])
        self.registry ||= {}
        self.registry[room.id] = room
        room
      end

      def [](id)
        (self.registry || {})["#{id}"]
      end

      def reset!
        self.registry = {}
      end
    end
  end

  # Mirrors core's Exit model closely enough for Docking's specs -
  # named, one-directional, source/dest are plain Room references.
  class TestExit
    attr_accessor :id, :name, :source, :dest
    @@next_id = 1

    def initialize(opts = {})
      self.id = (@@next_id += 1).to_s
      self.name = opts[:name]
      self.source = opts[:source]
      self.dest = opts[:dest]
    end

    def update(attrs)
      attrs.each { |k, v| send("#{k}=", v) }
      self
    end

    def delete
      (Exit.registry || {}).delete(self.id)
    end
  end

  module Exit
    class << self
      attr_accessor :registry

      def create(opts = {})
        exit = TestExit.new(opts)
        self.registry ||= {}
        self.registry[exit.id] = exit
        exit
      end

      def [](id)
        (self.registry || {})["#{id}"]
      end

      def reset!
        self.registry = {}
      end
    end
  end

  class TestBodyState
    attr_accessor :id, :system_key, :body_key, :faction, :notes, :landing_room
    @@next_id = 1

    def initialize(opts = {})
      self.id = (@@next_id += 1).to_s
      self.system_key = opts[:system_key]
      self.body_key = opts[:body_key]
      self.faction = opts[:faction]
      self.notes = opts[:notes]
      self.landing_room = opts[:landing_room]
    end

    def update(attrs)
      attrs.each { |k, v| send("#{k}=", v) }
      self
    end
  end

  # No real Redis-backed SpaceBodyState existed in the harness before
  # Docking needed one - Systems.claim/control_record had only ever been
  # exercised through the rescue => nil in control_record, which quietly
  # swallowed the missing constant. set_landing_room and claim both call
  # SpaceBodyState.create directly, with no rescue of their own, so
  # without this they'd raise in specs instead of being tested.
  module SpaceBodyState
    class << self
      attr_accessor :all

      def create(opts = {})
        record = TestBodyState.new(opts)
        self.all ||= []
        self.all << record
        record
      end

      def reset!
        self.all = []
      end
    end
  end

  module Rooms
    class << self
      attr_accessor :move_log

      def reset!
        self.move_log = []
      end

      # Mirrors the real move_to's one visible side effect for specs:
      # the character ends up in the new room. The real one also fires
      # room echoes and screen-reader handling - not this plugin's
      # behaviour to test, so the double doesn't reproduce it.
      def move_to(client, char, room, exit_name = nil)
        self.move_log ||= []
        move_log << { char: char.name, room: room ? room.name : nil, exit: exit_name }
        char.update(room: room)
      end

      def ooc_room
        @ooc_room ||= Room.create(name: "OOC Room")
      end
    end
  end

  class TestSector
    attr_accessor :id, :name, :geometry, :width, :height, :system_key, :body_key
    def initialize(opts = {})
      self.id = opts[:id] || 1
      self.name = opts[:name] || "Test Sector"
      self.geometry = opts[:geometry] || "square"
      self.width = opts[:width] || 20
      self.height = opts[:height] || 20
      self.system_key = opts[:system_key]
      self.body_key = opts[:body_key]
    end

    def update(attrs)
      attrs.each { |k, v| send("#{k}=", v) }
      self
    end
  end

  # No real Redis-backed SpaceSector.all/create existed in the harness
  # before this - Systems.sectors_at/engagement_at had only ever been
  # exercised through the rescue => nil in sectors_at, which quietly
  # swallowed the missing constant, so "a ship at an engaged body shows
  # a map marker" (web_data.rb) could never actually be tested. Same
  # blind spot as SpaceBodyState/SpaceCombat elsewhere in this file.
  module SpaceSector
    class << self
      attr_accessor :all

      def create(opts = {})
        sector = TestSector.new(opts)
        self.all ||= []
        self.all << sector
        sector
      end

      def reset!
        self.all = []
      end
    end
  end

  class TestShip
    include Space::ShipBehavior

    ATTRS = [ :id, :name, :ship_class, :faction, :x, :y, :facing, :speed,
              :sections, :stations, :orders, :ammo, :evade_margin,
              :sweep_range, :status, :sector, :entry_room, :operational_rooms,
              :owner, :boarded_from, :system_key, :location_key, :dock_exit,
              :carrier, :hangar_room, :destination_key, :departed_at,
              :travel_seconds, :system_ring, :system_angle ]
    attr_accessor(*ATTRS)

    def initialize(opts = {})
      self.id = opts[:id]
      self.name = opts[:name]
      self.ship_class = opts[:ship_class]
      self.faction = opts[:faction] || "Unknown"
      self.x = opts[:x] || 0
      self.y = opts[:y] || 0
      self.facing = opts[:facing] || 0
      self.speed = opts[:speed] || 0
      self.sector = opts[:sector]
      self.status = opts[:status] || "active"
      self.evade_margin = 0
      self.sweep_range = 0
      self.stations = opts[:stations] || {}
      self.orders = {}
      self.entry_room = opts[:entry_room]
      self.operational_rooms = opts[:operational_rooms] || []
      self.owner = opts[:owner]
      self.boarded_from = opts[:boarded_from] || {}
      self.system_key = opts[:system_key]
      self.location_key = opts[:location_key]
      self.dock_exit = opts[:dock_exit]
      self.carrier = opts[:carrier]
      self.hangar_room = opts[:hangar_room]
      self.system_ring = opts[:system_ring]
      self.system_angle = opts[:system_angle]
      class_data = Space::SpaceConfig.ship_class(self.ship_class) || {}
      self.sections = opts[:sections] || Space::Ships.build_sections(class_data)
      self.ammo = opts[:ammo] || Space::Ships.build_ammo(class_data)
    end

    def update(attrs)
      attrs.each { |k, v| send("#{k}=", v) }
      self
    end

    def sector_id
      sector ? sector.id : nil
    end

    def in_transit?
      !self.destination_key.to_s.empty? && !self.departed_at.nil?
    end

    def eta_seconds
      Space::Astro.seconds_remaining(self.departed_at, self.travel_seconds.to_i)
    end
  end

  class TestCombat
    attr_accessor :id, :sector, :round, :state, :log, :last_report
    @@next_id = 1

    def initialize(sector)
      self.id = (@@next_id += 1).to_s
      self.sector = sector
      self.round = 0
      self.state = "active"
      self.log = []
    end

    def sector_id
      sector ? sector.id : nil
    end

    def update(attrs)
      attrs.each { |k, v| send("#{k}=", v) }
      self
    end

    def active?
      state == "active"
    end

    def add_log(msg)
      self.log << "R#{round}: #{msg}"
    end
  end

  # No real Redis-backed SpaceCombat existed in the harness before this -
  # Engagements.sector_combats/active_combat had only ever been exercised
  # through the rescue => nil in sector_combats, which quietly swallowed
  # the missing constant. Docking.land/launch's "is this ship in an
  # active engagement" check calls Engagements.combat_for_ship, which
  # depends on the same path - without this double it would silently
  # never trigger in specs, the same blind spot SpaceBodyState closed
  # for Systems.claim above.
  module SpaceCombat
    class << self
      attr_accessor :all

      def create(opts = {})
        combat = TestCombat.new(opts[:sector])
        combat.update(opts.reject { |k, _| k == :sector })
        self.all ||= []
        self.all << combat
        combat
      end

      def reset!
        self.all = []
      end
    end
  end

  # The world the helpers query. Specs register ships here instead of Redis.
  module TestWorld
    class << self
      attr_accessor :ships, :terrain

      def reset!
        self.ships = []
        self.terrain = []
      end
    end
  end
end

# Point the production lookups at the in-memory world.
module AresMUSH
  module Space
    module Ships
      def self.sector_ships(sector)
        return [] if !sector
        TestWorld.ships.select { |s| s.sector_id.to_s == sector.id.to_s }
      end

      def self.sector_terrain(sector)
        return [] if !sector
        TestWorld.terrain.select { |t| t.sector_id.to_s == sector.id.to_s }
      end

      def self.find_ship(name)
        TestWorld.ships.find { |s| s.name.to_s.downcase == "#{name}".downcase }
      end

      def self.find_ship_in_sector(sector, name)
        sector_ships(sector).find { |s| s.name.to_s.downcase == "#{name}".downcase }
      end

      def self.all_ships
        TestWorld.ships
      end
    end

    # Systems.system_ships calls SpaceShip.all directly (not through
    # Ships, which is fully doubled above) - there's no SpaceShip
    # constant in this harness at all, so without this override every
    # caller (ships_at, ships_at_ring, settle_arrivals, web_data's
    # system_ship_entries) was silently hitting Systems' own
    # rescue => nil and getting back an empty list, the same blind spot
    # SpaceBodyState and SpaceCombat closed elsewhere in this file.
    module Systems
      def self.system_ships(system_key)
        return [] if !system_key
        TestWorld.ships.select { |s| s.system_key.to_s == "#{system_key}" && !s.destroyed? }
      end
    end
  end
end

# String helpers the engine adds; the plugin uses them, so the harness
# must provide them too.
class String
  def after(str)
    index = self.index(str)
    index ? self[(index + str.length)..-1] : ""
  end unless method_defined?(:after)

  def titlecase
    split(/[\s_]/).map { |w| w.capitalize }.join(" ")
  end unless method_defined?(:titlecase)
end

module AresMUSH
  # Character lookup by id, backed by whatever the spec registered.
  class Character
    @registry = {}
    class << self
      attr_accessor :registry

      def [](id)
        registry["#{id}"]
      end

      def register(char)
        registry["#{char.id}"] = char
        char
      end

      def reset!
        self.registry = {}
      end
    end
  end
end

# `t` is a top-level method in the engine, callable from anywhere the
# plugin runs. Translations aren't under test; return something readable.
def t(str, **args)
  args.empty? ? str : "#{str}(#{args.map { |k, v| "#{k}=#{v}" }.join(',')})"
end
