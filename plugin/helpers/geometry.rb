module AresMUSH
  module Space

    # Pure geometry. No Ohm, no config reads, no Ares dependencies - the
    # geometry mode is always passed in, so this is unit-testable and both
    # square and hex sectors run through one interface.
    #
    # Positions are [x, y] pairs. In hex mode those are axial coordinates
    # [q, r]; the storage and the interface don't change, only the math.
    #
    # Facings are integer indices into the geometry's direction list.
    module Geometry

      # y grows downward (screen/telnet order), so N is (0, -1).
      SQUARE_DIRS = [
        { name: "N",  short: "N",  delta: [  0, -1 ] },
        { name: "NE", short: "NE", delta: [  1, -1 ] },
        { name: "E",  short: "E",  delta: [  1,  0 ] },
        { name: "SE", short: "SE", delta: [  1,  1 ] },
        { name: "S",  short: "S",  delta: [  0,  1 ] },
        { name: "SW", short: "SW", delta: [ -1,  1 ] },
        { name: "W",  short: "W",  delta: [ -1,  0 ] },
        { name: "NW", short: "NW", delta: [ -1, -1 ] }
      ]

      # Axial hex, pointy-top. Neighbours sit at 30/90/150/210/270/330
      # degrees, which is why these are named NE..NW with no true N.
      HEX_DIRS = [
        { name: "NE", short: "NE", delta: [  1, -1 ] },
        { name: "E",  short: "E",  delta: [  1,  0 ] },
        { name: "SE", short: "SE", delta: [  0,  1 ] },
        { name: "SW", short: "SW", delta: [ -1,  1 ] },
        { name: "W",  short: "W",  delta: [ -1,  0 ] },
        { name: "NW", short: "NW", delta: [  0, -1 ] }
      ]

      def self.hex?(mode)
        "#{mode}".downcase == "hex"
      end

      def self.dirs(mode)
        hex?(mode) ? HEX_DIRS : SQUARE_DIRS
      end

      def self.facing_count(mode)
        dirs(mode).count
      end

      def self.facing_name(mode, facing)
        d = dirs(mode)[facing.to_i % facing_count(mode)]
        d ? d[:name] : "?"
      end

      # Parses "NE", "ne", or a raw index. Returns nil if it isn't a
      # legal facing for this geometry.
      def self.parse_facing(mode, str)
        return nil if str.nil?
        s = "#{str}".strip.upcase
        return nil if s.empty?

        idx = dirs(mode).index { |d| d[:name] == s }
        return idx if idx

        if s =~ /\A\d+\z/
          i = s.to_i
          return i if i >= 0 && i < facing_count(mode)
        end
        nil
      end

      def self.facing_names(mode)
        dirs(mode).map { |d| d[:name] }
      end

      # Distance in whole squares/hexes.
      def self.distance(mode, from, to)
        dx = to[0] - from[0]
        dy = to[1] - from[1]

        if hex?(mode)
          # Axial distance.
          (dx.abs + (dx + dy).abs + dy.abs) / 2
        else
          # Chebyshev: diagonals cost the same as orthogonals, which is
          # what 8-way movement implies.
          [ dx.abs, dy.abs ].max
        end
      end

      # The facing index pointing from one position toward another.
      # Returns nil when the positions coincide (no meaningful bearing).
      def self.bearing(mode, from, to)
        dx = to[0] - from[0]
        dy = to[1] - from[1]
        return nil if dx == 0 && dy == 0

        if hex?(mode)
          # Axial -> pixel, then snap to the 6 directions at 30 + 60n.
          px = dx.to_f + dy.to_f / 2.0
          py = dy.to_f * Math.sqrt(3) / 2.0
          deg = normalize_degrees(Math.atan2(px, -py) * 180.0 / Math::PI)
          (((deg - 30.0) / 60.0).round % 6)
        else
          deg = normalize_degrees(Math.atan2(dx.to_f, -dy.to_f) * 180.0 / Math::PI)
          ((deg / 45.0).round % 8)
        end
      end

      # Which of the observer's four arcs a target lies in.
      # Returns :forward, :aft, :port, :starboard, or nil if co-located.
      #
      # diagonal_bias (square only) decides where the corner directions go:
      #   "forward"   - wide bow/stern arcs, narrow beams
      #   "broadside" - narrow bow/stern, wide beams
      def self.arc(mode, observer_pos, observer_facing, target_pos, diagonal_bias = "forward")
        b = bearing(mode, observer_pos, target_pos)
        return nil if b.nil?
        arc_for_bearing(mode, observer_facing, b, diagonal_bias)
      end

      def self.arc_for_bearing(mode, observer_facing, bearing, diagonal_bias = "forward")
        count = facing_count(mode)
        rel = (bearing.to_i - observer_facing.to_i) % count

        if hex?(mode)
          # 6 facings split 1 / 2 / 1 / 2 - evenly, no bias needed.
          case rel
          when 0    then :forward
          when 1, 2 then :starboard
          when 3    then :aft
          else           :port
          end
        elsif "#{diagonal_bias}".downcase == "broadside"
          case rel
          when 0          then :forward
          when 1, 2, 3    then :starboard
          when 4          then :aft
          else                 :port
          end
        else
          case rel
          when 7, 0, 1    then :forward
          when 2          then :starboard
          when 3, 4, 5    then :aft
          else                 :port
          end
        end
      end

      # Cheapest number of facing steps between two headings.
      def self.turn_cost(mode, from_facing, to_facing)
        count = facing_count(mode)
        diff = (to_facing.to_i - from_facing.to_i) % count
        [ diff, count - diff ].min
      end

      # Moves `steps` squares/hexes along a facing.
      def self.translate(mode, pos, facing, steps = 1)
        d = dirs(mode)[facing.to_i % facing_count(mode)]
        return pos if !d
        [ pos[0] + d[:delta][0] * steps, pos[1] + d[:delta][1] * steps ]
      end

      def self.in_bounds?(pos, width, height)
        pos[0] >= 0 && pos[0] < width && pos[1] >= 0 && pos[1] < height
      end

      # A short human bearing/range string for sensor readouts.
      def self.describe_vector(mode, from, to)
        b = bearing(mode, from, to)
        dist = distance(mode, from, to)
        return "docked" if b.nil?
        "#{facing_name(mode, b)} #{dist}"
      end

      def self.normalize_degrees(deg)
        d = deg % 360.0
        d < 0 ? d + 360.0 : d
      end

      private_class_method :normalize_degrees
    end
  end
end
