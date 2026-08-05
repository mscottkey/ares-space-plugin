import Controller from '@ember/controller';
import { inject as service } from '@ember/service';
import { computed, action } from '@ember/object';
import AuthenticatedController from 'ares-webportal/mixins/authenticated-controller';

export default Controller.extend(AuthenticatedController, {
  gameApi: service(),
  flashMessages: service(),

  queryParams: [ 'system' ],
  system: null,

  selectedKey: null,
  animate: true,

  pageTitle: computed('model.name', function () {
    return this.get('model.name') || 'System';
  }),

  selectedBody: computed('selectedKey', 'model.bodies.[]', function () {
    const key = this.selectedKey;
    if (!key) {
      return null;
    }
    return (this.get('model.bodies') || []).find((b) => `${b.key}` === `${key}`);
  }),

  refreshMap() {
    this.gameApi.requestOne('spaceSystem', { id: this.get('model.key') }, null)
      .then((response) => {
        if (!response.error) {
          this.set('model', response);
        }
      });
  },

  @action
  selectBody(body) {
    this.set('selectedKey', body.key);
  },

  @action
  toggleAnimation() {
    this.toggleProperty('animate');
  },

  @action
  refresh() {
    this.refreshMap();
  },

  @action
  travelTo(bodyKey) {
    this.gameApi.requestOne('spaceTravel', { destination: bodyKey }, null)
      .then((response) => {
        if (response.error) {
          this.flashMessages.danger(response.error);
          return;
        }
        this.flashMessages.success(response.message);
        this.refreshMap();
      });
  }
});
