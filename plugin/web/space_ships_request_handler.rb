module AresMUSH
  module Space
    # The ship roster. Staff see every ship; a player sees every ship
    # they hold a station on.
    class SpaceShipsRequestHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        enactor = request.enactor
        WebData.ships_list(enactor, enactor.is_admin?)
      end
    end
  end
end
