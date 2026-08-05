module AresMUSH
  module Space
    # The system map. Deliberately open to any logged-in character: this
    # is the standard view of space, not a combat screen.
    class SpaceSystemRequestHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        enactor = request.enactor
        ship = Ships.ship_for_char(enactor)

        key = request.args[:id]
        key = Systems.find_system_key(key) if key
        if !key
          key = (ship && !ship.system_key.to_s.empty?) ? ship.system_key : Systems.default_system_key
        end
        return { error: t('space.no_systems') } if !key

        viewer = (ship && ship.system_key.to_s == key.to_s) ? ship : nil
        payload = WebData.system_map(key, viewer)
        return { error: t('space.no_such_system', name: key) } if !payload

        payload.merge(
          is_admin: enactor.is_admin?,
          systems: Systems.all_systems.map { |k, d| { key: k, name: d["name"] } }
        )
      end
    end
  end
end
