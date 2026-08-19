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
  // A body caught up in an active ship transit - either endpoint of a
  // course line - holds its ambient orbit spin still, so its rendered
  // position matches the authoritative one WebData.ship_map_entry drew
  // the line to. The spin is decorative "looks alive" motion (see
  // Astro.orbit_period's own docstring: not meant to be astronomically
  // honest), not a real clock, so left running it visibly drifts the
  // destination away from the line within moments of a refresh - the
  // two only ever agree at the instant the animation starts. A moon has
  // no independent spin of its own; it only moves because it's nested
  // inside its PARENT's spin group, so a transit touching a moon has to
  // freeze the parent, not the moon's own (nonexistent) animation.
  bodies: computed('system.bodies.[]', 'system.ships.[]', 'selectedKey', 'animate', 'basePeriod', 'labelSize', function () {
    const center = this.get('system.center') || 0;
    const base = this.basePeriod;
    const selected = this.selectedKey;
    const labelSize = this.labelSize;
    const globallyPaused = !this.animate;
    const raw = this.get('system.bodies') || [];

    const moonsByParent = {};
    const parentOf = {};
    raw.filter((b) => b.parent).forEach((m) => {
      (moonsByParent[m.parent] = moonsByParent[m.parent] || []).push(m);
      parentOf[`${m.key}`] = `${m.parent}`;
    });

    const transitBodyKeys = new Set();
    (this.get('system.ships') || []).filter((s) => s.in_transit).forEach((s) => {
      [ s.location, s.destination ].forEach((key) => {
        if (!key || /^ring:/.test(`${key}`)) {
          return;
        }
        transitBodyKeys.add(parentOf[`${key}`] || `${key}`);
      });
    });

    return raw.filter((b) => !b.parent).map((b) => {
      // Longer orbits further out; the exponent keeps the spread modest
      // so the outer system doesn't look frozen.
      const period = Math.round(base * Math.pow(b.ring || 1, 0.75));
      const angle = b.angle || 0;
      const paused = (globallyPaused || transitBodyKeys.has(`${b.key}`))
        ? 'animation-play-state:paused;' : '';

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

      // A ship at this body only arrives here (engaged_ships) when the
      // body is actually engaged - see WebData.body_map_entry. It rides
      // the body's own rotation the exact same way a moon does: a
      // small fixed offset from the body's resting point, nested inside
      // the same spin+start transform, with the same two-angle counter-
      // rotation to keep its label level. shipsRadius is small on
      // purpose - "hovering right next to the body," not another orbit.
      const shipsRadius = this._visual(b, labelSize).shipsRadius;
      const dockedShips = (b.engaged_ships || []).map((s, i) => {
        const count = b.engaged_ships.length;
        const shipAngle = count > 1 ? (360 / count) * i : 0;
        const shipX = bodyX + shipsRadius * Math.cos(shipAngle * Math.PI / 180);
        const shipY = bodyY + shipsRadius * Math.sin(shipAngle * Math.PI / 180);
        const shipCounterStyle =
          `transform-origin:${shipX}px ${shipY}px;` +
          `animation-duration:${period}s;` + paused;

        return {
          id: s.id,
          name: s.name,
          faction: s.faction,
          color: s.faction_color || '#666666',
          shipX,
          shipY,
          localTransform: `rotate(${shipAngle} ${bodyX} ${bodyY})`,
          counterStyle: shipCounterStyle,
          counterTransform: `rotate(${-(angle + shipAngle)} ${shipX} ${shipY})`
        };
      });

      const moons = (moonsByParent[b.key] || []).map((m) => {
        const moonAngle = m.angle || 0;
        // m.orbit_radius is the moon's distance from its PARENT here,
        // not from the star (see WebData.body_map_entry) - so this is
        // the same "rest on +x, then rotate" trick, just centred on the
        // parent's resting point instead of the star's.
        const moonX = bodyX + m.orbit_radius;
        const moonY = bodyY;
        // Same animation-duration/delay as the parent's counterStyle -
        // it has to cancel the exact same shared Spin(t) - but pivoted
        // at the MOON's own resting point, not the parent's. Reusing
        // the parent's counterStyle verbatim (its transform-origin is
        // the parent's bodyX/bodyY) was the actual bug here: rotating
        // the moon's counter-spin about the wrong point doesn't cancel
        // position, it orbits the moon around a point offset from
        // where it belongs by exactly its own moon_orbit distance.
        const moonCounterStyle =
          `transform-origin:${moonX}px ${moonY}px;` +
          `animation-duration:${period}s;` + paused;

        return Object.assign(this._visual(m, labelSize), {
          bodyX: moonX,
          bodyY: moonY,
          // Places the moon around the parent's (unrotated) resting
          // point. Being nested inside the parent's own spin + start
          // transform is what then carries the two of them around the
          // star together, at a constant offset - "rides its parent's
          // orbit," literally.
          localTransform: `rotate(${moonAngle} ${bodyX} ${bodyY})`,
          counterStyle: moonCounterStyle,
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
        moons: moons.map((m) => Object.assign(m, { selected: `${m.key}` === `${selected}` })),
        dockedShips
      });
    });
  }),

  // Only a ship under way gets drawn here - it tracks its own course
  // line between two points, which isn't something either orbit-spin
  // mechanism below applies to. A ship parked at an engaged body rides
  // that body's own group instead (see `bodies`/`dockedShips` above);
  // a ring-anchored ship gets its own group below (`ringShips`). Any
  // ship simply parked with nothing going on isn't in system.ships at
  // all - see WebData.system_ship_entries - so there's nothing to
  // filter out here for that case.
  ships: computed('system.ships.[]', function () {
    return (this.get('system.ships') || [])
      .filter((s) => s.in_transit)
      .map((s) => ({
        id: s.id,
        name: s.name,
        x: s.x,
        y: s.y,
        inTransit: true,
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

  // A ring-anchored ship has no body to ride along with, so it gets its
  // own animated group, structured exactly like a lone body in `bodies`
  // above (spin about the star, counter-rotate to keep the label
  // level) but ship-styled rather than drawn as a body circle. Unlike
  // an in-transit ship, it isn't going anywhere, so the flat `ships`
  // layer (built for a moving course line) isn't the right home for it.
  ringShips: computed('system.ships.[]', 'animate', 'basePeriod', 'labelSize', function () {
    const center = this.get('system.center') || 0;
    const base = this.basePeriod;
    const labelSize = this.labelSize;
    const paused = this.animate ? '' : 'animation-play-state:paused;';
    const raw = (this.get('system.ships') || []).filter((s) => s.ring_anchored);

    return raw.map((s) => {
      const period = Math.round(base * Math.pow(s.ring || 1, 0.75));
      const angle = s.angle || 0;
      const bodyX = center + s.orbit_radius;
      const bodyY = center;

      const spinStyle =
        `transform-origin:${center}px ${center}px;` +
        `animation-duration:${period}s;` + paused;
      const counterStyle =
        `transform-origin:${bodyX}px ${bodyY}px;` +
        `animation-duration:${period}s;` + paused;

      return {
        id: s.id,
        name: s.name,
        faction: s.faction,
        color: s.faction_color || '#666666',
        bodyX,
        bodyY,
        spinStyle,
        startTransform: `rotate(${angle} ${center} ${center})`,
        counterStyle,
        counterTransform: `rotate(${-angle} ${bodyX} ${bodyY})`
      };
    });
  }),

  actions: {
    selectBody(body) {
      if (this.onSelect) {
        this.onSelect(body);
      }
    }
  }
});
