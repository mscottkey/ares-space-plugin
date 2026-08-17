module AresMUSH
  module Space
    module Dice

      # A dice system that is deliberately NOT FS3, so the specs can
      # prove the seam is real rather than accidentally FS3-shaped.
      #
      # It records every call it receives (which is how the specs check
      # what Crew passes down), lets a spec script whole result hashes
      # rather than bare success counts (so extras can be exercised), and
      # can be made unavailable or made to raise on demand.
      #
      # Lives in support/ rather than harness.rb because it is a distinct
      # concern, and is NOT named *_specs.rb because .rspec's pattern
      # would otherwise try to run it as a spec file. PluginManager skips
      # specs/ entirely, so it can never load on a real game.
      module FakeAdapter
        class << self
          attr_accessor :calls, :scripted, :is_available, :raise_on_roll, :config_errors, :known

          def reset!
            self.calls = []
            self.scripted = []
            self.is_available = true
            self.raise_on_roll = false
            self.config_errors = []
            self.known = nil
          end

          # Junk in the default result on purpose: the plugin has to
          # carry these through untouched and never act on them.
          def default_result
            { successes: 3, success_title: "Fake", advantage: 2, threat: 1, symbols: [ :triumph ] }
          end

          def script(*results)
            self.scripted = results.flatten
          end

          # Emptiness decides, not truthiness - a spec scripting an
          # explicit nil is testing that the plugin survives a system
          # returning junk, so nil must not fall back to the default.
          def next_result
            self.scripted ||= []
            return default_result if self.scripted.empty?
            self.scripted.shift
          end

          def available?
            self.is_available
          end

          # nil means "every ability is fine", which is what a system
          # with no skill list would answer.
          def known_ability?(ability)
            return true if self.known.nil?
            Array(self.known).map { |a| "#{a}" }.include?("#{ability}")
          end

          def roll_ability(char, ability, modifier = 0)
            (self.calls ||= []) << { kind: :ability, char: char, ability: ability, modifier: modifier }
            raise "fake dice exploded" if self.raise_on_roll
            next_result
          end

          def roll_pool(rating, modifier = 0)
            (self.calls ||= []) << { kind: :pool, rating: rating, modifier: modifier }
            raise "fake dice exploded" if self.raise_on_roll
            next_result
          end

          def check_config(station_skills)
            self.config_errors
          end
        end

        reset!
      end
    end
  end
end
