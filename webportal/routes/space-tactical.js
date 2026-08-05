import Route from '@ember/routing/route';
import { inject as service } from '@ember/service';
import DefaultRoute from 'ares-webportal/mixins/default-route';
import { action } from '@ember/object';

export default Route.extend(DefaultRoute, {
  gameApi: service(),
  gameSocket: service(),

  model: function (params) {
    return this.gameApi.requestOne('spaceTactical', { id: params.id });
  },

  setupController: function (controller, model) {
    this._super(controller, model);
    controller.setup();
  },

  activate: function () {
    this.controllerFor('space-tactical').setupCallback();
  },

  @action
  willTransition() {
    this.gameSocket.removeCallback('space_round');
  }
});
