module AresMUSH
  module Space
    # space/start <sector>
    class SpaceStartCmd
      include CommandHandler

      attr_accessor :sector_name

      def parse_args
        self.sector_name = cmd.args
      end

      def required_args
        [ self.sector_name ]
      end

      def check_admin
        return t('dispatcher.not_allowed') if !enactor.is_admin?
        return nil
      end

      def handle
        sector = SpaceSector.find_one_by_name(self.sector_name)
        return client.emit_failure t('space.sector_not_found', name: self.sector_name) if !sector

        combat, error = Engagements.start(sector)
        return client.emit_failure error if error

        client.emit_success t('space.combat_started', sector: sector.name)
        Engagements.notify_crews(sector, t('space.combat_started_crew', sector: sector.name))
      end
    end
  end
end
