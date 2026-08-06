$:.unshift File.dirname(__FILE__)

module AresMUSH
  module Space

    def self.plugin_dir
      File.dirname(__FILE__)
    end

    def self.shortcuts
      Global.read_config('space', 'shortcuts') || {}
    end

    def self.get_cmd_handler(client, cmd, enactor)
      case cmd.root
      when 'space'
        case cmd.switch

        # Consoles. The system map is the default view: space is where
        # ships live, and a tactical sector is the exception you drop
        # into when there's a fight.
        when 'system', 'map', nil
          return SpaceSystemCmd
        when 'tac', 'tactical'
          return SpaceTacCmd
        when 'status'
          return SpaceStatusCmd
        when 'contacts'
          return SpaceContactsCmd
        when 'orders'
          return SpaceOrdersCmd

        # Crew orders
        when 'helm'
          return SpaceHelmCmd
        when 'evade'
          return SpaceEvadeCmd
        when 'hold'
          return SpaceHoldCmd
        when 'fire'
          return SpaceFireCmd
        when 'repair'
          return SpaceRepairCmd
        when 'sweep'
          return SpaceSweepCmd
        when 'clear'
          return SpaceClearCmd
        when 'travel', 'nav'
          return SpaceTravelCmd
        when 'board'
          return SpaceBoardCmd
        when 'disembark'
          return SpaceDisembarkCmd
        when 'tag'
          return SpaceTagCmd

        # GM
        when 'sector'
          return SpaceSectorCmd
        when 'sectors'
          return SpaceSectorsCmd
        when 'spawn'
          return SpaceSpawnCmd
        when 'place'
          return SpacePlaceCmd
        when 'crew'
          return SpaceCrewCmd
        when 'terrain'
          return SpaceTerrainCmd
        when 'claim'
          return SpaceClaimCmd
        when 'anchor'
          return SpaceAnchorCmd
        when 'station'
          return SpaceStationCmd
        when 'start'
          return SpaceStartCmd
        when 'resolve'
          return SpaceResolveCmd
        when 'end'
          return SpaceEndCmd
        when 'remove'
          return SpaceRemoveCmd
        when 'uninstall'
          return SpaceUninstallCmd

        else
          client.emit_failure t('space.unknown_command')
          return nil
        end
      end
      return nil
    end

    def self.get_event_handler(event_name)
      nil
    end

    # Emits the result of Orders.issue to a telnet client. The web portal
    # hands the same structure back as JSON, so both surfaces report a
    # given order identically.
    def self.emit_order_result(client, result)
      if result[:error]
        client.emit_failure result[:error]
        return
      end
      (result[:warnings] || []).each { |w| client.emit_ooc w }
      client.emit_success result[:message] if result[:message]
    end

    def self.get_web_request_handler(request)
      case request.cmd
      when "spaceTactical"
        return SpaceTacticalRequestHandler
      when "spaceSectors"
        return SpaceSectorsRequestHandler
      when "spaceShip"
        return SpaceShipRequestHandler
      when "spaceOrder"
        return SpaceOrderRequestHandler
      when "spaceResolve"
        return SpaceResolveRequestHandler
      when "spaceSystem"
        return SpaceSystemRequestHandler
      when "spaceTravel"
        return SpaceTravelRequestHandler
      end
      return nil
    end

    # Called by the engine's PluginManager after the plugin loads.
    # (Note: an instance method named `load` is never called by core.)
    def self.init_plugin
      Global.logger.info "Space plugin loaded."
    end

    # Surfaced by `manage/checkconfig`. Catches the two mistakes that
    # would otherwise show up as silent one-die rolls mid-battle.
    def self.check_config
      errors = []

      if !Space::Crew.fs3_available?
        errors << "space: FS3Skills is unavailable. This plugin rolls all crew actions through core FS3."
      else
        (Space::SpaceConfig.station_skills || {}).each do |station, ability|
          if !Space::Crew.known_ability?(ability)
            errors << "space: station '#{station}' maps to ability '#{ability}', which FS3 does not define. It will roll untrained dice."
          end
        end
      end

      (Space::SpaceConfig.ship_classes || {}).each do |name, data|
        sections = data["sections"] || {}
        errors << "space: ship class '#{name}' has no sections." if sections.empty?

        (data["hardpoints"] || []).each do |hp|
          if !Space::SpaceConfig.weapon(hp["weapon"])
            errors << "space: ship class '#{name}' mounts unknown weapon '#{hp['weapon']}'."
          end
          if ![ "forward", "aft", "port", "starboard" ].include?("#{hp['arc']}")
            errors << "space: ship class '#{name}' has a hardpoint in unknown arc '#{hp['arc']}'."
          end
        end
      end

      errors
    end
  end
end
