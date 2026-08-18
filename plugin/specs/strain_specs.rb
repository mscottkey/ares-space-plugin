require_relative "spec_helper"

module AresMUSH
  module Space
    describe "system strain" do
      let(:sector) { TestSector.new(id: 1, name: "Concord Graveyard", width: 20, height: 20) }
      let(:combat) { TestCombat.new(sector) }

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

      def script(*successes)
        FS3Skills.scripted_successes = successes.flatten
      end

      describe "ShipBehavior#strain_threshold" do
        it "defaults off silhouette when the ship class sets nothing" do
          talon = spawn("Talon One", "Talon")
          expect(talon.strain_threshold).to eq(talon.silhouette * 2)
        end
      end

      describe "a strained-out ship" do
        it "skips movement" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5, facing: 0)
          talon.update(strain: talon.strain_threshold)
          Orders.set_move(talon, 0, 3)

          Resolver.resolve_round(combat)

          expect(talon.pos).to eq [ 5, 5 ]
        end

        it "skips attacks" do
          attacker = spawn("Talon One", "Talon", x: 5, y: 5, facing: 4)
          target = spawn("Mote", "Swarm Mote", x: 5, y: 6, facing: 0)
          attacker.update(strain: attacker.strain_threshold)

          Orders.add_fire(attacker, "Mote", 0)
          script(9)

          report = Resolver.resolve_round(combat)

          expect(report[:attacks]).to be_empty
          expect(target.sections["hull"]["hull"]).to eq 3
        end

        it "still rolls engineering (repair)" do
          covenant = spawn("Covenant", "Covenant", x: 10, y: 10)
          crew_with_char(covenant, "engineering", "Sato")
          covenant.update(strain: covenant.strain_threshold)

          sections = covenant.sections
          sections["aft"]["hull"] = 4
          covenant.update(sections: sections)

          Orders.set_repair(covenant, "aft")
          script(3)

          Resolver.resolve_round(combat)

          expect(covenant.sections["aft"]["hull"]).to eq 7
        end

        it "still runs sensor sweeps" do
          covenant = spawn("Covenant", "Covenant", x: 10, y: 10)
          crew_with_char(covenant, "sensors", "Idris")
          covenant.update(strain: covenant.strain_threshold)

          Orders.set_sweep(covenant)
          script(4)

          report = Resolver.resolve_round(combat)

          expect(report[:sweeps].first[:range]).to eq(SpaceConfig.passive_sensor_range + 4)
        end

        it "stays active - not destroyed - and its status is untouched" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          talon.update(strain: talon.strain_threshold)

          Resolver.resolve_round(combat)

          expect(talon.destroyed?).to be false
          expect(talon.status).to eq "active"
          expect(talon.active?).to be true
        end
      end

      describe "passive recovery" do
        it "recovers strain each round and comes back under threshold" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          talon.update(strain: talon.strain_threshold)
          expect(talon.strained_out?).to be true

          talon.strain_threshold.times { Resolver.resolve_round(combat) }

          expect(talon.strain).to eq 0
          expect(talon.strained_out?).to be false
        end

        it "moves and fights again once it drops back under threshold" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5, facing: 0)
          talon.update(strain: talon.strain_threshold)

          talon.strain_threshold.times { Resolver.resolve_round(combat) }

          Orders.set_move(talon, 0, 3)
          Resolver.resolve_round(combat)

          expect(talon.pos).to_not eq [ 5, 5 ]
        end
      end

      describe "venting strain directly" do
        it "reduces strain by the engineer's successes" do
          TestConfig.override([ "space", "strain", "regen" ], 0)
          covenant = spawn("Covenant", "Covenant", x: 10, y: 10)
          crew_with_char(covenant, "engineering", "Sato")
          covenant.update(strain: 10)

          Orders.set_vent(covenant)
          script(3)

          report = Resolver.resolve_round(combat)

          expect(covenant.strain).to eq 7
          expect(report[:engineering].first[:vented]).to eq 3
        end
      end

      describe "the botch source" do
        it "adds strain to the acting ship on a botched roll" do
          TestConfig.override([ "space", "strain", "regen" ], 0)
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          crew_with_char(talon, "pilot", "Rhee")
          Orders.set_evade(talon)
          script(-1)

          Resolver.resolve_round(combat)

          expect(talon.strain).to eq SpaceConfig.strain_on_botch
        end

        it "reports :strained_out only on the round it crosses the threshold" do
          TestConfig.override([ "space", "strain", "regen" ], 0)
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          crew_with_char(talon, "pilot", "Rhee")
          talon.update(strain: talon.strain_threshold - 1)
          Orders.set_evade(talon)
          script(-1)

          report = Resolver.resolve_round(combat)

          expect(report[:strained_out]).to eq [ "Talon One" ]
        end
      end
    end
  end
end
