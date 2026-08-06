require_relative "spec_helper"

module AresMUSH
  module Space
    describe Crew do

      let(:sector) { TestSector.new(id: 1, name: "Test Sector") }
      let(:ship) do
        s = TestShip.new(id: 1, name: "Talon One", ship_class: "Talon", sector: sector)
        TestWorld.ships << s
        s
      end
      let(:pilot) { Character.register(TestCharacter.new(1, "Kira")) }
      let(:other) { Character.register(TestCharacter.new(2, "Dex")) }

      def board!(char, ship)
        char.update(room: Room.create(name: "Hangar"))
        Boarding.board(nil, char, ship)
      end

      describe :claim do
        it "seats the character at an open station" do
          board!(pilot, ship)
          result = Crew.claim(pilot, ship, "pilot")
          expect(result[:ok]).to be true
          expect(ship.crew_at("pilot")).to eq Crew.char_key(pilot)
        end

        it "refuses a station that isn't real" do
          board!(pilot, ship)
          result = Crew.claim(pilot, ship, "helm")   # a Talon has no helm, only pilot
          expect(result[:ok]).to be false
        end

        it "refuses a station someone already holds" do
          board!(pilot, ship)
          board!(other, ship)
          Crew.claim(pilot, ship, "pilot")

          result = Crew.claim(other, ship, "pilot")

          expect(result[:ok]).to be false
          expect(ship.crew_at("pilot")).to eq Crew.char_key(pilot)
        end

        it "refuses to claim without being aboard" do
          result = Crew.claim(pilot, ship, "pilot")
          expect(result[:ok]).to be false
        end
      end

      describe :release do
        it "clears a station the character holds" do
          board!(pilot, ship)
          Crew.claim(pilot, ship, "pilot")

          result = Crew.release(pilot, ship, "pilot")

          expect(result[:ok]).to be true
          expect(ship.crew_at("pilot")).to be_nil
        end

        it "refuses to release a station that isn't theirs" do
          board!(pilot, ship)
          board!(other, ship)
          Crew.claim(pilot, ship, "pilot")

          result = Crew.release(other, ship, "pilot")

          expect(result[:ok]).to be false
          expect(ship.crew_at("pilot")).to eq Crew.char_key(pilot)
        end

        it "refuses to release an empty station" do
          board!(pilot, ship)
          result = Crew.release(pilot, ship, "pilot")
          expect(result[:ok]).to be false
        end
      end
    end
  end
end
