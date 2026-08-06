require_relative "spec_helper"

module AresMUSH
  module Space
    describe Boarding do

      let(:sector) { TestSector.new(id: 1, name: "Test Sector") }
      let(:ship) do
        s = TestShip.new(id: 1, name: "Talon One", ship_class: "Talon", sector: sector)
        TestWorld.ships << s
        s
      end
      let(:pilot) { Character.register(TestCharacter.new(1, "Kira")) }

      describe :entry_room_for do
        it "creates the room on first need" do
          room = Boarding.entry_room_for(ship)
          expect(room.name).to eq "Talon One (Ship)"
          expect(ship.entry_room).to eq room
        end

        it "seeds operational_rooms with it" do
          room = Boarding.entry_room_for(ship)
          expect(ship.operational_rooms).to include(room.id.to_s)
        end

        it "doesn't create a second room on a later call" do
          first = Boarding.entry_room_for(ship)
          second = Boarding.entry_room_for(ship)
          expect(second).to eq first
        end
      end

      describe :aboard? do
        it "is true in the entry room" do
          room = Boarding.entry_room_for(ship)
          pilot.update(room: room)
          expect(Boarding.aboard?(pilot, ship)).to be true
        end

        it "is true in a tagged room" do
          Boarding.entry_room_for(ship)
          extra = Room.create(name: "Talon One - Cockpit")
          Boarding.tag_room(ship, extra)
          pilot.update(room: extra)
          expect(Boarding.aboard?(pilot, ship)).to be true
        end

        it "is false in an untagged room" do
          Boarding.entry_room_for(ship)
          elsewhere = Room.create(name: "Somewhere Else")
          pilot.update(room: elsewhere)
          expect(Boarding.aboard?(pilot, ship)).to be false
        end

        it "is false with no room at all" do
          expect(Boarding.aboard?(pilot, ship)).to be false
        end
      end

      describe :board do
        it "moves the character into the entry room" do
          origin = Room.create(name: "Landing Pad")
          pilot.update(room: origin)

          result = Boarding.board(nil, pilot, ship)

          expect(result[:ok]).to be true
          expect(pilot.room).to eq ship.entry_room
        end

        it "remembers where the character came from" do
          origin = Room.create(name: "Landing Pad")
          pilot.update(room: origin)

          Boarding.board(nil, pilot, ship)

          expect(Boarding.recall_origin(ship, pilot)).to eq origin
        end

        it "refuses to board twice" do
          Boarding.board(nil, pilot, ship)
          result = Boarding.board(nil, pilot, ship)
          expect(result[:ok]).to be false
        end

        it "stamps the ship as the character's current one" do
          Boarding.board(nil, pilot, ship)
          expect(pilot.current_ship).to eq ship
        end

        it "boarding a second ship overwrites the stamp, even if never disembarked" do
          fighter = TestShip.new(id: 2, name: "TIE One", ship_class: "Talon", sector: sector)
          TestWorld.ships << fighter

          Boarding.board(nil, pilot, ship)
          pilot.update(room: Room.create(name: "Wandered off"))   # left without disembarking
          Boarding.board(nil, pilot, fighter)

          expect(pilot.current_ship).to eq fighter
        end
      end

      describe :disembark do
        it "returns the character to where they boarded from" do
          origin = Room.create(name: "Landing Pad")
          pilot.update(room: origin)
          Boarding.board(nil, pilot, ship)

          result = Boarding.disembark(nil, pilot, ship)

          expect(result[:ok]).to be true
          expect(pilot.room).to eq origin
        end

        it "falls back to the OOC room if nothing was remembered" do
          Boarding.entry_room_for(ship)
          pilot.update(room: ship.entry_room)

          Boarding.disembark(nil, pilot, ship)

          expect(pilot.room).to eq Rooms.ooc_room
        end

        it "forgets the origin once used, so a second board/disembark doesn't reuse a stale one" do
          origin = Room.create(name: "Landing Pad")
          pilot.update(room: origin)
          Boarding.board(nil, pilot, ship)
          Boarding.disembark(nil, pilot, ship)

          elsewhere = Room.create(name: "Somewhere Else")
          pilot.update(room: elsewhere)
          Boarding.board(nil, pilot, ship)
          Boarding.disembark(nil, pilot, ship)

          expect(pilot.room).to eq elsewhere
        end

        it "refuses to disembark a character who isn't aboard" do
          result = Boarding.disembark(nil, pilot, ship)
          expect(result[:ok]).to be false
        end

        it "clears the current-ship stamp" do
          pilot.update(room: Room.create(name: "Landing Pad"))
          Boarding.board(nil, pilot, ship)
          Boarding.disembark(nil, pilot, ship)
          expect(pilot.current_ship).to be_nil
        end
      end

      describe :tag_room do
        it "adds the room to the operational set" do
          extra = Room.create(name: "Engineering")
          Boarding.tag_room(ship, extra)
          expect(ship.operational_rooms).to include(extra.id.to_s)
        end

        it "is idempotent" do
          extra = Room.create(name: "Engineering")
          Boarding.tag_room(ship, extra)
          Boarding.tag_room(ship, extra)
          expect(ship.operational_rooms.count(extra.id.to_s)).to eq 1
        end
      end

      describe :ship_for_room do
        it "finds the ship by its entry room" do
          room = Boarding.entry_room_for(ship)
          expect(Boarding.ship_for_room(room)).to eq ship
        end

        it "finds the ship by a tagged room" do
          Boarding.entry_room_for(ship)
          extra = Room.create(name: "Engineering")
          Boarding.tag_room(ship, extra)
          expect(Boarding.ship_for_room(extra)).to eq ship
        end

        it "returns nil for a room no ship claims" do
          elsewhere = Room.create(name: "Somewhere Else")
          expect(Boarding.ship_for_room(elsewhere)).to be_nil
        end

        it "returns nil for no room" do
          expect(Boarding.ship_for_room(nil)).to be_nil
        end
      end
    end
  end
end
