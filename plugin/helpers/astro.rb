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
      def self.canvas_size(rings, layout = {})
        outer = ring_radius(rings.to_i + 1, layout)
        margin = (layout["margin"] || 40).to_f
        ((outer + margin) * 2).round
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
