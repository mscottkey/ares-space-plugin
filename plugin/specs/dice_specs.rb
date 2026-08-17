require_relative "spec_helper"

module AresMUSH
  module Space
    module Dice
      # Defined out here, not inside the describe block below: a module
      # opened inside `describe` nests under RSpec's anonymous example-
      # group class, so it would never be reachable at the constant path
      # the lookup actually resolves.

      # Deliberately incomplete, to prove check_config catches it.
      module HalfAdapter
        def self.available?; true; end
        def self.known_ability?(_a); true; end
      end

      module AngryAdapter
        def self.available?; true; end
        def self.known_ability?(_a); true; end
        def self.roll_ability(_c, _a, _m = 0); {}; end
        def self.roll_pool(_r, _m = 0); {}; end
        def self.check_config(_s); raise "no"; end
      end
    end

    describe Dice do

      def use(system)
        TestConfig.override([ "space", "dice_system" ], system)
      end

      describe :adapter_for do
        it "defaults to fs3 when nothing is configured" do
          expect(Dice.adapter).to eq Dice::Fs3Adapter
        end

        it "resolves a bare name to one of ours" do
          expect(Dice.adapter_for("fake")).to eq Dice::FakeAdapter
        end

        it "is case-insensitive about the configured name" do
          expect(Dice.adapter_for("FAKE")).to eq Dice::FakeAdapter
        end

        it "resolves an underscored name to its camel-cased module" do
          expect(Dice.adapter_for("fs3")).to eq Dice::Fs3Adapter
        end

        it "is nil for a name nobody installed" do
          expect(Dice.adapter_for("nonsense")).to be_nil
        end

        it "is nil for blank or missing names" do
          expect(Dice.adapter_for(nil)).to be_nil
          expect(Dice.adapter_for("")).to be_nil
          expect(Dice.adapter_for("   ")).to be_nil
        end

        # A bare name is always looked up inside our own namespace, so an
        # arbitrary top-level constant can't be reached through it.
        it "does not resolve a bare name to some unrelated top-level constant" do
          expect(Dice.adapter_for("Kernel")).to be_nil
          expect(Dice.adapter_for("Object")).to be_nil
        end

        it "rejects a qualified name that isn't a constant path" do
          expect(Dice.adapter_for("foo bar::baz")).to be_nil
          expect(Dice.adapter_for("lowercase::thing")).to be_nil
        end

        # A fully-qualified name IS allowed to reach outside our
        # namespace - that's how a third-party plugin ships its own
        # adapter - so the contract check is what keeps it honest.
        it "resolves a fully-qualified constant, leaving the contract check to reject a non-adapter" do
          expect(Dice.adapter_for("AresMUSH::Space::Dice::FakeAdapter")).to eq Dice::FakeAdapter
          expect(Dice.usable_adapter).not_to eq Kernel
        end
      end

      describe :missing_contract_methods do
        it "is empty for a complete adapter" do
          expect(Dice.missing_contract_methods(Dice::Fs3Adapter)).to eq []
        end

        it "names everything a non-adapter is missing" do
          expect(Dice.missing_contract_methods(Kernel)).to eq Dice::CONTRACT
        end

        it "names the whole contract when there's no adapter at all" do
          expect(Dice.missing_contract_methods(nil)).to eq Dice::CONTRACT
        end
      end

      describe :roll do
        before(:each) { use("fake") }

        it "routes through the configured system" do
          Dice.roll_ability(nil, "Piloting", 2)
          expect(Dice::FakeAdapter.calls.first[:kind]).to eq :ability
        end

        it "passes the modifier through verbatim, negatives included" do
          Dice.roll_ability(nil, "Piloting", -3)
          expect(Dice::FakeAdapter.calls.first[:modifier]).to eq(-3)
        end

        it "hands roll_pool the raw rating and modifier separately" do
          Dice.roll_pool(5, 2)
          call = Dice::FakeAdapter.calls.first
          expect(call[:rating]).to eq 5
          expect(call[:modifier]).to eq 2
        end

        it "carries system-specific extras through untouched" do
          result = Dice.roll_ability(nil, "Piloting")
          expect(result[:advantage]).to eq 2
          expect(result[:symbols]).to eq [ :triumph ]
        end

        it "coerces successes to an Integer" do
          Dice::FakeAdapter.script({ successes: "4" })
          expect(Dice.roll_ability(nil, "Piloting")[:successes]).to eq 4
        end

        # Degrading to zero rather than raising matters because the
        # resolver spends ammo before it rolls - an exception escaping
        # here would abandon the round half-applied.
        it "degrades to no successes rather than raising when the system blows up" do
          Dice::FakeAdapter.raise_on_roll = true
          expect { @r = Dice.roll_ability(nil, "Piloting") }.not_to raise_error
          expect(@r[:successes]).to eq 0
        end

        it "degrades to no successes when the system is unavailable" do
          Dice::FakeAdapter.is_available = false
          expect(Dice.roll_ability(nil, "Piloting")[:successes]).to eq 0
        end

        it "degrades to no successes when no system is installed" do
          use("nonsense")
          expect(Dice.roll_ability(nil, "Piloting")[:successes]).to eq 0
        end

        it "degrades when the system returns something that isn't a result" do
          Dice::FakeAdapter.script(nil)
          expect(Dice.roll_ability(nil, "Piloting")[:successes]).to eq 0
        end

        it "degrades when the system returns a hash with no successes" do
          Dice::FakeAdapter.script({ advantage: 3 })
          expect(Dice.roll_ability(nil, "Piloting")[:successes]).to eq 0
        end
      end

      describe :available? do
        it "is true for the default system" do
          expect(Dice.available?).to be true
        end

        it "is false when the configured system says it isn't" do
          use("fake")
          Dice::FakeAdapter.is_available = false
          expect(Dice.available?).to be false
        end

        it "is false when the configured system doesn't exist" do
          use("nonsense")
          expect(Dice.available?).to be false
        end
      end

      describe :known_ability? do
        it "asks the configured system" do
          use("fake")
          Dice::FakeAdapter.known = [ "Flying" ]
          expect(Dice.known_ability?("Flying")).to be true
          expect(Dice.known_ability?("Swimming")).to be false
        end

        it "is false when no system is available, rather than raising" do
          use("nonsense")
          expect(Dice.known_ability?("Piloting")).to be false
        end
      end

      describe :check_config do
        it "passes for a stock game" do
          expect(Dice.check_config).to eq []
        end

        it "names an uninstalled system and lists what is installed" do
          use("nonsense")
          errors = Dice.check_config
          expect(errors.count).to eq 1
          expect(errors.first).to include "nonsense"
          expect(errors.first).to include "fs3"
        end

        it "names the methods a half-written adapter is missing" do
          use("AresMUSH::Space::Dice::HalfAdapter")
          errors = Dice.check_config
          expect(errors.count).to eq 1
          expect(errors.first).to include "roll_ability"
          expect(errors.first).to include "roll_pool"
        end

        it "reports a system that is installed but unavailable" do
          use("fake")
          Dice::FakeAdapter.is_available = false
          expect(Dice.check_config.first).to include "not available"
        end

        it "surfaces the system's own config complaints" do
          use("fake")
          Dice::FakeAdapter.config_errors = [ "space: something is wrong" ]
          expect(Dice.check_config).to eq [ "space: something is wrong" ]
        end

        it "rescues a system that raises while checking itself" do
          use("AresMUSH::Space::Dice::AngryAdapter")
          expect { @errors = Dice.check_config }.not_to raise_error
          expect(@errors.first).to include "raised"
        end
      end

    end
  end
end
