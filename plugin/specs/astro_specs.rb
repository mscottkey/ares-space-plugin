require_relative "spec_helper"

module AresMUSH
  module Space
    describe Astro do

      let(:layout) { { "inner_radius" => 70, "ring_step" => 46, "ring_curve" => 1.0 } }
      let(:travel) { { "seconds_per_ring" => 180, "minimum_seconds" => 60, "par_speed" => 2 } }

      describe :ring_radius do
        it "puts the first ring at the inner radius" do
          expect(Astro.ring_radius(1, layout)).to eq 70.0
        end

        it "steps outward evenly with a linear curve" do
          expect(Astro.ring_radius(2, layout)).to eq 116.0
          expect(Astro.ring_radius(3, layout)).to eq 162.0
        end

        it "compresses the outer rings when the curve is below one" do
          curved = layout.merge("ring_curve" => 0.5)
          spread_inner = Astro.ring_radius(3, curved) - Astro.ring_radius(2, curved)
          spread_outer = Astro.ring_radius(12, curved) - Astro.ring_radius(11, curved)
          expect(spread_outer).to be < spread_inner
        end

        it "treats ring zero as ring one rather than collapsing onto the star" do
          expect(Astro.ring_radius(0, layout)).to eq 70.0
        end
      end

      describe :position do
        it "places zero degrees to the right of the star" do
          x, y = Astro.position(400, 400, 100, 0)
          expect(x).to eq 500.0
          expect(y).to eq 400.0
        end

        it "places ninety degrees below the star in SVG coordinates" do
          x, y = Astro.position(400, 400, 100, 90)
          expect(x).to be_within(0.01).of(400.0)
          expect(y).to be_within(0.01).of(500.0)
        end

        it "comes back round after a full turn" do
          a = Astro.position(400, 400, 100, 30)
          b = Astro.position(400, 400, 100, 390)
          expect(a[0]).to be_within(0.01).of(b[0])
          expect(a[1]).to be_within(0.01).of(b[1])
        end
      end

      describe :canvas_size do
        it "leaves room for the outermost ring and its labels" do
          size = Astro.canvas_size(10, layout)
          outer = Astro.ring_radius(11, layout)
          expect(size).to be >= (outer * 2)
        end
      end

      describe :travel_seconds do
        it "charges per ring crossed" do
          expect(Astro.travel_seconds(1, 3, 2, travel)).to eq 360
        end

        it "is symmetric between outbound and inbound" do
          expect(Astro.travel_seconds(6, 2, 2, travel)).to eq Astro.travel_seconds(2, 6, 2, travel)
        end

        it "rewards a faster hull" do
          fast = Astro.travel_seconds(1, 5, 4, travel)
          slow = Astro.travel_seconds(1, 5, 1, travel)
          expect(fast).to be < slow
        end

        it "never drops below the configured minimum" do
          expect(Astro.travel_seconds(3, 3, 10, travel)).to eq 60
          expect(Astro.travel_seconds(1, 2, 99, travel)).to eq 60
        end

        it "does not divide by zero for a crippled hull" do
          expect(Astro.travel_seconds(1, 4, 0, travel)).to be > 0
        end
      end

      describe :progress do
        it "is zero at the moment of departure" do
          now = Time.now
          expect(Astro.progress(now, 100, now)).to eq 0.0
        end

        it "is half way at half the duration" do
          departed = Time.now - 50
          expect(Astro.progress(departed, 100, Time.now)).to be_within(0.01).of(0.5)
        end

        it "clamps at one once the trip is over" do
          expect(Astro.progress(Time.now - 500, 100, Time.now)).to eq 1.0
        end

        it "treats a ship that never departed as arrived" do
          expect(Astro.progress(nil, 100)).to eq 1.0
        end
      end

      describe :arrived? do
        it "is false mid-flight and true afterwards" do
          expect(Astro.arrived?(Time.now - 10, 100)).to be false
          expect(Astro.arrived?(Time.now - 200, 100)).to be true
        end
      end

      describe :seconds_remaining do
        it "counts down and stops at zero" do
          expect(Astro.seconds_remaining(Time.now - 40, 100)).to be_within(2).of(60)
          expect(Astro.seconds_remaining(Time.now - 500, 100)).to eq 0
        end
      end

      describe :format_duration do
        it "reads naturally at each scale" do
          expect(Astro.format_duration(45)).to eq "45s"
          expect(Astro.format_duration(120)).to eq "2m"
          expect(Astro.format_duration(260)).to eq "4m 20s"
        end
      end

      describe :transit_position do
        it "sits at the origin at the start and the destination at the end" do
          expect(Astro.transit_position([ 0, 0 ], [ 100, 50 ], 0)).to eq [ 0.0, 0.0 ]
          expect(Astro.transit_position([ 0, 0 ], [ 100, 50 ], 1)).to eq [ 100.0, 50.0 ]
        end

        it "interpolates in between" do
          expect(Astro.transit_position([ 0, 0 ], [ 100, 50 ], 0.5)).to eq [ 50.0, 25.0 ]
        end

        it "clamps a fraction outside zero to one" do
          expect(Astro.transit_position([ 0, 0 ], [ 100, 50 ], 5)).to eq [ 100.0, 50.0 ]
          expect(Astro.transit_position([ 0, 0 ], [ 100, 50 ], -3)).to eq [ 0.0, 0.0 ]
        end
      end
    end
  end
end
