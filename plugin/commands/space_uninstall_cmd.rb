module AresMUSH
  module Space
    class SpaceUninstallCmd
      include CommandHandler

      attr_accessor :confirm

      def parse_args
        self.confirm = downcase_arg(cmd.args)
      end

      def check_admin
        return t('dispatcher.not_allowed') if !enactor.is_admin?
        return nil
      end

      def handle
        # Confirmation rides in the args rather than a second switch: the
        # command cracker allows only one switch, so `space/uninstall/confirm`
        # would arrive as the switch "uninstall/confirm" and never route here.
        if self.confirm != "confirm"
          client.emit t('space.uninstall_warning')
          return
        end

        sectors = SpaceSector.all.to_a
        count = sectors.count
        sectors.each { |s| s.delete }

        # Sweep up anything orphaned by an interrupted delete.
        SpaceShip.all.each { |s| s.delete }
        SpaceTerrain.all.each { |t| t.delete }
        SpaceCombat.all.each { |c| c.delete }

        client.emit_success t('space.uninstalled', count: count)
      end
    end
  end
end
