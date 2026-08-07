require_relative "spec_helper"

module AresMUSH
  module Space
    describe Docking do

      let(:system_key) { "covenant_reach" }

      def spawn(name)
        s = TestShip.new(id: TestWorld.ships.count + 1, name: name, ship_class: "Talon")
        s.system_key = system_key
        s.location_key = "p1"
        TestWorld.ships << s
        s
      end

      describe :dock do
        it "does nothing when the body has no landing room" do
          ship = spawn("Talon One")
          Docking.dock(ship)
          expect(ship.dock_exit).to be_nil
          expect(ship.entry_room).to be_nil
        end

        it "opens a door both ways once the body has a landing room" do
          landing = Room.create(name: "Landing Pad")
          Systems.set_landing_room(system_key, "p1", landing)
          ship = spawn("Talon One")

          Docking.dock(ship)

          expect(ship.dock_exit.source).to eq landing
          expect(ship.dock_exit.dest).to eq ship.entry_room
          expect(ship.entry_room.get_exit("Out").dest).to eq landing
        end

        it "names the landing-room door after the ship" do
          landing = Room.create(name: "Landing Pad")
          Systems.set_landing_room(system_key, "p1", landing)
          ship = spawn("Talon One")

          Docking.dock(ship)

          expect(ship.dock_exit.name).to eq "Talon One"
        end

        it "clears the previous door before opening a new one, so re-docking doesn't leave a stale exit behind" do
          landing = Room.create(name: "Landing Pad")
          Systems.set_landing_room(system_key, "p1", landing)
          ship = spawn("Talon One")

          Docking.dock(ship)
          first_exit_id = ship.dock_exit.id
          Docking.dock(ship)

          expect(Exit[first_exit_id]).to be_nil
          expect(ship.dock_exit.id).not_to eq first_exit_id
        end

        it "gives two ships at the same landing room two separate doors" do
          landing = Room.create(name: "Landing Pad")
          Systems.set_landing_room(system_key, "p1", landing)
          a = spawn("Talon One")
          b = spawn("Talon Two")

          Docking.dock(a)
          Docking.dock(b)

          expect(a.dock_exit.id).not_to eq b.dock_exit.id
          expect(a.dock_exit.dest).to eq a.entry_room
          expect(b.dock_exit.dest).to eq b.entry_room
        end

        it "reuses the ship's own Out exit rather than creating a second one" do
          landing = Room.create(name: "Landing Pad")
          Systems.set_landing_room(system_key, "p1", landing)
          ship = spawn("Talon One")

          Docking.dock(ship)
          out_exit = ship.entry_room.get_exit("Out")
          Docking.undock(ship)
          Docking.dock(ship)

          expect(ship.entry_room.get_exit("Out").id).to eq out_exit.id
        end
      end

      describe :undock do
        it "removes the landing-room door and closes the ship's own exit" do
          landing = Room.create(name: "Landing Pad")
          Systems.set_landing_room(system_key, "p1", landing)
          ship = spawn("Talon One")
          Docking.dock(ship)
          exit_id = ship.dock_exit.id

          Docking.undock(ship)

          expect(Exit[exit_id]).to be_nil
          expect(ship.dock_exit).to be_nil
          expect(ship.entry_room.get_exit("Out").dest).to be_nil
        end

        it "is safe to call on a ship that was never docked" do
          ship = spawn("Talon One")
          expect { Docking.undock(ship) }.not_to raise_error
        end

        it "is safe to call on a ship that never even boarded (no entry_room yet)" do
          ship = spawn("Talon One")
          expect(ship.entry_room).to be_nil
          expect { Docking.undock(ship) }.not_to raise_error
        end
      end
    end
  end
end
