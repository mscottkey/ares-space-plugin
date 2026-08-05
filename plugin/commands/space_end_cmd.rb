module AresMUSH
  module Space
    class SpaceEndCmd
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

        combat = Engagements.active_combat(sector)
        return client.emit_failure t('space.no_active_combat', sector: sector.name) if !combat

        Engagements.stop(combat)
        client.emit_success t('space.combat_ended', sector: sector.name, rounds: combat.round)
        Engagements.notify_crews(sector, t('space.combat_ended_crew', sector: sector.name))
      end
    end
  end
end
