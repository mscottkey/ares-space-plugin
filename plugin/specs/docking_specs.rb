require_relative "spec_helper"

module AresMUSH
  module Space
    describe Docking do

      let(:system_key) { "covenant_reach" }

      def spawn(name, ship_class = "Talon")
        s = TestShip.new(id: TestWorld.ships.count + 1, name: name, ship_class: ship_class)
        s.system_key = system_key
        s.location_key = "p1"
        TestWorld.ships << s
        s
      end

      def spawn_carrier(name)
        spawn(name, "Covenant")
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

      describe :hangar_room_for do
        it "is nil for a class with no flight deck" do
          fighter = spawn("Talon One")
          expect(Docking.hangar_room_for(fighter)).to be_nil
        end

        it "creates one lazily for a hangar-capable class" do
          carrier = spawn_carrier("Covenant")
          room = Docking.hangar_room_for(carrier)
          expect(room.name).to eq "Covenant (Flight Deck)"
          expect(carrier.hangar_room).to eq room
        end

        it "doesn't create a second one on a later call" do
          carrier = spawn_carrier("Covenant")
          first = Docking.hangar_room_for(carrier)
          expect(Docking.hangar_room_for(carrier)).to eq first
        end
      end

      describe :land do
        it "refuses a carrier with no flight deck" do
          fighter = spawn("Talon One")
          not_a_carrier = spawn("Talon Two")
          result = Docking.land(fighter, not_a_carrier)
          expect(result[:ok]).to be false
        end

        it "refuses if not at the same position" do
          fighter = spawn("Talon One")
          carrier = spawn_carrier("Covenant")
          carrier.location_key = "p2"
          result = Docking.land(fighter, carrier)
          expect(result[:ok]).to be false
        end

        it "refuses if either ship is in an active tactical engagement" do
          fighter = spawn("Talon One")
          carrier = spawn_carrier("Covenant")
          combat_sector = TestSector.new(id: 9)
          fighter.sector = combat_sector
          SpaceCombat.create(sector: combat_sector, state: "active")

          result = Docking.land(fighter, carrier)

          expect(result[:ok]).to be false
        end

        it "does not refuse just because a ship was once spawned into a sector - only an active fight there blocks it" do
          fighter = spawn("Talon One")
          carrier = spawn_carrier("Covenant")
          # Every ship gets a sector at spawn (space/spawn requires one),
          # but nothing ever clears it once travel takes over via
          # system_key/location_key - so a stale sector reference with no
          # active combat in it must not be mistaken for "in a fight."
          fighter.sector = TestSector.new(id: 9)

          result = Docking.land(fighter, carrier)

          expect(result[:ok]).to be true
        end

        it "refuses a ship that's already docked" do
          fighter = spawn("Talon One")
          carrier = spawn_carrier("Covenant")
          Docking.land(fighter, carrier)
          result = Docking.land(fighter, carrier)
          expect(result[:ok]).to be false
        end

        it "docks the fighter and opens a door from the hangar" do
          fighter = spawn("Talon One")
          carrier = spawn_carrier("Covenant")

          result = Docking.land(fighter, carrier)

          expect(result[:ok]).to be true
          expect(fighter.carrier).to eq carrier
          expect(fighter.dock_exit.source).to eq carrier.hangar_room
          expect(fighter.dock_exit.dest).to eq fighter.entry_room
        end

        it "clears the fighter's independent position - it has none while hangared" do
          fighter = spawn("Talon One")
          carrier = spawn_carrier("Covenant")

          Docking.land(fighter, carrier)

          expect(fighter.system_key).to be_nil
          expect(fighter.location_key).to be_nil
        end
      end

      describe :launch do
        it "refuses a ship that isn't docked anywhere" do
          fighter = spawn("Talon One")
          result = Docking.launch(fighter)
          expect(result[:ok]).to be false
        end

        it "restores the fighter's position to wherever the carrier currently is" do
          fighter = spawn("Talon One")
          carrier = spawn_carrier("Covenant")
          Docking.land(fighter, carrier)

          carrier.system_key = system_key
          carrier.location_key = "p3"   # carrier moved on while the fighter was docked

          result = Docking.launch(fighter)

          expect(result[:ok]).to be true
          expect(fighter.system_key).to eq system_key
          expect(fighter.location_key).to eq "p3"
        end

        it "clears the carrier reference and closes the door - a flying ship has none" do
          fighter = spawn("Talon One")
          carrier = spawn_carrier("Covenant")
          Docking.land(fighter, carrier)
          dock_exit_id = fighter.dock_exit.id

          Docking.launch(fighter)

          expect(fighter.carrier).to be_nil
          expect(fighter.dock_exit).to be_nil
          expect(Exit[dock_exit_id]).to be_nil
          expect(fighter.entry_room.get_exit("Out").dest).to be_nil
        end

        it "lands again cleanly after launching" do
          fighter = spawn("Talon One")
          carrier = spawn_carrier("Covenant")
          Docking.land(fighter, carrier)
          Docking.launch(fighter)

          result = Docking.land(fighter, carrier)

          expect(result[:ok]).to be true
          expect(fighter.carrier).to eq carrier
        end
      end
    end
  end
end
