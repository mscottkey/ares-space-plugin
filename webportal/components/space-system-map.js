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

  // Seconds for one revolution of the innermost ring, from
  // space_systems.yml's orbit_layout.orbit_period. Outer rings take
  // proportionally longer (see the `bodies` computed below). Configured
  // rather than fixed, since "obviously moving" and "calm ambient
  // background" want very different numbers and there's no way to pick
  // one that's right for both.
  basePeriod: computed('system.orbit_period', function () {
    return this.get('system.orbit_period') || 24;
  }),

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

  // Per-body display fields shared by a planet and a moon alike - the
  // circles, the label offset, none of it cares which kind of body it's
  // drawing.
  _visual(b, labelSize) {
    const size = b.size || 6;
    return {
      key: b.key,
      name: b.name,
      callout: b.callout,
      description: b.description,
      type: b.type,
      classification: b.classification,
      isBelt: b.is_belt,
      size,
      fill: b.fill,
      stroke: b.stroke,
      faction: b.faction,
      factionColor: b.faction_color,
      shipCount: (b.ships || []).length,
      engaged: b.engaged,
      sectorId: b.sector_id,
      round: b.round,
      haloRadius: +(size + labelSize * 0.18).toFixed(2),
      shipsRadius: +(size + labelSize * 0.36).toFixed(2),
      engagedRadius: +(size + labelSize * 0.54).toFixed(2),
      labelDy: -+(size + labelSize * 0.85).toFixed(2)
    };
  },

  // Planets (and belts, stations, wrecks - anything with no `parent`)
  // orbit the star. A moon orbits its parent instead, so it is nested
  // INSIDE that parent's own rotating group rather than drawn as a
  // sibling with its own star-relative angle.
  //
  // That nesting is load-bearing, not cosmetic: two rotations compose by
  // adding their angles regardless of pivot, so a moon has to undo BOTH
  // its parent's static rotation and its own to keep its label level -
  // undoing only its own (as if it were a lone body) leaves the parent's
  // angle uncancelled and the label swings with the orbit. See the
  // regression this replaced: a moon given an independent angle, as if
  // it were just another body at its parent's ring, landed whichever
  // bearing that raw angle put it at - nowhere near the parent, and
  // farther from the star than bodies several rings out.
  bodies: computed('system.bodies.[]', 'selectedKey', 'animate', 'basePeriod', 'labelSize', function () {
    const center = this.get('system.center') || 0;
    const base = this.basePeriod;
    const selected = this.selectedKey;
    const labelSize = this.labelSize;
    const paused = this.animate ? '' : 'animation-play-state:paused;';
    const raw = this.get('system.bodies') || [];

    const moonsByParent = {};
    raw.filter((b) => b.parent).forEach((m) => {
      (moonsByParent[m.parent] = moonsByParent[m.parent] || []).push(m);
    });

    return raw.filter((b) => !b.parent).map((b) => {
      // Longer orbits further out; the exponent keeps the spread modest
      // so the outer system doesn't look frozen.
      const period = Math.round(base * Math.pow(b.ring || 1, 0.75));
      const angle = b.angle || 0;

      // Resting place along the +x axis. The static rotation below swings
      // it round to its real angle; the animation takes it from there.
      const bodyX = center + b.orbit_radius;
      const bodyY = center;

      const spinStyle =
        `transform-origin:${center}px ${center}px;` +
        `animation-duration:${period}s;` + paused;
      // Cancels the spin so the label stays level. Shared verbatim with
      // any moon below - they ride the same animation, so they need the
      // same duration/delay to cancel it.
      const counterStyle =
        `transform-origin:${bodyX}px ${bodyY}px;` +
        `animation-duration:${period}s;` + paused;

      const moons = (moonsByParent[b.key] || []).map((m) => {
        const moonAngle = m.angle || 0;
        // m.orbit_radius is the moon's distance from its PARENT here,
        // not from the star (see WebData.body_map_entry) - so this is
        // the same "rest on +x, then rotate" trick, just centred on the
        // parent's resting point instead of the star's.
        const moonX = bodyX + m.orbit_radius;
        const moonY = bodyY;

        return Object.assign(this._visual(m, labelSize), {
          bodyX: moonX,
          bodyY: moonY,
          // Places the moon around the parent's (unrotated) resting
          // point. Being nested inside the parent's own spin + start
          // transform is what then carries the two of them around the
          // star together, at a constant offset - "rides its parent's
          // orbit," literally.
          localTransform: `rotate(${moonAngle} ${bodyX} ${bodyY})`,
          counterStyle,
          // Undoes the parent's startTransform AND this moon's own
          // localTransform in one rotation - the moon branch never
          // passes through the parent's own counter group, so nothing
          // else cancels the parent's share of the rotation for it.
          counterTransform: `rotate(${-(angle + moonAngle)} ${moonX} ${moonY})`
        });
      });

      return Object.assign(this._visual(b, labelSize), {
        selected: `${b.key}` === `${selected}`,
        bodyX,
        bodyY,
        spinStyle,
        // The configured starting angle, independent of any animation.
        startTransform: `rotate(${angle} ${center} ${center})`,
        counterStyle,
        // ...and this cancels the starting angle, for the same reason.
        counterTransform: `rotate(${-angle} ${bodyX} ${bodyY})`,
        moons: moons.map((m) => Object.assign(m, { selected: `${m.key}` === `${selected}` }))
      });
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
