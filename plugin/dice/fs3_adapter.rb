module AresMUSH
  module Space
    module Dice

      # Core FS3, and the default - a game that configures nothing gets
      # exactly the behaviour this plugin has always had.
      #
      # Only fs3skills' public API is used. We never roll our own dice and
      # never touch fs3combat's turn loop.
      module Fs3Adapter

        # Two conditions, not one. The obvious `defined?(FS3Skills)` is
        # necessary but not sufficient: PluginManager#load_plugin loads a
        # plugin's code files BEFORE it checks is_disabled?, so the
        # constant resolves perfectly well for a plugin the game has
        # switched off. Without the second check a game that disabled
        # fs3skills would keep rolling through it rather than falling
        # back.
        def self.available?
          return false if !defined?(FS3Skills)
          return false if !FS3Skills.respond_to?(:one_shot_roll)
          return FS3Skills.is_enabled? if FS3Skills.respond_to?(:is_enabled?)
          true
        end

        # FS3 answers :background for an ability it doesn't know rather
        # than failing, which would quietly turn a misconfigured station
        # into a one-die roll. Only the types that mean "the game really
        # defines this" count as known.
        def self.known_ability?(ability)
          return false if ability.nil?
          return false if !available?
          type = FS3Skills.get_ability_type("#{ability}")
          [ :action, :attribute, :language, :advantage ].include?(type)
        rescue => e
          Global.logger.debug "Space: could not classify ability #{ability}: #{e}"
          false
        end

        def self.unavailable_hint
          "This system rolls through core FS3 (fs3skills), which must be installed and enabled."
        end

        # Every station skill has to be an ability FS3 really defines,
        # or that station silently rolls untrained all game.
        def self.check_config(station_skills)
          (station_skills || {}).reject { |_station, ability| known_ability?(ability) }
                                .map do |station, ability|
            "space: station '#{station}' maps to ability '#{ability}', which FS3 does not define. It will roll untrained dice."
          end
        end

        def self.roll_ability(char, ability, modifier = 0)
          result = FS3Skills.one_shot_roll(char, FS3Skills::RollParams.new(ability, modifier.to_i))
          result.merge(dice: nil)
        end

        # The floor of one die is FS3's rule, not the plugin's, which is
        # why the rating and the modifier arrive here separately instead
        # of as a finished count - another system is free to combine them
        # differently, or to ignore the modifier entirely.
        def self.roll_pool(rating, modifier = 0)
          dice = [ rating.to_i + modifier.to_i, 1 ].max
          result = FS3Skills.one_shot_die_roll(dice)
          result.merge(dice: dice)
        end
      end
    end
  end
end
