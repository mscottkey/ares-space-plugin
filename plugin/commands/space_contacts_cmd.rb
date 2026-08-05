module AresMUSH
  module Space
    class SpaceContactsCmd
      include CommandHandler

      def handle
        ship = Ships.ship_for_char(enactor)
        return client.emit_failure t('space.not_crewing') if !ship

        client.emit_success t('space.contacts_header', ship: ship.name)
        client.emit Display.render_contacts(ship)
      end
    end
  end
end
