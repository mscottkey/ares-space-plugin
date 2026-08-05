# Loads the production rules against the in-memory harness so the round
# resolver can be exercised without Redis or a running game.

PLUGIN_ROOT = File.expand_path("..", __dir__)

require_relative "spec_helper_standalone"

RSpec.configure do |config|
  config.before(:each) do
    AresMUSH::TestWorld.reset!
    AresMUSH::FS3Skills.reset!
    AresMUSH::Character.reset!
  end
end
