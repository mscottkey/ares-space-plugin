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

      def self.set_vent(ship)
        set(ship, "engineering", { "action" => "vent" })
      end

      def self.set_sweep(ship)
        set(ship, "sensors", { "action" => "sweep" })
      end

      # ---------------------------------------------------------------
      # Issuing orders
      # ---------------------------------------------------------------

      # The single entry point for giving a ship an order, used by both
      # the in-game commands and the web portal so the two cannot drift
      # into behaving differently.
      #
      # Returns { ok:, message:, warnings: [], error: }.
      def self.issue(ship, kind, params = {})
        return failure(t('space.ship_destroyed_order')) if !ship.active? && "#{kind}" != "clear"

        case "#{kind}"
        when "helm"    then issue_helm(ship, params)
        when "evade"   then issue_simple(ship, :evade)
        when "hold"    then issue_simple(ship, :hold)
        when "fire"    then issue_fire(ship, params)
        when "repair"  then issue_repair(ship, params)
        when "vent"    then issue_vent(ship)
        when "sweep"   then issue_sweep(ship)
        when "clear"   then clear(ship) && success(t('space.orders_cleared', ship: ship.name))
        else failure(t('space.unknown_order', kind: kind))
        end
      end

      def self.issue_helm(ship, params)
        facing = Geometry.parse_facing(ship.geometry, params[:heading])
        if facing.nil?
          return failure(t('space.bad_heading',
            heading: params[:heading],
            valid: Geometry.facing_names(ship.geometry).join(', ')))
        end

        warnings = []
        max = Resolver.effective_max_speed(ship)
        speed = params[:speed].nil? ? ship.max_speed : params[:speed].to_i
        if speed > max
          warnings << t('space.speed_capped', requested: speed, max: max)
          speed = max
        end
        speed = 0 if speed < 0

        turn = Geometry.turn_cost(ship.geometry, ship.facing, facing)
        if turn > ship.agility
          warnings << t('space.turn_will_be_limited', agility: ship.agility, needed: turn)
        end

        set_move(ship, facing, speed)
        success(t('space.helm_ordered',
          ship: ship.name,
          heading: Geometry.facing_name(ship.geometry, facing),
          speed: speed), warnings)
      end

      def self.issue_simple(ship, action)
        if action == :evade
          set_evade(ship)
          success(t('space.evade_ordered', ship: ship.name))
        else
          set_hold(ship)
          success(t('space.hold_ordered', ship: ship.name))
        end
      end

      def self.issue_fire(ship, params)
        target = Ships.find_ship_in_sector(ship.sector, params[:target])
        return failure(t('space.target_not_found', name: params[:target])) if !target

        index = params[:hardpoint].nil? ? 0 : params[:hardpoint].to_i
        error = validate_fire(ship, target, index)
        return failure(error) if error

        hp = Ships.hardpoint(ship, index)
        warnings = []
        firing_arc = Geometry.arc(ship.geometry, ship.pos, ship.facing, target.pos,
                                  SpaceConfig.arc_diagonal_bias)
        if "#{firing_arc}" != "#{hp['arc']}"
          warnings << t('space.arc_warning',
            weapon: hp["weapon"], arc: hp["arc"], actual: firing_arc || "none")
        end

        add_fire(ship, target.name, index)
        success(t('space.fire_ordered', weapon: hp["weapon"], target: target.name), warnings)
      end

      def self.issue_repair(ship, params)
        section = "#{params[:section]}".downcase
        if !ship.sections.key?(section)
          return failure(t('space.no_such_section',
            section: section, valid: ship.sections.keys.join(', ')))
        end

        set_repair(ship, section)
        success(t('space.repair_ordered', section: section, ship: ship.name))
      end

      def self.issue_sweep(ship)
        set_sweep(ship)
        success(t('space.sweep_ordered', ship: ship.name))
      end

      def self.issue_vent(ship)
        set_vent(ship)
        success(t('space.vent_ordered', ship: ship.name))
      end

      def self.success(message, warnings = [])
        { ok: true, message: message, warnings: warnings, error: nil }
      end

      def self.failure(error)
        { ok: false, message: nil, warnings: [], error: error }
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
