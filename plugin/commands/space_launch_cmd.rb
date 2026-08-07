module AresMUSH
  module Space
    # space/launch
    #
    # Flies your ship out of whatever hangar it's docked in. No
    # argument - a ship can only be docked in one carrier at a time.
    class SpaceLaunchCmd
      include CommandHandler

      def handle
        ship = Ships.ship_for_char(enactor)
        return client.emit_failure t('space.not_crewing') if !ship

        result = Docking.launch(ship)
        return client.emit_failure result[:error] if result[:error]
        client.emit_success result[:message]
      end
    end
  end
end
