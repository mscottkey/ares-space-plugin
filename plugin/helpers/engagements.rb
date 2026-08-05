module AresMUSH
  module Space

    # Combat instances. A sector can hold drifting contacts with no
    # engagement running; combat is the turn structure laid over it.
    module Engagements

      def self.sector_combats(sector)
        return [] if !sector
        SpaceCombat.all.select { |c| c.sector_id.to_s == sector.id.to_s }
      rescue => e
        Global.logger.warn "Space: failed to list combats for sector #{sector.id}: #{e}"
        []
      end

      def self.active_combat(sector)
        sector_combats(sector).select { |c| c.active? }.first
      end

      def self.start(sector)
        existing = active_combat(sector)
        return [ existing, t('space.combat_already_running') ] if existing

        combat = SpaceCombat.create(sector: sector, round: 0, state: "active", log: [])
        [ combat, nil ]
      end

      def self.stop(combat)
        combat.update(state: "resolved")
        Ships.sector_ships(combat.sector).each do |ship|
          Orders.clear(ship)
          ship.update(evade_margin: 0, sweep_range: 0)
        end
      end

      def self.combat_for_ship(ship)
        return nil if !ship || !ship.sector
        active_combat(ship.sector)
      end

      # Announces a round to everyone crewing a ship in the sector,
      # wherever in the game they happen to be standing.
      def self.notify_crews(sector, message)
        Ships.sector_ships(sector).each do |ship|
          ship.stations.values.each do |crew|
            char = Crew.crew_char(crew)
            next if !char
            client = Login.find_game_client(char)
            next if !client
            client.emit message
          end
        end
      end

      # Pushes an update to any portal client watching this sector, over
      # the websocket the portal already maintains - the same mechanism
      # fs3combat uses for combat_activity. Staff and anyone crewing a
      # ship in the sector get it.
      #
      # The message is prefixed with the sector id so the page can ignore
      # traffic for a sector it isn't looking at.
      def self.notify_web(sector, type, message)
        return if !defined?(Global) || !Global.respond_to?(:client_monitor)

        crew_ids = Ships.sector_ships(sector).flat_map do |ship|
          ship.stations.values.map { |crew| Crew.crew_char(crew) }
        end.compact.map { |char| char.id.to_s }

        payload = "#{sector.id}|#{message}"

        Global.client_monitor.notify_web_clients(type, payload, true) do |char|
          char && (crew_ids.include?(char.id.to_s) || char.is_admin?)
        end
      rescue => e
        Global.logger.warn "Space: failed to notify web clients: #{e}"
      end

      # Whether the round is ready to resolve on its own. The POC leaves
      # auto_resolve off and the GM in charge, but the resolver does not
      # care which of the two calls it.
      def self.ready_to_resolve?(sector)
        return false if !SpaceConfig.auto_resolve?
        Orders.ships_awaiting_orders(sector).empty?
      end
    end
  end
end
