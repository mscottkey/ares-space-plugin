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
        when 'vent'
          return SpaceVentCmd
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
        when 'take'
          return SpaceTakeCmd
        when 'leave'
          return SpaceLeaveCmd
        when 'land'
          return SpaceLandCmd
        when 'launch'
          return SpaceLaunchCmd

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
        when 'dock'
          return SpaceDockCmd
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

    # Reads one arg from a web request, tolerant of whether the framework
    # handed the args hash back with string or symbol keys.
    #
    # Found live: request.args comes back as string keys
    # ({"id"=>"1"}) on at least one real deployment, while every request
    # handler in plugin/web/ was written reading request.args[:id] - a
    # symbol lookup against a string-keyed hash returns nil silently, so
    # every id-bearing web page failed with a blank-name "not found"
    # error instead of a working sector/ship/system lookup. Checking
    # both key shapes here, once, is cheaper than trusting either
    # convention is stable across AresMUSH deployments/versions.
    def self.arg(request, key)
      request.args["#{key}"] || request.args[key.to_sym]
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
      when "spaceShips"
        return SpaceShipsRequestHandler
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

    # Surfaced by `manage/checkconfig`. Catches the mistakes that would
    # otherwise show up as silent token rolls mid-battle.
    def self.check_config
      errors = []

      errors.concat(Space::Dice.check_config)

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
