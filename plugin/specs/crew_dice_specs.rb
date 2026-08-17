require_relative "spec_helper"

module AresMUSH
  module Space

    # What Crew hands the dice system, and - the point of the whole
    # slice - that the plugin actually plays on a system that is not FS3.
    describe "crew and the dice seam" do

      let(:sector) { TestSector.new(id: 1, name: "Test Sector", width: 20, height: 20) }
      let(:combat) { TestCombat.new(sector) }

      before(:each) { TestConfig.override([ "space", "dice_system" ], "fake") }

      def spawn(name, ship_class, opts = {})
        ship = TestShip.new(opts.merge(id: TestWorld.ships.count + 1,
                                       name: name,
                                       ship_class: ship_class,
                                       sector: sector))
        TestWorld.ships << ship
        ship
      end

      def crew_with_char(ship, station, name)
        char = Character.register(TestCharacter.new(TestWorld.ships.count + 100, name))
        Crew.assign(ship, station, Crew.char_key(char))
        char
      end

      def last_call
        Dice::FakeAdapter.calls.last
      end

      describe "what the seam is handed" do
        it "sends a seated character's own ability roll" do
          ship = spawn("Talon One", "Talon")
          char = crew_with_char(ship, "pilot", "Alex")

          Crew.roll_station(ship, "pilot", 2)

          expect(last_call[:kind]).to eq :ability
          expect(last_call[:char]).to eq char
          expect(last_call[:ability]).to eq "Piloting"
          expect(last_call[:modifier]).to eq 2
        end

        it "sends an NPC's stored rating as a pool, not an ability" do
          ship = spawn("Talon One", "Talon")
          Crew.assign(ship, "pilot", Crew.npc_key(5))

          Crew.roll_station(ship, "pilot", 1)

          expect(last_call[:kind]).to eq :pool
          expect(last_call[:rating]).to eq 5
          expect(last_call[:modifier]).to eq 1
        end

        it "falls back to the configured untrained pool for an unmanned station" do
          ship = spawn("Talon One", "Talon")

          Crew.roll_station(ship, "pilot")

          expect(last_call[:kind]).to eq :pool
          expect(last_call[:rating]).to eq SpaceConfig.untrained_dice
        end

        it "rolls a pool when the system doesn't know the station's ability" do
          Dice::FakeAdapter.known = [ "SomethingElse" ]
          ship = spawn("Talon One", "Talon")
          crew_with_char(ship, "pilot", "Alex")

          Crew.roll_station(ship, "pilot")

          expect(last_call[:kind]).to eq :pool
        end

        it "passes a negative modifier through unchanged" do
          ship = spawn("Talon One", "Talon")
          crew_with_char(ship, "pilot", "Alex")

          Crew.roll_station(ship, "pilot", -4)

          expect(last_call[:modifier]).to eq(-4)
        end
      end

      describe "what comes back" do
        it "carries the system's own extras through to the caller" do
          ship = spawn("Talon One", "Talon")
          crew_with_char(ship, "pilot", "Alex")

          result = Crew.roll_station(ship, "pilot")

          expect(result[:advantage]).to eq 2
          expect(result[:symbols]).to eq [ :triumph ]
        end

        # Crew resolved the display name before rolling; a dice system
        # doesn't get to overwrite it.
        it "stamps roller and ability over anything the system returned" do
          Dice::FakeAdapter.script({ successes: 1, roller: "WRONG", ability: "WRONG" })
          ship = spawn("Talon One", "Talon")
          crew_with_char(ship, "pilot", "Alex")

          result = Crew.roll_station(ship, "pilot")

          expect(result[:roller]).to eq "Alex"
          expect(result[:ability]).to eq "Piloting"
        end
      end

      # The headline: a whole round resolved by a system that is not FS3
      # and knows nothing about it. If this passes, the combat math is
      # genuinely running off the scalar and nothing else.
      describe "a full round on a non-FS3 system" do
        it "resolves attacks, evasion, repair and sweeps from the scalar alone" do
          attacker = spawn("Talon One", "Talon", x: 5, y: 5, facing: 2)
          target = spawn("Mote", "Swarm Mote", x: 6, y: 5, facing: 6)
          crew_with_char(attacker, "pilot", "Alex")

          Orders.add_fire(attacker, "Mote", 0)
          report = Resolver.resolve_round(combat)

          attack = report[:attacks].first
          expect(attack).not_to be_nil
          # 3 scripted successes vs no evade clears hit_threshold 1.
          expect(attack[:hit]).to be true
          expect(attack[:successes]).to eq 3
          expect(target.total_hull[:current]).to be < target.total_hull[:max]
        end

        it "banks an evade margin from the scalar" do
          ship = spawn("Talon One", "Talon", x: 5, y: 5)
          crew_with_char(ship, "pilot", "Alex")
          Orders.set_evade(ship)

          Resolver.resolve_round(combat)

          expect(ship.evade_margin).to eq 3
        end

        # Both roll the same scalar, so the attacker's 3 against a banked
        # 3 nets 0 - short of hit_threshold 1. The defender has to bank it
        # during the round rather than have it pre-set, since the resolver
        # zeroes evade_margin at the top of every round.
        it "lets a defender's banked margin turn a hit into a miss" do
          attacker = spawn("Talon One", "Talon", x: 5, y: 5, facing: 2)
          target = spawn("Talon Two", "Talon", x: 6, y: 5, facing: 6)
          crew_with_char(attacker, "pilot", "Alex")
          crew_with_char(target, "pilot", "Sam")

          Orders.set_evade(target)
          Orders.add_fire(attacker, "Talon Two", 0)
          report = Resolver.resolve_round(combat)

          expect(target.evade_margin).to eq 3
          expect(report[:attacks].first[:hit]).to be false
        end

        it "repairs hull equal to the scalar" do
          ship = spawn("Covenant", "Covenant", x: 5, y: 5)
          crew_with_char(ship, "engineering", "Sam")
          sections = Rules.deep_copy_sections(ship.sections)
          sections["fore"]["hull"] = 4
          ship.update(sections: sections)

          Orders.set_repair(ship, "fore")
          Resolver.resolve_round(combat)

          expect(ship.sections["fore"]["hull"]).to eq 7   # 4 + 3 successes
        end

        # Asserted on the report rather than the ship: sweeps only last
        # the round, and finish_round clears sweep_range on the way out.
        it "extends sensor reach by the scalar" do
          ship = spawn("Covenant", "Covenant", x: 5, y: 5)
          crew_with_char(ship, "sensors", "Sam")

          Orders.set_sweep(ship)
          report = Resolver.resolve_round(combat)

          sweep = report[:sweeps].first
          expect(sweep[:successes]).to eq 3
          expect(sweep[:range]).to eq SpaceConfig.passive_sensor_range + 3
        end
      end

      # A broken dice system must not take the round down with it - the
      # resolver spends ammo before it rolls.
      describe "when the dice system fails mid-round" do
        it "still completes the round instead of raising" do
          attacker = spawn("Talon One", "Talon", x: 5, y: 5, facing: 2)
          spawn("Mote", "Swarm Mote", x: 6, y: 5, facing: 6)
          crew_with_char(attacker, "gunnery", "Alex")
          Dice::FakeAdapter.raise_on_roll = true

          Orders.add_fire(attacker, "Mote", 0)

          expect { @report = Resolver.resolve_round(combat) }.not_to raise_error
          expect(@report[:attacks].first[:hit]).to be false
        end
      end
    end
  end
end
