// AresMUSH webportal custom routes.
//
// If your game already has a custom-routes.js with routes in it, add the
// two space routes to the existing function rather than replacing the
// file - this hook is shared by every plugin that adds pages.
export default function setupCustomRoutes(router) {
  router.route('space-sectors', { path: '/space' });
  router.route('space-tactical', { path: '/space/:id' });
}
