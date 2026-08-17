# Loads the plugin rules and the in-memory harness WITHOUT rspec, so
# tools/demo.rb can drive a scenario from a plain ruby run.

require_relative "../helpers/geometry"
require_relative "../helpers/astro"
require_relative "../helpers/rules"
require_relative "../helpers/ship_behavior"
require_relative "../helpers/space_config"
require_relative "../dice/dice"
require_relative "../dice/fs3_adapter"
require_relative "../helpers/ships"
require_relative "../helpers/crew"
require_relative "../helpers/boarding"
require_relative "../helpers/orders"
require_relative "../helpers/sensors"
require_relative "../helpers/resolver"
require_relative "../helpers/engagements"
require_relative "../helpers/display"
require_relative "../helpers/systems"
require_relative "../helpers/docking"
require_relative "../helpers/system_display"
require_relative "../helpers/web_data"

# Must come last: it points the lookups at the in-memory world.
require_relative "support/harness"
require_relative "support/fake_dice"
