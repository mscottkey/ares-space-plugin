require_relative "spec_helper"

module AresMUSH
  module Space
    describe Systems do

      let(:system_key) { "covenant_reach" }

      def spawn(name, ship_class = "Talon", opts = {})
        s = TestShip.new(opts.merge(id: TestWorld.ships.count + 1, name: name, ship_class: ship_class))
        s.system_key = system_key
        TestWorld.ships << s
        s
      end

      describe :parse_ring do
        it "accepts a bare integer" do
          expect(Systems.parse_ring("5")).to eq 5
        end

        it "rejects a body key" do
          expect(Systems.parse_ring("p1")).to be_nil
        end

        it "rejects blank/nil" do
          expect(Systems.parse_ring(nil)).to be_nil
          expect(Systems.parse_ring("")).to be_nil
        end
      end

      describe :ring_key do
        it "round-trips through ring_from_key" do
          expect(Systems.ring_from_key(Systems.ring_key(5))).to eq 5
        end

        it "does not mistake a body key for a ring key" do
          expect(Systems.ring_from_key("p1")).to be_nil
        end
      end

      describe :ring_angle_for do
        it "is deterministic for the same ship" do
          ship = spawn("Talon One")
          expect(Systems.ring_angle_for(ship)).to eq Systems.ring_angle_for(ship)
        end

        it "stays within 0..359" do
          ship = spawn("Talon One", "Talon", id: 999)
          angle = Systems.ring_angle_for(ship)
          expect(angle).to be >= 0
          expect(angle).to be < 360
        end
      end

      describe :current_ring do
        it "reads a body's ring when the ship is at a body" do
          ship = spawn("Talon One")
          ship.location_key = "p1"
          expect(Systems.current_ring(ship)).to eq 1
        end

        it "reads system_ring directly when the ship has no body" do
          ship = spawn("Talon One")
          ship.system_ring = 7
          expect(Systems.current_ring(ship)).to eq 7
        end
      end

      describe :destination_name do
        it "names a body" do
          expect(Systems.destination_name(system_key, "p1")).to eq "P1"
        end

        it "names a bare ring, distinctly from a body" do
          name = Systems.destination_name(system_key, Systems.ring_key(5))
          expect(name).not_to eq Systems.destination_name(system_key, "p1")
          expect(name).to include("5")
        end
      end

      describe :set_course do
        it "sets a course to a body" do
          ship = spawn("Talon One")
          ship.location_key = "p2"

          result = Systems.set_course(ship, "p1")

          expect(result[:ok]).to be true
          expect(ship.destination_key).to eq "p1"
          expect(ship.departed_at).not_to be_nil
          expect(ship.travel_seconds).to be > 0
        end

        it "refuses a body it's already at" do
          ship = spawn("Talon One")
          ship.location_key = "p1"

          result = Systems.set_course(ship, "p1")

          expect(result[:ok]).to be false
        end

        it "refuses an unknown body" do
          ship = spawn("Talon One")
          ship.location_key = "p1"

          result = Systems.set_course(ship, "Nowhere")

          expect(result[:ok]).to be false
        end

        it "refuses while already under way" do
          ship = spawn("Talon One")
          ship.location_key = "p1"
          Systems.set_course(ship, "p2")

          result = Systems.set_course(ship, "p3")

          expect(result[:ok]).to be false
        end

        it "sets a course to a bare ring" do
          ship = spawn("Talon One")
          ship.location_key = "p1"

          result = Systems.set_course(ship, "5")

          expect(result[:ok]).to be true
          expect(ship.destination_key).to eq "ring:5"
          expect(ship.travel_seconds).to be > 0
        end

        it "refuses a ring it's already holding at" do
          ship = spawn("Talon One")
          ship.system_ring = 5

          result = Systems.set_course(ship, "5")

          expect(result[:ok]).to be false
        end

        it "sets a course from a ring back to a body" do
          ship = spawn("Talon One")
          ship.system_ring = 5

          result = Systems.set_course(ship, "p1")

          expect(result[:ok]).to be true
          expect(ship.destination_key).to eq "p1"
        end

        it "undocks the ship when a course is set" do
          landing = Room.create(name: "Landing Pad")
          Systems.set_landing_room(system_key, "p1", landing)
          ship = spawn("Talon One")
          ship.location_key = "p1"
          Docking.dock(ship)
          expect(ship.dock_exit).not_to be_nil

          Systems.set_course(ship, "p2")

          expect(ship.dock_exit).to be_nil
        end
      end

      describe :settle_arrival do
        it "does nothing for a ship not travelling" do
          ship = spawn("Talon One")
          ship.location_key = "p1"
          expect(Systems.settle_arrival(ship)).to be false
        end

        it "does nothing before the travel clock has run out" do
          ship = spawn("Talon One")
          ship.location_key = "p1"
          Systems.set_course(ship, "p2")
          expect(Systems.settle_arrival(ship)).to be false
          expect(ship.location_key).to eq "p1"
        end

        it "arrives at a body once the clock runs out" do
          ship = spawn("Talon One")
          ship.location_key = "p1"
          Systems.set_course(ship, "p2")
          ship.departed_at = Time.now - ship.travel_seconds - 1

          expect(Systems.settle_arrival(ship)).to be true
          expect(ship.location_key).to eq "p2"
          expect(ship.system_ring).to be_nil
          expect(ship.destination_key).to be_nil
          expect(ship.in_transit?).to be false
        end

        it "arrives at a ring once the clock runs out, clearing location_key" do
          ship = spawn("Talon One")
          ship.location_key = "p1"
          Systems.set_course(ship, "5")
          ship.departed_at = Time.now - ship.travel_seconds - 1

          expect(Systems.settle_arrival(ship)).to be true
          expect(ship.location_key.to_s).to be_empty
          expect(ship.system_ring).to eq 5
          expect(ship.system_angle).not_to be_nil
          expect(ship.destination_key).to be_nil
        end

        it "leaves a ring-arrived ship undocked with no body landing room" do
          ship = spawn("Talon One")
          ship.location_key = "p1"
          Systems.set_course(ship, "5")
          ship.departed_at = Time.now - ship.travel_seconds - 1

          Systems.settle_arrival(ship)

          expect(ship.dock_exit).to be_nil
        end
      end

      describe :ships_at_ring do
        it "finds a ship holding position in that ring" do
          ship = spawn("Talon One")
          ship.system_ring = 5

          expect(Systems.ships_at_ring(system_key, 5)).to eq [ ship ]
        end

        it "does not include a ship at a body, even on a matching ring" do
          ship = spawn("Talon One")
          ship.location_key = "p1"

          expect(Systems.ships_at_ring(system_key, 1)).to eq []
        end

        it "does not include a ship still travelling to that ring" do
          ship = spawn("Talon One")
          ship.location_key = "p1"
          Systems.set_course(ship, "5")

          expect(Systems.ships_at_ring(system_key, 5)).to eq []
        end
      end
    end
  end
end
