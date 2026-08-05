module AresMUSH

  # A region of space with its own geometry. Persistent and independent of
  # the room grid: nobody walks into a sector, they read it off instruments.
  class SpaceSector < Ohm::Model
    include ObjectModel
    include FindByName

    # FindByName looks sectors up by name_upcase, so the attribute, the
    # index and the before_save hook all have to be here or every lookup
    # silently finds nothing.
    attribute :name
    attribute :name_upcase
    index :name_upcase
    before_save :save_upcase

    attribute :description
    attribute :geometry, :default => "square"   # square | hex
    attribute :width, :type => DataType::Integer, :default => 20
    attribute :height, :type => DataType::Integer, :default => 20

    # The third argument is load-bearing. Ohm derives a collection's
    # foreign key from the DECLARING class, so without it these would
    # look for `space_sector_id` while the references below actually
    # write `sector_id` - and every use would raise IndexNotFound.
    collection :ships, "AresMUSH::SpaceShip", :sector
    collection :terrain, "AresMUSH::SpaceTerrain", :sector
    collection :combats, "AresMUSH::SpaceCombat", :sector

    before_delete :delete_contents

    def save_upcase
      self.name_upcase = self.name ? self.name.upcase : nil
    end

    def delete_contents
      ships.each { |s| s.delete }
      terrain.each { |t| t.delete }
      combats.each { |c| c.delete }
    end

    def hex?
      Space::Geometry.hex?(self.geometry)
    end

    def active_ships
      Space::Ships.sector_ships(self).select { |s| s.active? }
    end

    def active_combat
      Space::Engagements.sector_combats(self).select { |c| c.active? }.first
    end
  end

  # Asteroid fields, debris, wrecks - terrain that bends sensors and guns.
  class SpaceTerrain < Ohm::Model
    include ObjectModel

    attribute :terrain_type
    attribute :name
    attribute :x, :type => DataType::Integer, :default => 0
    attribute :y, :type => DataType::Integer, :default => 0
    attribute :radius, :type => DataType::Integer, :default => 0

    reference :sector, "AresMUSH::SpaceSector"
    index :sector_id

    def pos
      [ self.x.to_i, self.y.to_i ]
    end

    def covers?(geometry, position)
      Space::Geometry.distance(geometry, self.pos, position) <= self.radius.to_i
    end
  end

  class SpaceShip < Ohm::Model
    include ObjectModel
    include FindByName

    # Everything derived from these attributes lives in ShipBehavior, so
    # the resolver can be exercised against an in-memory double in the
    # specs without the two definitions drifting apart.
    include Space::ShipBehavior

    attribute :name
    attribute :name_upcase
    index :name_upcase
    before_save :save_upcase

    attribute :ship_class
    attribute :faction, :default => "Unknown"

    attribute :x, :type => DataType::Integer, :default => 0
    attribute :y, :type => DataType::Integer, :default => 0
    attribute :facing, :type => DataType::Integer, :default => 0
    attribute :speed, :type => DataType::Integer, :default => 0

    # section name => { shields, max_shields, hull, max_hull, systems }
    attribute :sections, :type => DataType::Hash, :default => {}
    # station name => "char:<id>" or "npc:<rating>"
    attribute :stations, :type => DataType::Hash, :default => {}
    # role => order hash, cleared each time the round resolves
    attribute :orders, :type => DataType::Hash, :default => {}
    # hardpoint index => shots remaining, for weapons with ammo
    attribute :ammo, :type => DataType::Hash, :default => {}

    # Successes the pilot banked this round; spent defending against
    # every attack until the round resolves.
    attribute :evade_margin, :type => DataType::Integer, :default => 0
    # Extra sensor reach bought by a successful sweep, cleared each round.
    attribute :sweep_range, :type => DataType::Integer, :default => 0

    attribute :status, :default => "active"   # active | destroyed | derelict | docked
    attribute :destroyed_reason

    reference :sector, "AresMUSH::SpaceSector"
    index :sector_id
    reference :carrier, "AresMUSH::SpaceShip"

    def save_upcase
      self.name_upcase = self.name ? self.name.upcase : nil
    end
  end

  # An engagement in a sector. Sectors can hold drifting contacts with no
  # combat running; combat is the explicit turn structure on top.
  class SpaceCombat < Ohm::Model
    include ObjectModel

    attribute :round, :type => DataType::Integer, :default => 0
    attribute :state, :default => "active"     # active | resolved
    attribute :log, :type => DataType::Array, :default => []
    attribute :last_report

    reference :sector, "AresMUSH::SpaceSector"
    index :sector_id

    def active?
      self.state == "active"
    end

    def add_log(msg)
      entries = self.log || []
      entries << "R#{self.round}: #{msg}"
      self.update(log: entries.last(200))
    end
  end
end
