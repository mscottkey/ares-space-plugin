module AresMUSH
  module Space
    # space/land <carrier>
    #
    # Flies your ship into another ship's hangar - only works if both
    # are at the same body, and the target actually has a flight deck
    # (class_data["hangar"]). Acts on Ships.ship_for_char, same as
    # every other order-issuing command.
    class SpaceLandCmd
      include CommandHandler

      attr_accessor :carrier_name

      def parse_args
        self.carrier_name = cmd.args
      end

      def required_args
        [ self.carrier_name ]
      end

      def handle
        ship = Ships.ship_for_char(enactor)
        return client.emit_failure t('space.not_crewing') if !ship

        carrier = Ships.find_ship(self.carrier_name)
        return client.emit_failure t('space.ship_not_found', name: self.carrier_name) if !carrier

        result = Docking.land(ship, carrier)
        return client.emit_failure result[:error] if result[:error]
        client.emit_success result[:message]
      end
    end
  end
end
