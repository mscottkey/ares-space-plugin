import Component from '@ember/component';
import { computed } from '@ember/object';

// The orbital map. All geometry arrives precomputed from the server
// (see WebData.system_map), so this component only draws and animates.
//
// Motion is pure CSS: each body sits in a group that rotates about the
// star, with a negative animation-delay setting its starting angle so
// the config's placement is preserved. A counter-rotating inner group
// keeps labels upright.
export default Component.extend({
  tagName: '',

  system: null,
  selectedKey: null,
  animate: true,

  // Seconds for one revolution of the innermost ring. Outer rings take
  // proportionally longer, which reads as orbital motion without
  // pretending to be Kepler.
  basePeriod: 240,

  viewBox: computed('system.size', function () {
    const size = this.get('system.size') || 800;
    return `0 0 ${size} ${size}`;
  }),

  orbitRings: computed('system.rings.[]', 'system.center', function () {
    const center = this.get('system.center') || 0;
    return (this.get('system.rings') || []).map((r) => ({
      ring: r.ring,
      cx: center,
      cy: center,
      r: r.radius
    }));
  }),

  // Everything drawn on an orbit, with the CSS custom properties the
  // animation needs.
  bodies: computed('system.bodies.[]', 'selectedKey', 'animate', 'basePeriod', function () {
    const center = this.get('system.center') || 0;
    const base = this.basePeriod;
    const selected = this.selectedKey;
    const animate = this.animate;

    return (this.get('system.bodies') || []).map((b) => {
      // Longer orbits further out; the exponent keeps the spread modest
      // so the outer system doesn't look frozen.
      const period = Math.round(base * Math.pow(b.ring || 1, 0.75));
      const delay = -1 * (period * ((b.angle || 0) / 360));

      return {
        key: b.key,
        name: b.name,
        callout: b.callout,
        description: b.description,
        type: b.type,
        classification: b.classification,
        isBelt: b.is_belt,
        radius: b.orbit_radius,
        size: b.size,
        fill: b.fill,
        stroke: b.stroke,
        faction: b.faction,
        factionColor: b.faction_color,
        ships: b.ships || [],
        shipCount: (b.ships || []).length,
        engaged: b.engaged,
        sectorId: b.sector_id,
        round: b.round,
        selected: `${b.key}` === `${selected}`,
        // The body's resting place along the +x axis; the wrapper's
        // rotation carries it to its real angle.
        bodyX: center + b.orbit_radius,
        bodyY: center,
        style: `transform-origin:${center}px ${center}px;` +
               `animation-duration:${period}s;` +
               `animation-delay:${delay}s;` +
               (animate ? '' : 'animation-play-state:paused;'),
        counterStyle: `transform-origin:${center + b.orbit_radius}px ${center}px;` +
               `animation-duration:${period}s;` +
               `animation-delay:${delay}s;` +
               (animate ? '' : 'animation-play-state:paused;')
      };
    });
  }),

  // Ships are drawn at fixed points rather than on the orbit animation:
  // a ship under way should track its own course line, not spin.
  ships: computed('system.ships.[]', function () {
    return (this.get('system.ships') || []).map((s) => ({
      id: s.id,
      name: s.name,
      x: s.x,
      y: s.y,
      inTransit: s.in_transit,
      fromX: s.from_x,
      fromY: s.from_y,
      toX: s.to_x,
      toY: s.to_y,
      destinationName: s.destination_name,
      eta: s.eta,
      color: s.faction_color || '#666666',
      faction: s.faction
    }));
  }),

  actions: {
    selectBody(body) {
      if (this.onSelect) {
        this.onSelect(body);
      }
    }
  }
});
