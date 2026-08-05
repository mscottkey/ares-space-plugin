// AresMUSH webportal custom routes.
//
// If your game already has a custom-routes.js with routes in it, add the
// space routes to the existing function rather than replacing the file -
// this hook is shared by every plugin that adds pages.
export default function setupCustomRoutes(router) {
  // The system map is the standard view of space, so it takes /space.
  // Which system is a query param (/space?system=covenant_reach) rather
  // than a second route: Ember will not register the same route name
  // twice, and there is no optional dynamic segment.
  router.route('space-system', { path: '/space' });

  // Tactical grids are the exception you drop into when there's a fight.
  router.route('space-sectors', { path: '/space/sectors' });
  router.route('space-tactical', { path: '/space/sector/:id' });
}
