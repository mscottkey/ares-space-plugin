module AresMUSH
  module Space
    class SpaceSectorsCmd
      include CommandHandler

      def handle
        sectors = SpaceSector.all.to_a
        return client.emit_success t('space.no_sectors') if sectors.empty?

        lines = [ t('space.sectors_header') ]
        sectors.each do |sector|
          ships = Ships.sector_ships(sector)
          combat = Engagements.active_combat(sector)
          state = combat ? t('space.in_combat', round: combat.round) : t('space.quiet')
          lines << "  %xh#{sector.name.to_s.ljust(24)}%xn " \
                   "#{sector.geometry.to_s.ljust(7)} " \
                   "#{sector.width}x#{sector.height}  " \
                   "ships #{ships.count.to_s.ljust(3)} #{state}"
        end
        client.emit lines.join("\n")
      end
    end
  end
end
