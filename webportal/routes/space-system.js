import Route from '@ember/routing/route';
import { inject as service } from '@ember/service';
import DefaultRoute from 'ares-webportal/mixins/default-route';

export default Route.extend(DefaultRoute, {
  gameApi: service(),

  queryParams: {
    system: { refreshModel: true }
  },

  // `system` is optional: with none named, the game picks the one your
  // ship is in, or the first configured system.
  model: function (params) {
    return this.gameApi.requestOne('spaceSystem', { id: params.system });
  },

  setupController: function (controller, model) {
    this._super(controller, model);
    controller.set('selectedKey', null);
  }
});
