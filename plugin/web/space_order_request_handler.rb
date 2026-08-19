module AresMUSH
  module Space
    # Issues an order from the web portal.
    #
    # Runs through Orders.issue, exactly as the in-game commands do, so a
    # player at the bridge console and one in a browser get the same
    # validation, the same warnings and the same refusals.
    class SpaceOrderRequestHandler
      def handle(request)
        error = Website.check_login(request)
        return error if error

        enactor = request.enactor
        ship = Ships.ship_for_char(enactor)
        return { error: t('space.not_crewing') } if !ship

        kind = "#{Space.arg(request, :kind)}".downcase
        result = Orders.issue(ship, kind,
          heading: Space.arg(request, :heading),
          speed: Space.arg(request, :speed),
          target: Space.arg(request, :target),
          hardpoint: Space.arg(request, :hardpoint),
          section: Space.arg(request, :section))

        return { error: result[:error] } if result[:error]

        {
          message: result[:message],
          warnings: result[:warnings] || [],
          orders: WebData.orders_payload(ship)
        }
      end
    end
  end
end
