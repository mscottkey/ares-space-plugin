module AresMUSH
  module Space

    # Spawning ships and reading their live state.
    module Ships

      # Full scans rather than indexed finds: Ohm indexes drift when
      # reference ids are written as strings in one place and integers in
      # another, and a MUSH never has enough ships for this to matter.
      def self.sector_ships(sector)
        return [] if !sector
        SpaceShip.all.select { |s| s.sector_id.to_s == sector.id.to_s }
      rescue => e
        Global.logger.warn "Space: failed to list ships for sector #{sector.id}: #{e}"
        []
      end

      def self.sector_terrain(sector)
        return [] if !sector
        SpaceTerrain.all.select { |t| t.sector_id.to_s == sector.id.to_s }
      rescue => e
        Global.logger.warn "Space: failed to list terrain for sector #{sector.id}: #{e}"
        []
      end

      def self.find_ship(name)
        return nil if name.nil?
        SpaceShip.all.select { |s| s.name.to_s.downcase == "#{name}".downcase }.first
      end

      # Every ship that exists, regardless of sector or system. Kept as
      # its own method (rather than callers reaching for SpaceShip.all
      # directly) so the spec harness has one seam to redirect at the
      # in-memory world, the same as sector_ships and find_ship above.
      def self.all_ships
        SpaceShip.all.to_a
      end

      def self.find_ship_in_sector(sector, name)
        return nil if name.nil?
        sector_ships(sector).select { |s| s.name.to_s.downcase == "#{name}".downcase }.first
      end

      # The ship a character's orders currently apply to.
      #
      # Prefers Character.current_ship - the ship they last boarded
      # (Boarding.board), authoritative regardless of where they've
      # physically wandered since - so long as they still hold a
      # station there. That "still holds a station" check is what makes
      # this safe now that a character can hold seats on more than one
      # ship at once (fly the fighter, then go back to the capital):
      # without it, the stamp alone can't tell "my active ship" from
      # "a ship I boarded once and never claimed anything on."
      #
      # Falls back to the old full scan for a character who holds a
      # station but never went through space/board at all - a staff
      # assignment via space/crew made directly, or data from before
      # this existed. That scan is what used to be the ONLY path, and
      # picked whichever ship .first happened to return if a character
      # held seats on more than one - silently wrong the moment
      # self-service claiming made that reachable instead of
      # theoretical.
      def self.ship_for_char(char)
        return nil if !char
        key = Crew.char_key(char)

        current = char.current_ship
        return current if current && current.active? && current.stations.values.include?(key)

        all_ships.select { |s| s.active? && s.stations.values.include?(key) }.first
      end

      def self.station_for_char(ship, char)
        return nil if !ship || !char
        key = "char:#{char.id}"
        ship.stations.select { |_station, crew| crew == key }.keys.first
      end

      # Builds the live section state for a class: every section gets its
      # current and maximum pools so damage and regen have a ceiling.
      def self.build_sections(class_data)
        sections = {}
        (class_data["sections"] || {}).each do |name, data|
          shields = (data["shields"] || 0).to_i
          hull = (data["hull"] || 1).to_i
          sections["#{name}"] = {
            "shields" => shields,
            "max_shields" => shields,
            "hull" => hull,
            "max_hull" => hull,
            "systems" => (data["systems"] || []).map { |s| "#{s}" }
          }
        end
        sections
      end

      def self.build_ammo(class_data)
        ammo = {}
        (class_data["hardpoints"] || []).each_with_index do |hp, i|
          rounds = SpaceConfig.weapon_stat(hp["weapon"], "ammo")
          ammo["#{i}"] = rounds.to_i if rounds
        end
        ammo
      end

      # Spawns a ship. Returns [ship, nil] or [nil, error_message].
      def self.spawn(sector, class_name, name, opts = {})
        canonical = SpaceConfig.ship_class_name(class_name)
        class_data = SpaceConfig.ship_class(class_name)
        return [ nil, t('space.unknown_ship_class', name: class_name) ] if !class_data

        return [ nil, t('space.ship_name_taken', name: name) ] if find_ship(name)

        geometry = sector.geometry
        facing = Geometry.parse_facing(geometry, opts[:facing]) || 0
        x = opts[:x] || (sector.width.to_i / 2)
        y = opts[:y] || (sector.height.to_i / 2)

        ship = SpaceShip.create(
          name: name,
          ship_class: canonical,
          # Classes carry a default faction so a spawned hull reads as UCC
          # or Swarm on the plot without the GM setting it every time.
          faction: opts[:faction] || class_data["faction"] || "Unknown",
          sector: sector,
          x: x,
          y: y,
          facing: facing,
          speed: 0,
          sections: build_sections(class_data),
          ammo: build_ammo(class_data),
          stations: {},
          orders: {},
          status: "active"
        )
        [ ship, nil ]
      end

      # ---------------------------------------------------------------
      # Weapons
      # ---------------------------------------------------------------

      def self.hardpoint(ship, index)
        ship.hardpoints[index.to_i]
      end

      def self.hardpoint_summary(ship)
        ship.hardpoints.each_with_index.map do |hp, i|
          weapon = SpaceConfig.weapon(hp["weapon"]) || {}
          rounds = ship.ammo["#{i}"]
          {
            index: i,
            arc: hp["arc"],
            weapon: hp["weapon"],
            scale: weapon["scale"],
            damage: weapon["damage"],
            range: weapon["range"],
            ammo: rounds
          }
        end
      end

      def self.ammo_remaining(ship, index)
        ship.ammo["#{index}"]
      end

      def self.spend_ammo(ship, index)
        remaining = ship.ammo["#{index}"]
        return true if remaining.nil?
        return false if remaining.to_i <= 0
        ammo = ship.ammo.to_h
        ammo["#{index}"] = remaining.to_i - 1
        ship.update(ammo: ammo)
        true
      end

      # ---------------------------------------------------------------
      # Damage
      # ---------------------------------------------------------------

      def self.apply_damage(ship, arc, damage, systems_only = false)
        section_name = ship.section_for_arc(arc)
        result = Rules.apply_damage(ship.sections, section_name, damage, systems_only)
        ship.update(sections: result[:sections])

        if Rules.destroyed?(ship.sections, SpaceConfig.destruction_fraction)
          ship.update(status: "destroyed")
          result[:events] << { type: :destroyed, ship: ship.name }
        end

        result[:events]
      end

      def self.repair(ship, section_name, amount)
        sections = Rules.deep_copy_sections(ship.sections)
        section = sections["#{section_name}"]
        return false if !section
        max = (section["max_hull"] || 0).to_i
        section["hull"] = [ section["hull"].to_i + amount.to_i, max ].min
        ship.update(sections: sections)
        true
      end

      def self.regen_shields(ship, skip_sections = [])
        amount = SpaceConfig.shield_regen
        return if amount <= 0
        ship.update(sections: Rules.regen_shields(ship.sections, amount, skip_sections))
      end

      def self.damaged_sections(ship)
        ship.sections.select { |_name, s| s["hull"].to_i < (s["max_hull"] || 0).to_i }.keys
      end

      # ---------------------------------------------------------------
      # Strain
      # ---------------------------------------------------------------

      # Returns the Rules events (e.g. :strained_out), so callers can tell
      # whether this blow was the one that put the ship adrift.
      def self.apply_strain(ship, amount)
        return [] if amount.to_i <= 0
        result = Rules.apply_strain(ship.strain.to_i, amount, ship.strain_threshold)
        ship.update(strain: result[:strain])
        result[:events]
      end

      def self.recover_strain(ship, amount)
        return if amount.to_i <= 0
        ship.update(strain: Rules.recover_strain(ship.strain.to_i, amount))
      end

      # ---------------------------------------------------------------
      # Movement
      # ---------------------------------------------------------------

      def self.place(ship, x, y, facing = nil)
        updates = { x: x.to_i, y: y.to_i }
        updates[:facing] = facing.to_i if facing
        ship.update(updates)
      end

      def self.clamp_to_sector(sector, pos)
        [
          [ [ pos[0], 0 ].max, sector.width.to_i - 1 ].min,
          [ [ pos[1], 0 ].max, sector.height.to_i - 1 ].min
        ]
      end
    end
  end
end
