module AresMUSH
  module Space
    # Sector index. Players see the sector their ship is in; staff see all.
    class SpaceSectorsRequestHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        enactor = request.enactor
        all = WebData.sectors_list
        return all if enactor.is_admin?

        ship = Ships.ship_for_char(enactor)
        return [] if !ship
        all.select { |s| s[:id].to_s == ship.sector_id.to_s }
      end
    end
  end
end
