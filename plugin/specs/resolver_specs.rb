require_relative "spec_helper"

module AresMUSH
  module Space
    describe Resolver do

      let(:sector) { TestSector.new(id: 1, name: "Concord Graveyard", width: 20, height: 20) }
      let(:combat) { TestCombat.new(sector) }

      # Places a ship in the in-memory world.
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

      # The rolls the round will consume, in order.
      def script(*successes)
        FS3Skills.scripted_successes = successes.flatten
      end

      describe "movement" do
        it "moves a ship along its ordered heading" do
          talon = spawn("Talon One", "Talon", x: 5, y: 10, facing: 0)
          Orders.set_move(talon, 0, 3)   # north, speed 3

          Resolver.resolve_round(combat)

          expect(talon.pos).to eq [ 5, 7 ]
          expect(talon.facing).to eq 0
        end

        it "caps speed at what the hull can manage" do
          talon = spawn("Talon One", "Talon", x: 5, y: 10, facing: 0)
          Orders.set_move(talon, 0, 99)

          report = Resolver.resolve_round(combat)

          expect(talon.pos).to eq [ 5, 6 ]   # Talon speed is 4
          expect(report[:moves].first[:speed_limited]).to be true
        end

        it "turns only as far as agility allows and reports it" do
          # A Talon has agility 2; asking for a 4-step turn should get 2.
          talon = spawn("Talon One", "Talon", x: 10, y: 10, facing: 0)
          Orders.set_move(talon, 4, 1)      # from N to S

          report = Resolver.resolve_round(combat)

          expect(talon.facing).to eq 2      # turned N -> NE -> E only
          expect(report[:moves].first[:turn_limited]).to be true
        end

        it "turns the short way around the compass" do
          talon = spawn("Talon One", "Talon", x: 10, y: 10, facing: 0)
          Orders.set_move(talon, 6, 0)      # N to W: shorter counter-clockwise

          Resolver.resolve_round(combat)

          expect(talon.facing).to eq 6      # 2 steps counter-clockwise, exactly agility
        end

        it "keeps ships inside the sector" do
          talon = spawn("Talon One", "Talon", x: 1, y: 1, facing: 0)
          Orders.set_move(talon, 0, 4)

          Resolver.resolve_round(combat)

          expect(talon.pos[1]).to eq 0
        end

        # Found by running the plugin on a live game: a pilot closing to
        # contact flew onto the target's square. Co-located, there is no
        # bearing between them, so no hardpoint could bear and the fight
        # deadlocked - reachable in one move by anyone who charges.
        it "stops short of an occupied cell instead of stacking" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5, facing: 4)
          spawn("Mote", "Swarm Mote", x: 5, y: 7, facing: 0)

          Orders.set_move(talon, 4, 4)      # would run straight through
          report = Resolver.resolve_round(combat)

          expect(talon.pos).to eq [ 5, 6 ]  # stopped one short
          expect(report[:moves].first[:blocked]).to be true
        end

        it "will not pass through a ship to reach open space beyond it" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5, facing: 4)
          spawn("Mote", "Swarm Mote", x: 5, y: 6, facing: 0)

          Orders.set_move(talon, 4, 4)
          Resolver.resolve_round(combat)

          expect(talon.pos).to eq [ 5, 5 ]  # blocked immediately
        end

        it "records the distance actually travelled as its speed" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5, facing: 4)
          spawn("Mote", "Swarm Mote", x: 5, y: 7, facing: 0)

          Orders.set_move(talon, 4, 4)
          Resolver.resolve_round(combat)

          expect(talon.speed).to eq 1       # not the 4 it was ordered
        end

        it "still bears on a target sharing its cell rather than deadlocking" do
          # A GM can place two ships in one cell even though movement
          # won't; combat must not become impossible when they do.
          attacker = spawn("Talon One", "Talon", x: 5, y: 5, facing: 0)
          target = spawn("Mote", "Swarm Mote", x: 5, y: 5, facing: 0)

          Orders.add_fire(attacker, "Mote", 0)
          script(4)

          report = Resolver.resolve_round(combat)

          expect(report[:attacks].first[:error]).to be_nil
          expect(report[:attacks].first[:hit]).to be true
          expect(target.sections["hull"]["hull"]).to be < 3
        end

        it "will not move a capital whose engines are gone" do
          covenant = spawn("Covenant", "Covenant", x: 10, y: 10, facing: 0)
          sections = covenant.sections
          sections["aft"]["hull"] = 0       # aft holds the engines
          covenant.update(sections: sections)

          Orders.set_move(covenant, 0, 1)
          Resolver.resolve_round(combat)

          expect(covenant.pos).to eq [ 10, 10 ]
        end
      end

      describe "evasion" do
        it "banks the pilot's successes as the round's defense" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          crew_with_char(talon, "pilot", "Rhee")
          Orders.set_evade(talon)
          script(3)

          report = Resolver.resolve_round(combat)

          expect(report[:evades].first[:margin]).to eq 3
          expect(report[:evades].first[:roller]).to eq "Rhee"
        end

        it "rolls the pilot's Piloting skill with an agility bonus" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          crew_with_char(talon, "pilot", "Rhee")
          Orders.set_evade(talon)
          script(2)

          Resolver.resolve_round(combat)

          roll = FS3Skills.roll_log.first
          expect(roll[:ability]).to eq "Piloting"
          expect(roll[:modifier]).to eq 2     # Talon agility
        end
      end

      describe "attacks" do
        it "hits, burns shields first, and reports the section struck" do
          attacker = spawn("Talon One", "Talon", x: 5, y: 5, facing: 4)   # facing south
          target = spawn("Mote", "Swarm Mote", x: 5, y: 6, facing: 0)
          crew_with_char(attacker, "pilot", "Rhee")

          Orders.add_fire(attacker, "Mote", 0)   # Light Cannon, forward arc
          script(3)

          report = Resolver.resolve_round(combat)
          attack = report[:attacks].first

          expect(attack[:hit]).to be true
          expect(attack[:target]).to eq "Mote"
          # Swarm Mote has no shields, so damage lands on hull: 3 base
          # plus 2 for beating the defender by 3.
          expect(target.sections["hull"]["hull"]).to be < 3
        end

        it "misses when the target's banked evasion beats the gunner" do
          attacker = spawn("Talon One", "Talon", x: 5, y: 5, facing: 4)
          target = spawn("Talon Two", "Talon", x: 5, y: 6, facing: 0)
          crew_with_char(attacker, "pilot", "Rhee")
          crew_with_char(target, "pilot", "Vance")

          Orders.add_fire(attacker, "Talon Two", 0)
          Orders.set_evade(target)
          script(4, 2)   # evade rolls first (4), then the attack (2)

          report = Resolver.resolve_round(combat)
          attack = report[:attacks].first

          expect(attack[:hit]).to be false
          expect(attack[:evade]).to eq 4
          expect(target.sections["hull"]["shields"]).to eq 6   # untouched
        end

        it "refuses a shot whose hardpoint arc does not bear on the target" do
          # Attacker faces north; target sits due south, in the aft arc,
          # while the Light Cannon is a forward mount.
          attacker = spawn("Talon One", "Talon", x: 5, y: 5, facing: 0)
          spawn("Mote", "Swarm Mote", x: 5, y: 7)
          Orders.add_fire(attacker, "Mote", 0)
          script(5)

          report = Resolver.resolve_round(combat)

          expect(report[:attacks].first[:error]).to include "wrong_arc"
          expect(report[:attacks].first[:hit]).to be_nil
        end

        it "refuses a shot beyond the weapon's range" do
          attacker = spawn("Talon One", "Talon", x: 5, y: 5, facing: 4)
          spawn("Mote", "Swarm Mote", x: 5, y: 15)
          Orders.add_fire(attacker, "Mote", 0)   # Light Cannon reaches 3
          script(5)

          report = Resolver.resolve_round(combat)

          expect(report[:attacks].first[:error]).to include "out_of_range"
        end

        it "checks arcs against where ships end up, not where they started" do
          # The target starts dead ahead of the attacker but slides off to
          # its starboard beam; by the time guns speak, the forward mount
          # no longer bears.
          attacker = spawn("Talon One", "Talon", x: 5, y: 10, facing: 0)
          runner = spawn("Talon Two", "Talon", x: 5, y: 8, facing: 3)

          Orders.add_fire(attacker, "Talon Two", 0)
          Orders.set_move(runner, 3, 3)    # SE, ending abeam at 8,11
          script(5)

          report = Resolver.resolve_round(combat)

          expect(runner.pos).to eq [ 8, 11 ]
          expect(report[:attacks].first[:error]).to include "wrong_arc"
        end

        it "lets small ships shoot before capitals" do
          covenant = spawn("Covenant", "Covenant", x: 5, y: 5, facing: 4)
          talon = spawn("Talon One", "Talon", x: 5, y: 6, facing: 0)

          Orders.add_fire(covenant, "Talon One", 0)
          Orders.add_fire(talon, "Covenant", 0)
          script(1, 1)

          report = Resolver.resolve_round(combat)

          expect(report[:attacks].map { |a| a[:attacker] }).to eq [ "Talon One", "Covenant" ]
        end

        it "spends ammunition and refuses to fire an empty magazine" do
          attacker = spawn("Talon One", "Talon", x: 5, y: 5, facing: 4)
          # A Talon absorbs the first Seeker on its shields and survives,
          # so the magazine - not the target - is what runs out.
          spawn("Talon Two", "Talon", x: 5, y: 6, facing: 0)

          expect(attacker.ammo["1"]).to eq 4     # Seeker has 4 rounds
          Orders.add_fire(attacker, "Talon Two", 1)
          script(2)
          Resolver.resolve_round(combat)
          expect(attacker.ammo["1"]).to eq 3

          attacker.update(ammo: { "1" => 0 })
          Orders.add_fire(attacker, "Talon Two", 1)
          script(5)
          report = Resolver.resolve_round(combat)

          expect(report[:attacks].first[:error]).to include "out_of_ammo"
        end
      end

      describe "silhouette and scale" do
        it "lets a fighter cripple a capital's section but never breach it" do
          talon = spawn("Talon One", "Talon", x: 10, y: 9, facing: 4)
          covenant = spawn("Covenant", "Covenant", x: 10, y: 10, facing: 0)

          # Strip the struck section's shields so damage reaches hull.
          sections = covenant.sections
          sections["fore"]["shields"] = 0
          covenant.update(sections: sections)

          12.times do
            Orders.add_fire(talon, "Covenant", 0)
            script(8)
            Resolver.resolve_round(combat)
          end

          expect(covenant.sections["fore"]["hull"]).to eq 1   # capped, not gutted
          expect(covenant.destroyed?).to be false
        end

        it "gives a fighter a bonus to hit something capital-sized" do
          talon = spawn("Talon One", "Talon", x: 10, y: 9, facing: 4)
          spawn("Covenant", "Covenant", x: 10, y: 10, facing: 0)
          crew_with_char(talon, "pilot", "Rhee")

          Orders.add_fire(talon, "Covenant", 0)
          script(3)
          Resolver.resolve_round(combat)

          # +3 silhouette (clamped) and +1 point blank.
          expect(FS3Skills.roll_log.first[:modifier]).to eq 4
        end

        it "penalizes a capital gun tracking a fighter" do
          covenant = spawn("Covenant", "Covenant", x: 10, y: 10, facing: 0)
          spawn("Talon One", "Talon", x: 10, y: 9, facing: 4)
          crew_with_char(covenant, "gunnery", "Okafor")

          Orders.add_fire(covenant, "Talon One", 0)   # Heavy Battery, forward
          script(3)
          Resolver.resolve_round(combat)

          # -3 silhouette, -3 capital-vs-small, +1 point blank.
          expect(FS3Skills.roll_log.first[:modifier]).to eq(-5)
          expect(FS3Skills.roll_log.first[:ability]).to eq "Gunnery"
        end

        it "kills a fighter outright with a capital hit" do
          covenant = spawn("Covenant", "Covenant", x: 10, y: 10, facing: 0)
          talon = spawn("Talon One", "Talon", x: 10, y: 9, facing: 4)

          Orders.add_fire(covenant, "Talon One", 0)
          script(9)

          report = Resolver.resolve_round(combat)

          expect(talon.destroyed?).to be true
          expect(report[:destroyed]).to include "Talon One"
        end
      end

      describe "damage direction" do
        it "damages the section facing the shooter" do
          covenant = spawn("Covenant", "Covenant", x: 10, y: 10, facing: 0)   # bow north
          # Attacker sits due west, so the shot lands on the port side.
          raider = spawn("Maw", "Swarm Maw", x: 7, y: 10, facing: 1)

          Orders.add_fire(raider, "Covenant", 0)   # forward-arc Heavy Battery
          script(4)

          report = Resolver.resolve_round(combat)
          attack = report[:attacks].first

          expect(attack[:hit]).to be true
          expect(attack[:section]).to eq "port"
          expect(covenant.sections["port"]["shields"]).to be < 8
          expect(covenant.sections["fore"]["shields"]).to eq 10
        end

        it "knocks out the systems in a gutted section" do
          covenant = spawn("Covenant", "Covenant", x: 10, y: 10, facing: 0)
          # The Maw must actually point its bow gun at the Covenant.
          maw = spawn("Maw", "Swarm Maw", x: 10, y: 9, facing: 4)

          expect(covenant.system_online?("sensors")).to be true

          6.times do
            Orders.add_fire(maw, "Covenant", 0)
            script(9)
            Resolver.resolve_round(combat)
          end

          expect(covenant.sections["fore"]["hull"]).to eq 0
          expect(covenant.system_online?("sensors")).to be false
        end
      end

      describe "engineering" do
        it "repairs hull equal to the engineer's successes" do
          covenant = spawn("Covenant", "Covenant", x: 10, y: 10)
          crew_with_char(covenant, "engineering", "Sato")

          sections = covenant.sections
          sections["aft"]["hull"] = 4
          covenant.update(sections: sections)

          Orders.set_repair(covenant, "aft")
          script(3)

          report = Resolver.resolve_round(combat)

          expect(covenant.sections["aft"]["hull"]).to eq 7
          expect(report[:engineering].first[:repaired]).to eq 3
          expect(FS3Skills.roll_log.first[:ability]).to eq "Technician"
        end

        it "never repairs past the section's maximum" do
          covenant = spawn("Covenant", "Covenant", x: 10, y: 10)
          crew_with_char(covenant, "engineering", "Sato")

          sections = covenant.sections
          sections["aft"]["hull"] = 11
          covenant.update(sections: sections)

          Orders.set_repair(covenant, "aft")
          script(6)
          Resolver.resolve_round(combat)

          expect(covenant.sections["aft"]["hull"]).to eq 12
        end
      end

      describe "sensors" do
        it "extends detection range on a successful sweep" do
          covenant = spawn("Covenant", "Covenant", x: 10, y: 10)
          crew_with_char(covenant, "sensors", "Idris")
          Orders.set_sweep(covenant)
          script(4)

          report = Resolver.resolve_round(combat)

          expect(report[:sweeps].first[:range]).to eq 10   # passive 6 + 4
          expect(FS3Skills.roll_log.first[:ability]).to eq "Alertness"
        end

        it "clears the sweep once the round is over" do
          covenant = spawn("Covenant", "Covenant", x: 10, y: 10)
          crew_with_char(covenant, "sensors", "Idris")
          Orders.set_sweep(covenant)
          script(4)

          Resolver.resolve_round(combat)

          expect(covenant.sweep_range).to eq 0
        end
      end

      describe "round bookkeeping" do
        it "advances the round and clears orders" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          Orders.set_move(talon, 0, 1)

          report = Resolver.resolve_round(combat)

          expect(report[:round]).to eq 1
          expect(combat.round).to eq 1
          expect(talon.orders).to be_empty
        end

        it "clears banked evasion so it does not carry into the next round" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          crew_with_char(talon, "pilot", "Rhee")
          Orders.set_evade(talon)
          script(3)
          Resolver.resolve_round(combat)
          expect(talon.evade_margin).to eq 3

          Resolver.resolve_round(combat)
          expect(talon.evade_margin).to eq 0
        end

        it "regenerates shields on ships that were not hit" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          sections = talon.sections
          sections["hull"]["shields"] = 2
          talon.update(sections: sections)

          Resolver.resolve_round(combat)

          expect(talon.sections["hull"]["shields"]).to eq 3
        end

        it "does not regenerate the section that just took fire" do
          attacker = spawn("Talon One", "Talon", x: 5, y: 5, facing: 4)
          target = spawn("Talon Two", "Talon", x: 5, y: 6, facing: 0)

          Orders.add_fire(attacker, "Talon Two", 0)
          script(3)
          Resolver.resolve_round(combat)

          # 3 base damage +2 margin bonus = 5 off a 6-point bubble, and
          # no regen this round because it was struck.
          expect(target.sections["hull"]["shields"]).to eq 1
        end

        it "logs a summary of the round" do
          attacker = spawn("Talon One", "Talon", x: 5, y: 5, facing: 4)
          spawn("Mote", "Swarm Mote", x: 5, y: 6)
          Orders.add_fire(attacker, "Mote", 0)
          script(2)

          Resolver.resolve_round(combat)

          expect(combat.log.last).to include "1 shot(s), 1 hit(s)"
        end
      end

      describe "unmanned and NPC stations" do
        it "rolls a flat NPC pool rather than a character's skill" do
          mote = spawn("Mote", "Swarm Mote", x: 5, y: 5, facing: 4)
          spawn("Talon One", "Talon", x: 5, y: 6)
          Crew.assign(mote, "pilot", Crew.npc_key(5))

          Orders.add_fire(mote, "Talon One", 0)
          script(2)
          Resolver.resolve_round(combat)

          roll = FS3Skills.roll_log.first
          expect(roll[:char]).to be_nil
          # 5 NPC dice, +0 silhouette (both 3), +1 point blank.
          expect(roll[:dice]).to eq 6
        end

        it "falls back to untrained dice for an unmanned station" do
          mote = spawn("Mote", "Swarm Mote", x: 5, y: 5, facing: 4)
          spawn("Talon One", "Talon", x: 5, y: 6)

          Orders.add_fire(mote, "Talon One", 0)
          script(1)
          Resolver.resolve_round(combat)

          # untrained_dice 2, +1 point blank.
          expect(FS3Skills.roll_log.first[:dice]).to eq 3
        end
      end

      describe "hex sectors" do
        let(:sector) { TestSector.new(id: 2, name: "Hex Sector", geometry: "hex", width: 20, height: 20) }

        it "moves along hex facings" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5, facing: 1)   # E
          Orders.set_move(talon, 1, 3)

          Resolver.resolve_round(combat)

          expect(talon.pos).to eq [ 8, 5 ]
        end

        it "resolves attacks with hex arcs" do
          attacker = spawn("Talon One", "Talon", x: 5, y: 5, facing: 1) # E
          target = spawn("Mote", "Swarm Mote", x: 6, y: 5)             # due E
          Orders.add_fire(attacker, "Mote", 0)
          script(3)

          report = Resolver.resolve_round(combat)

          expect(report[:attacks].first[:hit]).to be true
          expect(target.sections["hull"]["hull"]).to be < 3
        end
      end
    end
  end
end
