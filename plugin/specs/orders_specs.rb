require_relative "spec_helper"

module AresMUSH
  module Space
    # Orders.issue is the single path both the in-game commands and the
    # web portal call, so these cover the behaviour of both surfaces.
    describe Orders do

      let(:sector) { TestSector.new(id: 1, name: "Test Sector", width: 20, height: 20) }

      def spawn(name, ship_class, opts = {})
        ship = TestShip.new(opts.merge(id: TestWorld.ships.count + 1,
                                       name: name,
                                       ship_class: ship_class,
                                       sector: sector))
        TestWorld.ships << ship
        ship
      end

      describe "helm orders" do
        it "accepts a heading by name, case-insensitively" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          result = Orders.issue(talon, :helm, heading: "ne", speed: 2)

          expect(result[:ok]).to be true
          expect(Orders.get(talon, "helm")["heading"]).to eq 1
          expect(Orders.get(talon, "helm")["speed"]).to eq 2
        end

        it "refuses a heading the geometry doesn't have" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          result = Orders.issue(talon, :helm, heading: "up")

          expect(result[:ok]).to be false
          expect(result[:error]).to include "bad_heading"
          expect(Orders.get(talon, "helm")).to be_nil
        end

        it "caps excessive speed and warns rather than refusing" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          result = Orders.issue(talon, :helm, heading: "N", speed: 99)

          expect(result[:ok]).to be true
          expect(result[:warnings].first).to include "speed_capped"
          expect(Orders.get(talon, "helm")["speed"]).to eq 4
        end

        it "warns when the turn exceeds what the hull can manage" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5, facing: 0)
          result = Orders.issue(talon, :helm, heading: "S", speed: 1)

          expect(result[:ok]).to be true
          expect(result[:warnings].join).to include "turn_will_be_limited"
        end

        it "defaults to the hull's best speed when none is given" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          Orders.issue(talon, :helm, heading: "N")
          expect(Orders.get(talon, "helm")["speed"]).to eq 4
        end
      end

      describe "fire orders" do
        it "queues a shot at a contact in the sector" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5, facing: 4)
          spawn("Mote", "Swarm Mote", x: 5, y: 6)

          result = Orders.issue(talon, :fire, target: "mote", hardpoint: 0)

          expect(result[:ok]).to be true
          expect(Orders.fire_orders(talon).first["target"]).to eq "Mote"
        end

        it "refuses a target that isn't there" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          result = Orders.issue(talon, :fire, target: "Ghost")

          expect(result[:ok]).to be false
          expect(result[:error]).to include "target_not_found"
        end

        it "refuses a shot beyond the weapon's range" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5, facing: 4)
          spawn("Mote", "Swarm Mote", x: 5, y: 18)

          result = Orders.issue(talon, :fire, target: "Mote", hardpoint: 0)

          expect(result[:ok]).to be false
          expect(result[:error]).to include "out_of_range"
        end

        it "queues but warns when the hardpoint does not yet bear" do
          # Target is astern; the order stands because the ship may come
          # about before the round resolves.
          talon = spawn("Talon One", "Talon", x: 5, y: 5, facing: 0)
          spawn("Mote", "Swarm Mote", x: 5, y: 7)

          result = Orders.issue(talon, :fire, target: "Mote", hardpoint: 0)

          expect(result[:ok]).to be true
          expect(result[:warnings].join).to include "arc_warning"
          expect(Orders.fire_orders(talon).count).to eq 1
        end

        it "refuses a hardpoint the ship does not have" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5, facing: 4)
          spawn("Mote", "Swarm Mote", x: 5, y: 6)

          result = Orders.issue(talon, :fire, target: "Mote", hardpoint: 9)

          expect(result[:ok]).to be false
          expect(result[:error]).to include "no_such_hardpoint"
        end

        it "allows several hardpoints to be queued in one round" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5, facing: 4)
          spawn("Mote", "Swarm Mote", x: 5, y: 6)

          Orders.issue(talon, :fire, target: "Mote", hardpoint: 0)
          Orders.issue(talon, :fire, target: "Mote", hardpoint: 1)

          expect(Orders.fire_orders(talon).count).to eq 2
        end
      end

      describe "repair orders" do
        it "accepts a real section" do
          covenant = spawn("Covenant", "Covenant", x: 5, y: 5)
          result = Orders.issue(covenant, :repair, section: "AFT")

          expect(result[:ok]).to be true
          expect(Orders.get(covenant, "engineering")["section"]).to eq "aft"
        end

        it "refuses a section the ship doesn't have" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          result = Orders.issue(talon, :repair, section: "nose")

          expect(result[:ok]).to be false
          expect(result[:error]).to include "no_such_section"
        end
      end

      describe "other orders" do
        it "handles evade, hold, sweep and clear" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)

          expect(Orders.issue(talon, :evade)[:ok]).to be true
          expect(Orders.get(talon, "helm")["action"]).to eq "evade"

          expect(Orders.issue(talon, :hold)[:ok]).to be true
          expect(Orders.get(talon, "helm")["action"]).to eq "hold"

          expect(Orders.issue(talon, :sweep)[:ok]).to be true
          expect(Orders.get(talon, "sensors")["action"]).to eq "sweep"

          expect(Orders.issue(talon, :clear)[:ok]).to be true
          expect(talon.orders).to be_empty
        end

        it "rejects an order it doesn't recognise" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          result = Orders.issue(talon, :warp)

          expect(result[:ok]).to be false
          expect(result[:error]).to include "unknown_order"
        end

        it "refuses orders to a destroyed ship but still lets them be cleared" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          Orders.set_move(talon, 0, 1)
          talon.update(status: "destroyed")

          expect(Orders.issue(talon, :helm, heading: "N")[:ok]).to be false
          expect(Orders.issue(talon, :clear)[:ok]).to be true
        end
      end

      describe :awaiting_orders? do
        it "waits on a crewed ship with nothing ordered" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          Crew.assign(talon, "pilot", Crew.npc_key(3))
          expect(Orders.awaiting_orders?(talon)).to be true

          Orders.issue(talon, :hold)
          expect(Orders.awaiting_orders?(talon)).to be false
        end

        it "never waits on an empty hull" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          expect(Orders.awaiting_orders?(talon)).to be false
        end
      end
    end
  end
end
