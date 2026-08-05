module AresMUSH
  module Space
    # Feeds the (post-POC) Ember tactical page. Reached through the
    # engine's POST /request dispatch, not a REST route.
    class SpaceTacRequestHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        enactor = request.enactor
        sector = SpaceSector[request.args[:id]]
        return { c_error: t('space.sector_not_found', name: request.args[:id]) } if !sector

        viewer = Ships.ship_for_char(enactor)
        viewer = nil if viewer && viewer.sector_id.to_s != sector.id.to_s

        is_admin = enactor && enactor.is_admin?
        return { c_error: t('space.not_your_sector') } if !viewer && !is_admin

        combat = Engagements.active_combat(sector)

        {
          id: sector.id,
          name: sector.name,
          geometry: sector.geometry,
          width: sector.width.to_i,
          height: sector.height.to_i,
          round: combat ? combat.round.to_i : nil,
          in_combat: !combat.nil?,
          own_ship: viewer ? ship_data(viewer) : nil,
          contacts: viewer ? contact_data(viewer) : all_ship_data(sector),
          terrain: Ships.sector_terrain(sector).map do |terr|
            {
              type: terr.terrain_type,
              label: Sensors.terrain_label(terr.terrain_type),
              symbol: Sensors.terrain_symbol(terr.terrain_type),
              x: terr.x.to_i,
              y: terr.y.to_i,
              radius: terr.radius.to_i
            }
          end
        }
      end

      def ship_data(ship)
        {
          id: ship.id,
          name: ship.name,
          ship_class: ship.ship_class,
          faction: ship.faction,
          x: ship.pos[0],
          y: ship.pos[1],
          facing: ship.facing.to_i,
          facing_name: ship.facing_name,
          speed: ship.speed.to_i,
          silhouette: ship.silhouette,
          sections: ship.sections,
          systems_offline: ship.systems_offline,
          status: ship.status
        }
      end

      def contact_data(viewer)
        Sensors.contacts(viewer).map do |c|
          ship = c[:ship]
          if c[:identified]
            ship_data(ship).merge(distance: c[:distance], identified: true)
          else
            {
              id: ship.id,
              name: t('space.unknown_contact'),
              x: ship.pos[0],
              y: ship.pos[1],
              distance: c[:distance],
              identified: false
            }
          end
        end
      end

      def all_ship_data(sector)
        Ships.sector_ships(sector).map { |s| ship_data(s).merge(identified: true) }
      end
    end
  end
end
