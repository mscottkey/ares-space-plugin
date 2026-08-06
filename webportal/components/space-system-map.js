import Component from '@ember/component';
import { computed } from '@ember/object';

// The orbital map. All geometry arrives precomputed from the server
// (see WebData.system_map), so this component only draws and animates.
//
// Placement and motion are deliberately separated:
//
//   * Placement is a static SVG `transform` ATTRIBUTE carrying the body's
//     configured angle. It needs no stylesheet and no animation support.
//   * Motion is a CSS animation on an enclosing group, rotating the whole
//     orbit about the star, with a counter-rotating group inside so labels
//     stay level.
//
// An earlier version folded the starting angle into a negative
// animation-delay. That was neat and wrong: with the stylesheet missing or
// the animation paused, every body collapsed onto the +x axis, because the
// only thing putting it on its orbit was the animation itself.
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

  starGlowRadius: computed('system.star.radius', function () {
    return (this.get('system.star.radius') || 24) * 3;
  }),

  // Type size arrives from the server in canvas units, because the SVG
  // scales to whatever width the column gives it - a px value in the
  // stylesheet would be right at one width and wrong at every other.
  labelSize: computed('system.label_size', function () {
    return this.get('system.label_size') || 22;
  }),

  shipMarkerRadius: computed('labelSize', function () {
    return +(this.labelSize * 0.45).toFixed(2);
  }),

  shipLabelDy: computed('labelSize', function () {
    return -+(this.labelSize * 1.3).toFixed(2);
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

  bodies: computed('system.bodies.[]', 'selectedKey', 'animate', 'basePeriod', 'labelSize', function () {
    const center = this.get('system.center') || 0;
    const base = this.basePeriod;
    const selected = this.selectedKey;
    const labelSize = this.labelSize;
    const paused = this.animate ? '' : 'animation-play-state:paused;';

    return (this.get('system.bodies') || []).map((b) => {
      // Longer orbits further out; the exponent keeps the spread modest
      // so the outer system doesn't look frozen.
      const period = Math.round(base * Math.pow(b.ring || 1, 0.75));
      const angle = b.angle || 0;
      const size = b.size || 6;

      // Resting place along the +x axis. The static rotation below swings
      // it round to its real angle; the animation takes it from there.
      const bodyX = center + b.orbit_radius;
      const bodyY = center;

      return {
        key: b.key,
        name: b.name,
        callout: b.callout,
        description: b.description,
        type: b.type,
        classification: b.classification,
        isBelt: b.is_belt,
        radius: b.orbit_radius,
        size: size,
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

        bodyX: bodyX,
        bodyY: bodyY,
        haloRadius: +(size + labelSize * 0.18).toFixed(2),
        shipsRadius: +(size + labelSize * 0.36).toFixed(2),
        engagedRadius: +(size + labelSize * 0.54).toFixed(2),
        labelDy: -+(size + labelSize * 0.85).toFixed(2),

        // Rotates the orbit about the star.
        spinStyle:
          `transform-origin:${center}px ${center}px;` +
          `animation-duration:${period}s;` + paused,
        // The configured starting angle, independent of any animation.
        startTransform: `rotate(${angle} ${center} ${center})`,
        // Cancels the spin so the label stays level...
        counterStyle:
          `transform-origin:${bodyX}px ${bodyY}px;` +
          `animation-duration:${period}s;` + paused,
        // ...and this cancels the starting angle, for the same reason.
        counterTransform: `rotate(${-angle} ${bodyX} ${bodyY})`
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
