import Component from '@ember/component';
import { computed } from '@ember/object';

// Renders a sector as SVG. The geometry math here deliberately mirrors
// plugin/helpers/geometry.rb one-for-one: square cells use screen
// coordinates, hex cells use axial (q,r) projected with
// px = q + r/2, py = r * sqrt(3)/2 - the same projection the Ruby
// bearing code uses. If you change one, change the other.
export default Component.extend({
  tagName: '',

  sector: null,
  ownShip: null,
  contacts: null,
  terrain: null,
  selectedId: null,

  cellSize: 34,

  isHex: computed('sector.geometry', function () {
    return this.get('sector.geometry') === 'hex';
  }),

  // Center of a cell in SVG units.
  cellCenter(x, y) {
    const s = this.cellSize;
    if (this.isHex) {
      return {
        cx: s * (x + y / 2) + s,
        cy: s * (y * Math.sqrt(3) / 2) + s
      };
    }
    return { cx: x * s + s, cy: y * s + s };
  },

  // Unit vector for a facing index, matching the Ruby direction tables.
  facingVector(facing) {
    const s = 1;
    if (this.isHex) {
      const hexDirs = [[1, -1], [1, 0], [0, 1], [-1, 1], [-1, 0], [0, -1]];
      const d = hexDirs[((facing % 6) + 6) % 6] || [0, 0];
      return { dx: s * (d[0] + d[1] / 2), dy: s * (d[1] * Math.sqrt(3) / 2) };
    }
    const sqDirs = [[0, -1], [1, -1], [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1]];
    const d = sqDirs[((facing % 8) + 8) % 8] || [0, 0];
    return { dx: d[0], dy: d[1] };
  },

  viewBox: computed('sector.{width,height}', 'cellSize', 'isHex', function () {
    const s = this.cellSize;
    const w = this.get('sector.width') || 20;
    const h = this.get('sector.height') || 20;
    if (this.isHex) {
      return `0 0 ${s * (w + h / 2) + s * 2} ${s * (h * Math.sqrt(3) / 2) + s * 2}`;
    }
    return `0 0 ${s * w + s} ${s * h + s}`;
  }),

  // Background cells, so the grid reads as a grid even when empty.
  cells: computed('sector.{width,height}', 'isHex', 'cellSize', function () {
    const out = [];
    const w = this.get('sector.width') || 20;
    const h = this.get('sector.height') || 20;
    const s = this.cellSize;

    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const { cx, cy } = this.cellCenter(x, y);
        if (this.isHex) {
          const r = s / Math.sqrt(3);
          const pts = [];
          for (let i = 0; i < 6; i++) {
            const a = (Math.PI / 180) * (30 + 60 * i);
            pts.push(`${(cx + r * Math.cos(a)).toFixed(2)},${(cy + r * Math.sin(a)).toFixed(2)}`);
          }
          out.push({ key: `${x}-${y}`, points: pts.join(' '), isHex: true });
        } else {
          out.push({
            key: `${x}-${y}`,
            x: cx - s / 2,
            y: cy - s / 2,
            size: s,
            isHex: false
          });
        }
      }
    }
    return out;
  }),

  terrainMarks: computed('terrain.[]', 'isHex', 'cellSize', function () {
    const list = this.terrain || [];
    const s = this.cellSize;
    return list.map((t) => {
      const { cx, cy } = this.cellCenter(t.x, t.y);
      const radius = (t.radius || 0);
      return {
        id: t.id,
        cx: cx,
        cy: cy,
        r: s * (radius + 0.5),
        label: t.label,
        symbol: t.symbol,
        type: t.type
      };
    });
  }),

  // Everything with a position on the plot: own ship plus contacts.
  markers: computed('ownShip', 'contacts.[]', 'selectedId', 'isHex', 'cellSize', function () {
    const out = [];
    const s = this.cellSize;
    const own = this.ownShip;
    const selected = this.selectedId;

    const build = (ship, isOwn) => {
      const { cx, cy } = this.cellCenter(ship.x, ship.y);
      const identified = isOwn || ship.identified;
      const v = this.facingVector(ship.facing || 0);
      const len = s * 0.55;
      const mag = Math.sqrt(v.dx * v.dx + v.dy * v.dy) || 1;

      return {
        id: ship.id,
        cx: cx,
        cy: cy,
        r: s * 0.3,
        identified: identified,
        isOwn: isOwn,
        selected: !isOwn && `${ship.id}` === `${selected}`,
        canSelect: !isOwn && identified,
        // Precomputed rather than sliced in the template: Ember has no
        // built-in substring helper.
        initial: identified && ship.name ? ship.name.charAt(0).toUpperCase() : '?',
        name: identified ? ship.name : 'Unknown contact',
        faction: identified ? ship.faction : null,
        showFacing: identified,
        fx: cx + (v.dx / mag) * len,
        fy: cy + (v.dy / mag) * len,
        hull: identified ? ship.hull : null,
        maxHull: identified ? ship.max_hull : null,
        shields: identified ? ship.shields : null,
        maxShields: identified ? ship.max_shields : null,
        destroyed: identified && ship.status === 'destroyed'
      };
    };

    if (own) {
      out.push(build(own, true));
    }
    (this.contacts || []).forEach((c) => out.push(build(c, false)));
    return out;
  }),

  actions: {
    selectContact(marker) {
      if (!marker.canSelect) {
        return;
      }
      if (this.onSelect) {
        this.onSelect(marker.id, marker.name);
      }
    }
  }
});
