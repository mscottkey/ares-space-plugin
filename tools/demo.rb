# Runs a scripted engagement against the in-memory harness and prints
# what the crew would see. No game server, no Redis - this is here so the
# console and the round report can be eyeballed while tuning.
#
#   ruby tools/demo.rb

require_relative "../plugin/specs/spec_helper_standalone"

include AresMUSH

# Ares colour codes are %x plus a single letter; matching more than one
# letter eats the first character of the text that follows.
def strip_codes(text)
  text.gsub(/%x[a-z]/, "").gsub(/%l[hf]/, "").gsub(/%r/, "\n")
end

sector = TestSector.new(id: 1, name: "Concord Graveyard", width: 16, height: 12)
TestWorld.reset!
FS3Skills.reset!

def spawn(sector, name, klass, opts = {})
  ship = TestShip.new(opts.merge(name: name, ship_class: klass, sector: sector,
                                 id: TestWorld.ships.count + 1))
  TestWorld.ships << ship
  ship
end

covenant = spawn(sector, "Covenant", "Covenant", x: 3, y: 6, facing: 2, faction: "UCC")
talon    = spawn(sector, "Talon One", "Talon", x: 6, y: 5, facing: 2, faction: "UCC")
maw      = spawn(sector, "Maw", "Swarm Maw", x: 11, y: 5, facing: 6, faction: "Swarm")
mote     = spawn(sector, "Mote Alpha", "Swarm Mote", x: 9, y: 7, facing: 6, faction: "Swarm")

TestWorld.terrain << begin
  terr = Object.new
  def terr.terrain_type; "debris"; end
  def terr.sector_id; 1; end
  def terr.pos; [ 8, 3 ]; end
  def terr.radius; 1; end
  def terr.covers?(geometry, position)
    Space::Geometry.distance(geometry, pos, position) <= radius
  end
  terr
end

pilot = Character.register(TestCharacter.new(1, "Rhee"))
Space::Crew.assign(talon, "pilot", Space::Crew.char_key(pilot))
gunner = Character.register(TestCharacter.new(2, "Okafor"))
Space::Crew.assign(covenant, "gunnery", Space::Crew.char_key(gunner))
Space::Crew.assign(maw, "gunnery", Space::Crew.npc_key(4))

puts "=" * 70
puts "TACTICAL PLOT as read from Talon One"
puts "=" * 70
puts strip_codes(Space::Display.render_grid(sector, talon))
puts
puts "CONTACTS"
puts strip_codes(Space::Display.render_contacts(talon))
puts

puts "=" * 70
puts "ORDERS"
puts "=" * 70
Space::Orders.set_move(talon, 2, 3)              # come east at speed 3
Space::Orders.add_fire(talon, "Mote Alpha", 0)   # cannons on the mote
Space::Orders.set_evade(maw)
Space::Orders.add_fire(covenant, "Maw", 0)       # bow battery on the hulk
puts "  Talon One: come to E, speed 3; forward cannon on Mote Alpha"
puts "  Covenant:  bow Heavy Battery on Maw"
puts "  Maw:       evasive"
puts

# Scripted rolls, in resolution order: evade, then attacks smallest first.
FS3Skills.scripted_successes = [ 2, 4, 3 ]

combat = TestCombat.new(sector)
report = Space::Resolver.resolve_round(combat)

puts "=" * 70
puts strip_codes(Space::Display.render_report(report, sector.geometry))
puts

puts "=" * 70
puts "TACTICAL PLOT after the round"
puts "=" * 70
puts strip_codes(Space::Display.render_grid(sector, talon))
puts
puts "COVENANT STATUS"
puts strip_codes(Space::Display.render_sections(covenant))
puts
puts "MAW STATUS"
puts strip_codes(Space::Display.render_sections(maw))
