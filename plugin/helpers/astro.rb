module AresMUSH
  module Space

    # Orbital map geometry and travel timing, as pure functions.
    #
    # Positions are computed here on the server rather than in the
    # browser: nothing in the rules depends on where a planet is drawn,
    # so one implementation beats keeping Ruby and JavaScript in step
    # the way the tactical plot has to.
    module Astro

      # Radius of an orbital ring in SVG units.
      #
      # `curve` below 1 pulls the outer rings inward, which is what keeps
      # a fourteen-world system on screen without making the inner
      # planets pile up on the star.
      def self.ring_radius(ring, layout = {})
        inner = (layout["inner_radius"] || 70).to_f
        step  = (layout["ring_step"] || 46).to_f
        curve = (layout["ring_curve"] || 1.0).to_f
        r = [ ring.to_i, 1 ].max
        inner + step * ((r - 1) ** curve)
      end

      # Where a body sits, in SVG coordinates, given the map centre.
      def self.position(center_x, center_y, radius, angle_degrees)
        radians = angle_degrees.to_f * Math::PI / 180.0
        [
          (center_x + radius * Math.cos(radians)).round(2),
          (center_y + radius * Math.sin(radians)).round(2)
        ]
      end

      # Size of the whole map, so the SVG viewBox fits the outermost ring
      # plus a margin for labels.
      #
      # The margin defaults off the label size rather than a fixed number:
      # a body sitting on the outermost ring centres its name on itself,
      # so half of a long one ("Outer Belt", "Wreck of the Concord") hangs
      # outside the ring and gets clipped by the viewBox otherwise.
      def self.canvas_size(rings, layout = {})
        outer = ring_radius(rings.to_i + 1, layout)
        margin = (layout["margin"] || label_size(layout) * 4).to_f
        ((outer + margin) * 2).round
      end

      # Drawn radius of a body.
      #
      # `size` in the config is a relative figure - how big this world is
      # next to its neighbours - while a twelve-ring system is a canvas
      # over a thousand units across. Drawing those numbers literally
      # gives specks, so `body_scale` converts relative size into
      # something legible without anyone retuning every world by hand.
      def self.body_radius(size, layout = {})
        scale = (layout["body_scale"] || 2.4).to_f
        [ size.to_f * scale, 2.0 ].max.round(2)
      end

      # Label type size, in canvas units rather than pixels - the SVG
      # scales to whatever width it's given, so the two aren't the same.
      def self.label_size(layout = {})
        (layout["label_size"] || 22).to_f
      end

      # Seconds for a ring-1 body to complete one full revolution. Outer
      # rings take proportionally longer (see space-system-map.js, which
      # applies the same ring^0.75 curve the ring spacing itself uses).
      #
      # The default here is picked to be obviously alive at a glance, not
      # to be astronomically honest - a config value modelling real
      # orbital ratios would put the outer rings' motion below the
      # threshold of being noticeable at all inside a normal page visit.
      def self.orbit_period(layout = {})
        (layout["orbit_period"] || 24).to_f
      end

      # How long a trip between two rings takes, in seconds.
      #
      # Faster hulls cross the same gap in less time; `par_speed` is the
      # speed that takes exactly the configured duration.
      def self.travel_seconds(from_ring, to_ring, ship_speed, travel = {})
        per_ring = (travel["seconds_per_ring"] || 180).to_f
        minimum  = (travel["minimum_seconds"] || 60).to_f
        par      = (travel["par_speed"] || 2).to_f

        rings = (to_ring.to_i - from_ring.to_i).abs
        speed = [ ship_speed.to_f, 0.5 ].max
        seconds = rings * per_ring * (par / speed)

        [ seconds, minimum ].max.round
      end

      # Fraction of a trip completed, 0.0 to 1.0.
      def self.progress(departed_at, travel_seconds, now = Time.now)
        return 1.0 if !departed_at
        total = travel_seconds.to_f
        return 1.0 if total <= 0
        elapsed = (now - departed_at).to_f
        return 0.0 if elapsed <= 0
        [ elapsed / total, 1.0 ].min
      end

      def self.arrived?(departed_at, travel_seconds, now = Time.now)
        progress(departed_at, travel_seconds, now) >= 1.0
      end

      def self.seconds_remaining(departed_at, travel_seconds, now = Time.now)
        return 0 if !departed_at
        remaining = travel_seconds.to_f - (now - departed_at).to_f
        remaining <= 0 ? 0 : remaining.round
      end

      # "4m 20s" - short enough for a status line.
      def self.format_duration(seconds)
        s = seconds.to_i
        return "#{s}s" if s < 60
        minutes = s / 60
        rest = s % 60
        return "#{minutes}m" if rest == 0
        "#{minutes}m #{rest}s"
      end

      # A ship in transit is drawn between its origin and destination.
      def self.transit_position(from_pos, to_pos, fraction)
        f = [ [ fraction.to_f, 0.0 ].max, 1.0 ].min
        [
          (from_pos[0] + (to_pos[0] - from_pos[0]) * f).round(2),
          (from_pos[1] + (to_pos[1] - from_pos[1]) * f).round(2)
        ]
      end
    end
  end
end
