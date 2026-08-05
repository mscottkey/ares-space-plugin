import Controller from '@ember/controller';
import { inject as service } from '@ember/service';
import { computed } from '@ember/object';
import { action } from '@ember/object';
import AuthenticatedController from 'ares-webportal/mixins/authenticated-controller';

export default Controller.extend(AuthenticatedController, {
  gameApi: service(),
  gameSocket: service(),
  flashMessages: service(),

  selectedTargetId: null,
  selectedTargetName: null,
  selectedHardpoint: 0,
  heading: null,
  speed: null,
  repairSection: null,
  roundLog: '',

  pageTitle: computed('model.name', function () {
    return `Tactical - ${this.get('model.name')}`;
  }),

  setup() {
    this.set('roundLog', this.get('model.last_report') || '');
    this.set('heading', this.get('model.own_ship.facing_name'));
  },

  // The round report arrives over the same websocket the portal already
  // keeps open; the payload is "<sector id>|<report>", so traffic for
  // other sectors is ignored.
  setupCallback() {
    let self = this;
    this.gameSocket.setupCallback('space_round', function (type, msg) {
      self.onRoundResolved(msg);
    });
  },

  onRoundResolved(msg) {
    let split = `${msg}`.split('|');
    let sectorId = split[0];
    let report = split.slice(1).join('|');

    if (`${sectorId}` !== `${this.get('model.id')}`) {
      return;
    }

    this.set('roundLog', report);
    this.refreshPlot();
  },

  refreshPlot() {
    this.gameApi.requestOne('spaceTactical', { id: this.get('model.id') }, null)
      .then((response) => {
        if (response.error) {
          return;
        }
        this.set('model', response);
        this.set('selectedTargetId', null);
        this.set('selectedTargetName', null);
      });
  },

  sendOrder(args) {
    return this.gameApi.requestOne('spaceOrder', args, null).then((response) => {
      if (response.error) {
        this.flashMessages.danger(response.error);
        return;
      }
      (response.warnings || []).forEach((w) => this.flashMessages.warning(w));
      if (response.message) {
        this.flashMessages.success(response.message);
      }
      this.set('model.own_ship.orders', response.orders);
    });
  },

  @action
  selectTarget(id, name) {
    this.set('selectedTargetId', id);
    this.set('selectedTargetName', name);
  },

  @action
  setHardpoint(index) {
    this.set('selectedHardpoint', index);
  },

  @action
  orderHelm() {
    if (!this.heading) {
      this.flashMessages.danger('Choose a heading first.');
      return;
    }
    this.sendOrder({ kind: 'helm', heading: this.heading, speed: this.speed });
  },

  @action
  orderEvade() {
    this.sendOrder({ kind: 'evade' });
  },

  @action
  orderHold() {
    this.sendOrder({ kind: 'hold' });
  },

  @action
  orderFire() {
    if (!this.selectedTargetName) {
      this.flashMessages.danger('Select a contact on the plot first.');
      return;
    }
    this.sendOrder({
      kind: 'fire',
      target: this.selectedTargetName,
      hardpoint: this.selectedHardpoint
    });
  },

  @action
  orderRepair() {
    if (!this.repairSection) {
      this.flashMessages.danger('Choose a section to repair.');
      return;
    }
    this.sendOrder({ kind: 'repair', section: this.repairSection });
  },

  @action
  orderSweep() {
    this.sendOrder({ kind: 'sweep' });
  },

  @action
  clearOrders() {
    this.sendOrder({ kind: 'clear' });
  },

  @action
  resolveRound() {
    this.gameApi.requestOne('spaceResolve', { id: this.get('model.id') }, null)
      .then((response) => {
        if (response.error) {
          this.flashMessages.danger(response.error);
          return;
        }
        this.flashMessages.success(response.message);
        this.refreshPlot();
      });
  },

  @action
  refresh() {
    this.refreshPlot();
  }
});
