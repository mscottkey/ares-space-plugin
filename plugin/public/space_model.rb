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

    # Where in the astrography this tactical grid sits. A sector is only
    # spun up when there's a fight; anchoring it to a body lets the
    # system map show where the shooting is.
    attribute :system_key
    attribute :body_key

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
    # A whole-ship "stressed, not broken" pool, separate from the
    # per-section shields/hull above - see ShipBehavior#strain_threshold
    # and Rules.apply_strain/recover_strain/strained_out?.
    attribute :strain, :type => DataType::Integer, :default => 0
    # Extra sensor reach bought by a successful sweep, cleared each round.
    attribute :sweep_range, :type => DataType::Integer, :default => 0

    attribute :status, :default => "active"   # active | destroyed | derelict | docked
    attribute :destroyed_reason

    # A ship's normal position: a body in a star system. The sector
    # below is only set while it's in a tactical engagement.
    attribute :system_key
    index :system_key
    attribute :location_key

    # An alternative to location_key: a ship can hold position in a bare
    # orbital ring instead of at a body - a capital ship staging between
    # planets, or a station with no world of its own. Mutually exclusive
    # with location_key, the same way carrier is mutually exclusive with
    # having an independent position at all - see Systems.set_course/
    # settle_arrival and space/station. system_angle has no config
    # source of truth the way a body's angle does; it's just wherever
    # the ship was put (see Systems.ring_angle_for).
    attribute :system_ring, :type => DataType::Integer
    attribute :system_angle, :type => DataType::Float

    # Set only while under way. Arrival is worked out lazily from these
    # rather than by any scheduled task - see Systems.settle_arrival.
    attribute :destination_key
    attribute :departed_at, :type => DataType::Time
    attribute :travel_seconds, :type => DataType::Integer, :default => 0

    reference :sector, "AresMUSH::SpaceSector"
    index :sector_id
    reference :carrier, "AresMUSH::SpaceShip"

    # The one room external exits connect to - where boarding always
    # lands you, and later (once docking retargets exits) the anchor an
    # exit points at. Created lazily on first board, not at spawn: most
    # ships spawned for a test fight are never boarded at all.
    reference :entry_room, "AresMUSH::Room"

    # Every room a character can run ship commands from - always
    # includes entry_room, and staff/the owner can add more by tagging a
    # room while standing in it. Deliberately unlabeled: bridge,
    # engineering, entry are all equally "on duty" as far as any command
    # cares, because in an actual scene everyone ends up in the same
    # room anyway. What the set excludes matters more than what it
    # contains - a private cabin or the mess hall built off the same
    # interior is real space aboard the ship that doesn't count.
    attribute :operational_rooms, :type => DataType::Array, :default => []

    # Optional. Set, this character can bump anyone off a station on
    # this ship the way staff always could; unset, only staff can force
    # a reassignment and claiming an open seat is first-come.
    reference :owner, "AresMUSH::Character"

    # char key => room id the character was in before boarding, so
    # space/disembark returns them there instead of guessing. Scoped to
    # the ship rather than the character so this plugin never has to
    # touch the core Character model.
    attribute :boarded_from, :type => DataType::Hash, :default => {}

    # The "board me" exit at wherever this ship is CURRENTLY docked, if
    # anywhere - see Docking. Tracked here rather than found by name/
    # source each time because more than one ship can be docked at the
    # same landing room at once, each with its own exit named after it;
    # this is what tells undocking which one is this ship's to remove.
    reference :dock_exit, "AresMUSH::Exit"

    # A landing room that belongs to THIS ship rather than to a body -
    # only meaningful if class_data["hangar"] is true (see
    # ShipBehavior#hangar?). Created lazily on first use, same as
    # entry_room; a fighter or a freighter with no flight deck never
    # gets one.
    reference :hangar_room, "AresMUSH::Room"

    def save_upcase
      self.name_upcase = self.name ? self.name.upcase : nil
    end

    def in_transit?
      !self.destination_key.to_s.empty? && !self.departed_at.nil?
    end

    def eta_seconds
      Space::Astro.seconds_remaining(self.departed_at, self.travel_seconds.to_i)
    end
  end

  # Who holds a body right now. The astrography itself is static config;
  # only control changes during play, so only control lives here.
  class SpaceBodyState < Ohm::Model
    include ObjectModel

    attribute :system_key
    index :system_key
    attribute :body_key
    attribute :faction
    attribute :notes

    # Optional. Most bodies are empty rock with nowhere to physically
    # dock - this is only set for the ones staff have actually built a
    # landing room for. A ship can still be "at" any body either way
    # (that's just system_key/location_key); this only decides whether
    # arriving there also opens a walk-in door (see Docking).
    reference :landing_room, "AresMUSH::Room"
  end

  # Reopening core's Character, the same way fs3combat/places/scenes/
  # describe/rooms all reopen core's Room from their own public/ files -
  # an established, safe pattern, not a fork.
  #
  # Authoritative, not a room lookup: "which ship are you on" is "which
  # ship did you last board," full stop, until you board a different one
  # or disembark. Wandering off through an ordinary exit without
  # disembarking properly does NOT clear this - you're still "on" that
  # ship as far as any order is concerned, the same way forgetting to
  # sign out of a system doesn't log you out. Boarding.aboard? (a
  # physical room check) is a separate, non-authoritative signal for
  # flagging that mismatch somewhere later - a "?" next to a status
  # line, say - never something that overrides this.
  class Character
    reference :current_ship, "AresMUSH::SpaceShip"
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
