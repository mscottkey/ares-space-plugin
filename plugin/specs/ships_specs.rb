require_relative "spec_helper"

module AresMUSH
  module Space
    describe Ships do

      let(:sector) { TestSector.new(id: 1, name: "Test Sector") }

      def spawn(name, ship_class = "Talon")
        s = TestShip.new(id: TestWorld.ships.count + 1, name: name, ship_class: ship_class, sector: sector)
        TestWorld.ships << s
        s
      end

      let(:pilot) { Character.register(TestCharacter.new(1, "Kira")) }

      describe :ship_for_char do
        it "is nil for a character crewing nothing" do
          expect(Ships.ship_for_char(pilot)).to be_nil
        end

        it "finds a ship the character holds a station on, boarding or not" do
          ship = spawn("Talon One")
          Crew.assign(ship, "pilot", Crew.char_key(pilot))
          expect(Ships.ship_for_char(pilot)).to eq ship
        end

        it "prefers current_ship over a stale station held elsewhere" do
          isd = spawn("ISD")
          tie = spawn("TIE One")
          Crew.assign(isd, "helm", Crew.char_key(pilot))
          Crew.assign(tie, "pilot", Crew.char_key(pilot))

          pilot.update(room: Room.create(name: "Hangar"))
          Boarding.board(nil, pilot, tie)

          expect(Ships.ship_for_char(pilot)).to eq tie
        end

        it "boarding back to the first ship makes it current again" do
          isd = spawn("ISD")
          tie = spawn("TIE One")
          Crew.assign(isd, "helm", Crew.char_key(pilot))
          Crew.assign(tie, "pilot", Crew.char_key(pilot))

          origin = Room.create(name: "Hangar")
          pilot.update(room: origin)
          Boarding.board(nil, pilot, tie)
          Boarding.disembark(nil, pilot, tie)
          Boarding.board(nil, pilot, isd)

          expect(Ships.ship_for_char(pilot)).to eq isd
        end

        it "falls back to the scan if current_ship no longer holds a station for them" do
          ship = spawn("Talon One")
          pilot.update(room: Room.create(name: "Hangar"))
          Boarding.board(nil, pilot, ship)
          # Boarded, but never claimed anything - and staff assigned them
          # a seat on a different ship entirely, the old space/crew way.
          other = spawn("Talon Two")
          Crew.assign(other, "pilot", Crew.char_key(pilot))

          expect(Ships.ship_for_char(pilot)).to eq other
        end

        it "ignores a destroyed current_ship" do
          ship = spawn("Talon One")
          Crew.assign(ship, "pilot", Crew.char_key(pilot))
          pilot.update(room: Room.create(name: "Hangar"))
          Boarding.board(nil, pilot, ship)
          ship.update(status: "destroyed")

          expect(Ships.ship_for_char(pilot)).to be_nil
        end
      end
    end
  end
end
