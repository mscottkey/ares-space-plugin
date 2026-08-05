module AresMUSH
  module Space
    class SpaceShipRequestHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        ship = SpaceShip[request.args[:id]]
        return { c_error: t('space.ship_not_found', name: request.args[:id]) } if !ship

        {
          id: ship.id,
          name: ship.name,
          ship_class: ship.ship_class,
          faction: ship.faction,
          silhouette: ship.silhouette,
          max_speed: ship.max_speed,
          agility: ship.agility,
          status: ship.status,
          x: ship.pos[0],
          y: ship.pos[1],
          facing_name: ship.facing_name,
          speed: ship.speed.to_i,
          sections: ship.sections,
          systems_offline: ship.systems_offline,
          hardpoints: Ships.hardpoint_summary(ship),
          stations: Crew.station_summary(ship).map do |s|
            { station: s[:station], crew: s[:crew], manned: s[:manned], skill: s[:skill] }
          end
        }
      end
    end
  end
end
