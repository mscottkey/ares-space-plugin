require_relative "spec_helper"

module AresMUSH
  module Space
    describe WebData do

      let(:sector) { TestSector.new(id: 1, name: "Concord Graveyard", width: 20, height: 20) }

      def spawn(name, ship_class, opts = {})
        ship = TestShip.new(opts.merge(id: TestWorld.ships.count + 1,
                                       name: name,
                                       ship_class: ship_class,
                                       sector: sector))
        TestWorld.ships << ship
        ship
      end

      describe :ship_detail do
        it "reports pools, sections and hardpoints" do
          talon = spawn("Talon One", "Talon", x: 4, y: 5, facing: 2, faction: "UCC")
          data = WebData.ship_detail(talon)

          expect(data[:name]).to eq "Talon One"
          expect(data[:faction]).to eq "UCC"
          expect(data[:x]).to eq 4
          expect(data[:facing_name]).to eq "E"
          expect(data[:silhouette]).to eq 3
          expect(data[:shields]).to eq 6
          expect(data[:hull]).to eq 4
          expect(data[:small_craft]).to be true
          expect(data[:hardpoints].count).to eq 2
          expect(data[:sections].first[:name]).to eq "hull"
        end

        it "flags a wrecked section and the systems it took down" do
          covenant = spawn("Covenant", "Covenant", x: 10, y: 10)
          sections = covenant.sections
          sections["fore"]["hull"] = 0
          covenant.update(sections: sections)

          data = WebData.ship_detail(covenant)
          fore = data[:sections].find { |s| s[:name] == "fore" }

          expect(fore[:destroyed]).to be true
          expect(data[:systems_offline]).to include "sensors"
        end

        it "includes pending orders so the page can show them" do
          talon = spawn("Talon One", "Talon", x: 4, y: 5)
          Orders.set_move(talon, 2, 3)
          Orders.add_fire(talon, "Mote", 0)

          orders = WebData.ship_detail(talon)[:orders]

          expect(orders[:any]).to be true
          expect(orders[:helm]["action"]).to eq "move"
          expect(orders[:fire].first[:weapon]).to eq "Light Cannon"
        end
      end

      describe :tactical do
        it "shows a crew only what their own sensors resolved" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          spawn("Mote", "Swarm Mote", x: 6, y: 5)          # close: identified
          spawn("Far Mote", "Swarm Mote", x: 19, y: 19)    # beyond sensor reach

          data = WebData.tactical(sector, talon, false)

          expect(data[:own_ship][:name]).to eq "Talon One"
          expect(data[:contacts].count).to eq 1
          expect(data[:contacts].first[:name]).to eq "Mote"
        end

        it "withholds the name and hull of an unidentified blip" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          # Inside passive range (6) but past the identification band.
          spawn("Mote", "Swarm Mote", x: 10, y: 5)

          contact = WebData.tactical(sector, talon, false)[:contacts].first

          expect(contact[:identified]).to be false
          expect(contact[:name]).to be_nil
          expect(contact[:hull]).to be_nil
          expect(contact[:faction]).to be_nil
          # Position still travels: the blip has to be drawable.
          expect(contact[:x]).to eq 10
        end

        it "gives staff with no ship the whole sector" do
          spawn("Talon One", "Talon", x: 1, y: 1)
          spawn("Far Mote", "Swarm Mote", x: 19, y: 19)

          data = WebData.tactical(sector, nil, true)

          expect(data[:gm_view]).to be true
          expect(data[:own_ship]).to be_nil
          expect(data[:contacts].count).to eq 2
        end

        it "gives a non-staff viewer with no ship nothing" do
          spawn("Talon One", "Talon", x: 1, y: 1)
          data = WebData.tactical(sector, nil, false)
          expect(data[:contacts]).to be_empty
        end

        it "reports geometry and facings so the browser can draw the grid" do
          hex_sector = TestSector.new(id: 2, name: "Hex", geometry: "hex", width: 10, height: 10)
          data = WebData.tactical(hex_sector, nil, true)

          expect(data[:geometry]).to eq "hex"
          expect(data[:facings]).to eq %w(NE E SE SW W NW)
        end

        it "lists ships still awaiting orders for staff only" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          Crew.assign(talon, "pilot", Crew.npc_key(3))

          expect(WebData.tactical(sector, nil, true)[:awaiting_orders]).to eq [ "Talon One" ]
          expect(WebData.tactical(sector, talon, false)[:awaiting_orders]).to eq []
        end

        it "includes terrain for the plot" do
          talon = spawn("Talon One", "Talon", x: 5, y: 5)
          terr = Object.new
          def terr.id; 7; end
          def terr.terrain_type; "debris"; end
          def terr.sector_id; 1; end
          def terr.pos; [ 6, 5 ]; end
          def terr.radius; 1; end
          def terr.covers?(geometry, position)
            Geometry.distance(geometry, pos, position) <= radius
          end
          TestWorld.terrain << terr

          terrain = WebData.tactical(sector, talon, false)[:terrain]
          expect(terrain.first[:type]).to eq "debris"
          expect(terrain.first[:radius]).to eq 1
        end
      end

      describe :system_map do
        # Real config (game/config/space_systems.yml), not a fixture -
        # this is the system the bug was reported against, moon and all.
        let(:map) { WebData.system_map("covenant_reach") }
        let(:by_key) { map[:bodies].each_with_object({}) { |b, h| h[b[:key]] = b } }

        it "sends the orbit period so the browser doesn't have to hardcode a pace" do
          expect(map[:orbit_period]).to eq Systems.orbit_layout["orbit_period"].to_f
        end

        it "puts a moon within its own orbit distance of its parent, not the star" do
          parent = by_key["p3"]
          moon = by_key["p3_moon"]

          dist = Math.hypot(parent[:x] - moon[:x], parent[:y] - moon[:y])

          expect(dist).to be_within(0.1).of(moon[:orbit_radius])
        end

        it "does not place a moon by its own independent bearing from the star" do
          parent = by_key["p3"]
          moon = by_key["p3_moon"]

          # The regression: moon config sets angle: 210 against the
          # parent's angle: 62. Positioned from the star at that angle,
          # the moon lands far outside its parent's own orbit - farther
          # from the star than the parent, in this system's numbers.
          dist_from_star = Math.hypot(map[:center] - moon[:x], map[:center] - moon[:y])
          parent_dist_from_star = Math.hypot(map[:center] - parent[:x], map[:center] - parent[:y])

          expect(dist_from_star).to be < parent_dist_from_star + moon[:orbit_radius] + 0.1
        end

        it "gives a moon its parent's ring rather than a radius of its own" do
          parent = by_key["p3"]
          moon = by_key["p3_moon"]

          expect(moon[:ring]).to eq parent[:ring]
        end

        it "falls back to a near-star position for a moon with a bad parent key" do
          data = WebData.body_map_entry("covenant_reach",
            { "key" => "orphan", "parent" => "nonexistent", "angle" => 45, "moon_orbit" => 10 },
            map[:center], Systems.orbit_layout)

          expect(data[:x]).to be_a(Float)
          expect(data[:y]).to be_a(Float)
        end

        # Ship markers: a ship simply parked at a body is already visible
        # through that body's own ships list/table row, and its marker
        # never tracked the body's own orbit animation - the actual bug
        # report. So the map's ships[] only carries a ship that's doing
        # something worth a dedicated, independently-animated marker.
        def in_system(name, opts = {})
          ship = TestShip.new(opts.merge(id: TestWorld.ships.count + 1,
                                         name: name, ship_class: "Talon"))
          ship.system_key = "covenant_reach"
          TestWorld.ships << ship
          ship
        end

        def start_engagement_at(body_key)
          sector = SpaceSector.create(system_key: "covenant_reach", body_key: body_key)
          SpaceCombat.create(sector: sector, state: "active")
        end

        it "does not give a peacefully parked ship its own marker" do
          in_system("Talon One", location_key: "p1")

          expect(map[:ships]).to eq []
        end

        it "still reports a peacefully parked ship on own_ship" do
          ship = in_system("Talon One", location_key: "p1")

          own_ship = WebData.ship_map_entry(ship, by_key, map[:center], Systems.orbit_layout)

          expect(own_ship).not_to be_nil
          expect(own_ship[:location_name]).to eq "P1"
        end

        it "marks a ship at an engaged body, riding that body's position" do
          start_engagement_at("p1")
          in_system("Talon One", location_key: "p1")

          entry = map[:ships].first

          expect(entry[:name]).to eq "Talon One"
          expect(entry[:engaged]).to be true
          expect(entry[:x]).to eq by_key["p1"][:x]
          expect(entry[:y]).to eq by_key["p1"][:y]
        end

        it "lists an engaged body's present ships in engaged_ships too, for nested rendering" do
          start_engagement_at("p1")
          in_system("Talon One", location_key: "p1")

          expect(by_key["p1"][:engaged_ships].map { |s| s[:name] }).to eq [ "Talon One" ]
        end

        it "leaves engaged_ships empty for a body with nothing going on" do
          in_system("Talon One", location_key: "p1")

          expect(by_key["p1"][:engaged_ships]).to eq []
        end

        it "always marks a ring-anchored ship - there is no body to represent it otherwise" do
          in_system("Freedom", system_ring: 5, system_angle: 90.0)

          entry = map[:ships].first

          expect(entry[:name]).to eq "Freedom"
          expect(entry[:ring_anchored]).to be true
          expect(entry[:ring]).to eq 5
        end

        it "positions a ring-anchored ship along that ring at its stored angle" do
          ship = in_system("Freedom", system_ring: 2, system_angle: 0.0)

          entry = map[:ships].first
          radius = Astro.ring_radius(2, Systems.orbit_layout)

          expect(entry[:x]).to be_within(0.1).of(map[:center] + radius)
          expect(entry[:y]).to be_within(0.1).of(map[:center])
        end

        it "marks a ship under way, even mid-transit between two bodies" do
          ship = in_system("Talon One", location_key: "p1")
          Systems.set_course(ship, "p2")

          entry = map[:ships].find { |s| s[:name] == "Talon One" }

          expect(entry).not_to be_nil
          expect(entry[:in_transit]).to be true
        end

        it "gives a ship travelling to a bare ring a real destination name" do
          ship = in_system("Talon One", location_key: "p1")
          Systems.set_course(ship, "5")

          entry = map[:ships].find { |s| s[:name] == "Talon One" }

          expect(entry[:destination]).to eq "ring:5"
          expect(entry[:destination_name]).not_to be_nil
        end
      end

      describe :sector_summary do
        it "counts live ships and reports the engagement state" do
          spawn("Talon One", "Talon", x: 1, y: 1)
          dead = spawn("Wreck", "Talon", x: 2, y: 2)
          dead.update(status: "destroyed")

          summary = WebData.sector_summary(sector)

          expect(summary[:ship_count]).to eq 1
          expect(summary[:in_combat]).to be false
          expect(summary[:round]).to be_nil
        end
      end
    end
  end
end
