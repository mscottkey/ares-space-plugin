module AresMUSH
  module Space
    # The sensor console. Read from any room - the bridge, a cockpit, the
    # mess - because this is instruments, not a place you stand.
    class SpaceTacCmd
      include CommandHandler

      attr_accessor :sector_name

      def parse_args
        self.sector_name = cmd.args
      end

      def handle
        ship = Ships.ship_for_char(enactor)

        if self.sector_name
          sector = SpaceSector.find_one_by_name(self.sector_name)
          return client.emit_failure t('space.sector_not_found', name: self.sector_name) if !sector
          return client.emit_failure t('space.not_your_sector') if !enactor.is_admin? && (!ship || ship.sector_id.to_s != sector.id.to_s)
          viewer = (ship && ship.sector_id.to_s == sector.id.to_s) ? ship : nil
        else
          return client.emit_failure t('space.not_crewing') if !ship
          sector = ship.sector
          return client.emit_failure t('space.ship_has_no_sector') if !sector
          viewer = ship
        end

        client.emit TacticalTemplate.new(sector, viewer).render
      end
    end
  end
end
