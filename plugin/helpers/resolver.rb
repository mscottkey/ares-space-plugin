module AresMUSH
  module Space

    # Resolves one combat round.
    #
    # This is deliberately a plain function over a combat: the GM command
    # calls it, and later a scheduled tick or an auto-resolve trigger can
    # call exactly the same thing without the resolution logic caring who
    # pulled the trigger.
    module Resolver

      # Returns a report hash the templates render and the log stores.
      def self.resolve_round(combat)
        sector = combat.sector
        return { error: t('space.combat_has_no_sector') } if !sector

        geometry = sector.geometry
        bias = SpaceConfig.arc_diagonal_bias
        ships = Ships.sector_ships(sector).select { |s| s.active? }

        report = {
          round: combat.round.to_i + 1,
          sector: sector.name,
          sweeps: [],
          moves: [],
          evades: [],
          attacks: [],
          engineering: [],
          destroyed: [],
          strained_out: []
        }

        reset_round_state(ships)

        resolve_sweeps(ships, report)
        resolve_evasion(ships, report)
        resolve_movement(sector, geometry, ships, report)
        resolve_attacks(sector, geometry, bias, ships, report)
        resolve_engineering(ships, report)

        finish_round(combat, ships, report)
        report
      end

      # ---------------------------------------------------------------
      # Phases
      # ---------------------------------------------------------------

      def self.reset_round_state(ships)
        ships.each { |ship| ship.update(evade_margin: 0) }
      end

      def self.resolve_sweeps(ships, report)
        ships.each do |ship|
          order = Orders.get(ship, "sensors")
          next if !order || order["action"] != "sweep"

          roll = Sensors.sweep(ship)
          entry = {
            ship: ship.name,
            roller: roll[:roller],
            successes: roll[:successes],
            range: roll[:range]
          }
          entry[:detail] = roll[:detail] if roll[:detail]
          report[:sweeps] << entry
          apply_roll_strain(ship, roll, report)
        end
      end

      def self.resolve_evasion(ships, report)
        ships.each do |ship|
          order = Orders.get(ship, "helm")
          next if !order || order["action"] != "evade"

          station = Orders.station_for_role(ship, :helm)
          roll = Crew.roll_station(ship, station, ship.agility)
          margin = roll[:successes].to_i
          ship.update(evade_margin: margin)

          entry = {
            ship: ship.name,
            roller: roll[:roller],
            margin: margin,
            success_title: roll[:success_title]
          }
          entry[:detail] = roll[:detail] if roll[:detail]
          report[:evades] << entry
          apply_roll_strain(ship, roll, report)
        end
      end

      # Everyone moves at once, so orders are given against the positions
      # at the top of the round. A strained-out ship is adrift: skipped
      # here entirely, whatever helm order it was given.
      def self.resolve_movement(sector, geometry, ships, report)
        ships.each do |ship|
          next if ship.strained_out?

          order = Orders.get(ship, "helm")
          next if !order || order["action"] != "move"

          from = ship.pos
          old_facing = ship.facing.to_i

          requested = order["heading"].to_i
          new_facing = clamp_turn(geometry, old_facing, requested, ship.agility)

          speed = [ order["speed"].to_i, effective_max_speed(ship) ].min
          speed = [ speed, 0 ].max

          destination, blocked = advance(sector, geometry, ships, ship, from, new_facing, speed)

          Ships.place(ship, destination[0], destination[1], new_facing)
          travelled = Geometry.distance(geometry, from, destination)
          ship.update(speed: travelled)

          report[:moves] << {
            ship: ship.name,
            from: from,
            to: destination,
            facing: Geometry.facing_name(geometry, new_facing),
            requested_facing: Geometry.facing_name(geometry, requested),
            turn_limited: new_facing != requested,
            speed: travelled,
            speed_limited: speed < order["speed"].to_i,
            blocked: blocked
          }
        end
      end

      # Small ships shoot first: nimble craft get their shot off before a
      # capital's heavy batteries can bear. A strained-out ship is adrift
      # and cannot fire at all, whatever it was ordered to shoot.
      #
      # strained_out? is checked before EACH order, not once per ship: a
      # multi-hardpoint ship's own first shot can botch and push it over
      # threshold mid-phase (apply_roll_strain runs inside
      # resolve_single_attack), and a later hardpoint must not still fire
      # in that same round just because the ship started it able to.
      def self.resolve_attacks(sector, geometry, bias, ships, report)
        shooters = ships.sort_by { |s| [ s.silhouette, s.name.to_s ] }

        shooters.each do |ship|
          next if !ship.active?

          Orders.fire_orders(ship).each do |order|
            next if ship.strained_out?

            result = resolve_single_attack(sector, geometry, bias, ship, order, report)
            next if !result
            report[:attacks] << result
            if result[:destroyed]
              report[:destroyed] << result[:target]
            end
          end
        end
      end

      def self.resolve_single_attack(sector, geometry, bias, ship, order, report)
        target = Ships.find_ship_in_sector(sector, order["target"])
        hardpoint_index = order["hardpoint"].to_i
        hp = Ships.hardpoint(ship, hardpoint_index)

        return { attacker: ship.name, target: order["target"], error: t('space.target_gone') } if !target
        return { attacker: ship.name, target: target.name, error: t('space.no_such_hardpoint', index: hardpoint_index) } if !hp

        weapon_name = hp["weapon"]
        weapon = SpaceConfig.weapon(weapon_name) || {}

        if !target.active?
          return { attacker: ship.name, target: target.name, weapon: weapon_name,
                   error: t('space.target_already_down') }
        end

        # Arcs and ranges are checked against where everyone ended up
        # after movement, not where they were when orders were given.
        distance = Geometry.distance(geometry, ship.pos, target.pos)
        range_mod = Rules.range_mod(distance, weapon["range"], SpaceConfig.range_mods)
        if range_mod.nil?
          return { attacker: ship.name, target: target.name, weapon: weapon_name,
                   error: t('space.out_of_range', weapon: weapon_name,
                            range: weapon["range"], distance: distance) }
        end

        # Movement stops ships stacking, but a GM can place two in one
        # cell. Co-located there is no bearing, so rather than deadlock
        # the fight, treat point-blank contact as bearing on everything.
        firing_arc = Geometry.arc(geometry, ship.pos, ship.facing, target.pos, bias)
        firing_arc = hp["arc"].to_s.to_sym if firing_arc.nil?

        if "#{firing_arc}" != "#{hp['arc']}"
          return { attacker: ship.name, target: target.name, weapon: weapon_name,
                   error: t('space.wrong_arc', arc: hp["arc"], actual: firing_arc || "none") }
        end

        return { attacker: ship.name, target: target.name, weapon: weapon_name,
                 error: t('space.out_of_ammo', weapon: weapon_name) } if !Ships.spend_ammo(ship, hardpoint_index)

        terrain_mod = Sensors.targeting_mod_between(sector, ship.pos, target.pos)

        modifier = Rules.attack_modifier(
          attacker_sil: ship.silhouette,
          target_sil: target.silhouette,
          weapon_scale: weapon["scale"],
          silhouette_clamp: SpaceConfig.silhouette_clamp,
          scale_rules: SpaceConfig.scale_rules,
          range_mod: range_mod,
          terrain_mod: terrain_mod
        )

        station = Orders.station_for_role(ship, :fire)
        roll = Crew.roll_station(ship, station, modifier)
        successes = roll[:successes].to_i
        evade = target.evade_margin.to_i
        net = Rules.net_successes(successes, evade)

        result = {
          attacker: ship.name,
          target: target.name,
          weapon: weapon_name,
          roller: roll[:roller],
          modifier: modifier,
          successes: successes,
          evade: evade,
          net: net,
          distance: distance,
          arc: firing_arc
        }
        result[:detail] = roll[:detail] if roll[:detail]
        apply_roll_strain(ship, roll, report)

        if !Rules.hit?(successes, evade, SpaceConfig.hit_threshold)
          result[:hit] = false
          return result
        end

        result[:hit] = true

        base = weapon["damage"].to_i + Rules.damage_bonus(net)
        scaled = Rules.damage_for_scale(base, weapon["scale"], target.silhouette, SpaceConfig.scale_rules)

        # The section that takes it is the one facing the shooter.
        struck_arc = Geometry.arc(geometry, target.pos, target.facing, ship.pos, bias) || :forward
        section = target.section_for_arc(struck_arc)

        events = Ships.apply_damage(target, struck_arc, scaled[:damage], scaled[:systems_only])

        result[:damage] = scaled[:damage]
        result[:systems_only] = scaled[:systems_only]
        result[:struck_arc] = struck_arc
        result[:section] = section
        result[:events] = events
        result[:destroyed] = target.destroyed?
        result[:systems_lost] = events.select { |e| e.is_a?(Hash) && e[:type] == :section_destroyed }
                                      .flat_map { |e| e[:systems] || [] }
        result
      end

      # A strained-out ship still rolls engineering - being adrift is
      # exactly when you want the engineer working, and venting strain is
      # how it stops being adrift at all.
      def self.resolve_engineering(ships, report)
        ships.each do |ship|
          order = Orders.get(ship, "engineering")
          next if !order || ![ "repair", "vent" ].include?(order["action"])

          station = Orders.station_for_role(ship, :engineering)
          roll = Crew.roll_station(ship, station)
          successes = roll[:successes].to_i

          entry = { ship: ship.name, roller: roll[:roller], successes: successes }

          if order["action"] == "repair"
            repaired = 0
            if successes > 0
              repaired = successes
              Ships.repair(ship, order["section"], repaired)
            end
            entry[:section] = order["section"]
            entry[:repaired] = repaired
          else
            vented = 0
            if successes > 0
              vented = successes
              Ships.recover_strain(ship, vented)
            end
            entry[:vented] = vented
          end

          entry[:detail] = roll[:detail] if roll[:detail]
          report[:engineering] << entry
          apply_roll_strain(ship, roll, report)
        end
      end

      def self.finish_round(combat, ships, report)
        struck = {}
        report[:attacks].each do |a|
          next if !a[:hit]
          (struck[a[:target]] ||= []) << a[:section]
        end

        ships.each do |ship|
          if ship.active?
            Ships.regen_shields(ship, struck[ship.name] || [])
            Ships.recover_strain(ship, SpaceConfig.strain_regen)
          end
          Orders.clear(ship)
          ship.update(sweep_range: 0)
        end

        combat.update(round: report[:round])
        combat.add_log(summarize(report))
        combat.update(last_report: summarize(report))
      end

      # ---------------------------------------------------------------
      # Helpers
      # ---------------------------------------------------------------

      # Walks the ship forward a cell at a time, stopping short of the
      # sector edge and of anything already sitting in a cell.
      #
      # Without this, ships stack. Fly onto a target and the two share a
      # position, which leaves no bearing between them - so no hardpoint
      # can bear and the fight deadlocks. Closing to contact is the first
      # thing a pilot tries, so it gets handled here rather than papered
      # over at the firing step.
      #
      # Returns [ destination, blocked? ].
      def self.advance(sector, geometry, ships, ship, from, facing, speed)
        occupied = ships.reject { |s| s.id == ship.id || !s.active? }
                        .map { |s| s.pos }

        position = from
        blocked = false

        speed.to_i.times do
          step = Geometry.translate(geometry, position, facing, 1)

          if Ships.clamp_to_sector(sector, step) != step
            blocked = true
            break
          end

          if occupied.include?(step)
            blocked = true
            break
          end

          position = step
        end

        [ position, blocked ]
      end

      # A ship can only swing its nose so far in a round; ask for more and
      # it turns as far as it can toward the heading you wanted.
      def self.clamp_turn(geometry, from_facing, to_facing, agility)
        allowed = agility.to_i
        cost = Geometry.turn_cost(geometry, from_facing, to_facing)
        return to_facing if cost <= allowed
        return from_facing if allowed <= 0

        count = Geometry.facing_count(geometry)
        clockwise = (to_facing.to_i - from_facing.to_i) % count
        counter = (from_facing.to_i - to_facing.to_i) % count

        if clockwise <= counter
          (from_facing.to_i + allowed) % count
        else
          (from_facing.to_i - allowed) % count
        end
      end

      # The one place a roll's result becomes strain on the acting ship's
      # own hull - whether the adapter spent net threat into :strain (the
      # FFG hook), the roll botched (successes < 0, config
      # strain.on_botch), or both. Every phase that rolls funnels through
      # here rather than reimplementing it.
      def self.apply_roll_strain(ship, roll, report)
        amount = roll[:strain].to_i
        amount += SpaceConfig.strain_on_botch if roll[:successes].to_i < 0
        return if amount <= 0

        events = Ships.apply_strain(ship, amount)
        report[:strained_out] << ship.name if events.include?(:strained_out)
      end

      def self.effective_max_speed(ship)
        return ship.max_speed if ship.small_craft?
        return 0 if !ship.system_online?("engines")
        ship.max_speed
      end

      def self.summarize(report)
        hits = report[:attacks].count { |a| a[:hit] }
        shots = report[:attacks].count { |a| a.key?(:hit) }
        parts = [ "#{shots} shot(s), #{hits} hit(s)" ]
        parts << "#{report[:moves].count} moved" if report[:moves].any?
        parts << "strained out: #{report[:strained_out].join(', ')}" if report[:strained_out].any?
        parts << "destroyed: #{report[:destroyed].join(', ')}" if report[:destroyed].any?
        parts.join("; ")
      end
    end
  end
end
