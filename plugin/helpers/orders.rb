module AresMUSH
  module Space

    # Orders are stored on the ship and cleared when the round resolves.
    #
    # They are keyed by role rather than by station so a single-seat
    # fighter's pilot can both fly and shoot in the same round, while a
    # capital's helm and gunnery crew act independently.
    module Orders

      ROLES = [ :helm, :fire, :engineering, :sensors ]

      # Which station rolls for a given role on this ship. Capitals have
      # dedicated crew; on small craft the pilot does everything.
      def self.station_for_role(ship, role)
        stations = (ship.class_data["stations"] || []).map { |s| "#{s}" }

        preferred = case role
                    when :helm then [ "helm", "pilot" ]
                    when :fire then [ "gunnery", "pilot" ]
                    when :engineering then [ "engineering", "pilot" ]
                    when :sensors then [ "sensors", "pilot", "helm" ]
                    else [ "pilot" ]
                    end

        preferred.find { |s| stations.include?(s) } || stations.first || "pilot"
      end

      def self.set(ship, key, order)
        orders = ship.orders.to_h
        orders["#{key}"] = order
        ship.update(orders: orders)
      end

      def self.get(ship, key)
        ship.orders["#{key}"]
      end

      def self.clear(ship)
        ship.update(orders: {})
      end

      def self.any?(ship)
        !ship.orders.empty?
      end

      # ---------------------------------------------------------------
      # Helm
      # ---------------------------------------------------------------

      def self.set_move(ship, heading, speed)
        set(ship, "helm", { "action" => "move", "heading" => heading.to_i, "speed" => speed.to_i })
      end

      def self.set_evade(ship)
        set(ship, "helm", { "action" => "evade" })
      end

      def self.set_hold(ship)
        set(ship, "helm", { "action" => "hold" })
      end

      # ---------------------------------------------------------------
      # Weapons
      # ---------------------------------------------------------------

      # Several hardpoints can fire in one round; each is its own order.
      def self.add_fire(ship, target_name, hardpoint_index)
        orders = ship.orders.to_h
        fires = orders["fire"] || []
        fires << { "target" => target_name, "hardpoint" => hardpoint_index.to_i }
        orders["fire"] = fires
        ship.update(orders: orders)
      end

      def self.fire_orders(ship)
        ship.orders["fire"] || []
      end

      def self.clear_fire(ship)
        orders = ship.orders.to_h
        orders.delete("fire")
        ship.update(orders: orders)
      end

      # Checks a fire order now so the player hears about it while they
      # can still change it, rather than at resolution.
      # Returns nil if it's legal, or an error string.
      def self.validate_fire(ship, target, hardpoint_index)
        hp = Ships.hardpoint(ship, hardpoint_index)
        return t('space.no_such_hardpoint', index: hardpoint_index) if !hp

        weapon = SpaceConfig.weapon(hp["weapon"])
        return t('space.unknown_weapon', name: hp["weapon"]) if !weapon

        rounds = Ships.ammo_remaining(ship, hardpoint_index)
        return t('space.out_of_ammo', weapon: hp["weapon"]) if rounds && rounds.to_i <= 0

        return t('space.weapons_offline') if !ship.small_craft? && !ship.system_online?("weapons")

        return t('space.target_not_found', name: target) if !target

        geometry = ship.geometry
        distance = Geometry.distance(geometry, ship.pos, target.pos)
        if Rules.range_mod(distance, weapon["range"], SpaceConfig.range_mods).nil?
          return t('space.out_of_range', weapon: hp["weapon"], range: weapon["range"], distance: distance)
        end

        nil
      end

      # ---------------------------------------------------------------
      # Engineering and sensors
      # ---------------------------------------------------------------

      def self.set_repair(ship, section)
        set(ship, "engineering", { "action" => "repair", "section" => "#{section}" })
      end

      def self.set_sweep(ship)
        set(ship, "sensors", { "action" => "sweep" })
      end

      # ---------------------------------------------------------------
      # Readiness
      # ---------------------------------------------------------------

      # A ship is waiting on its crew if anyone is aboard and nothing has
      # been ordered. Unmanned NPC hulls never block the round.
      def self.awaiting_orders?(ship)
        return false if !ship.active?
        return false if ship.stations.empty?
        ship.orders.empty?
      end

      def self.ships_awaiting_orders(sector)
        Ships.sector_ships(sector).select { |s| awaiting_orders?(s) }
      end
    end
  end
end
