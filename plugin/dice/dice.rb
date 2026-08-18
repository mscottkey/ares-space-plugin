module AresMUSH
  module Space

    # Which dice a game rolls, and how to find them.
    #
    # Nothing about ships, arcs, sections, silhouette or the round
    # structure is FS3-specific - only the dice are. This is the seam that
    # lets a game on another system use the rest of the plugin. FS3 is the
    # default and needs no configuration.
    #
    # An adapter is a stateless module with four methods:
    #
    #   available?                            is the system loaded and enabled?
    #   known_ability?(ability)               would this ability really resolve?
    #   roll_ability(char, ability, modifier) => { successes:, ... }
    #   roll_pool(rating, modifier)           => { successes:, ... }
    #
    # Both roll methods must return a hash carrying an Integer
    # `:successes`. That scalar is what the combat math is built on - see
    # Rules.hit?/net_successes/damage_bonus, and note the resolver also
    # spends it as a magnitude (a repair success is a hull point, a sweep
    # success is a grid cell of extra range). Extra system-specific keys
    # are welcome and simply ignored by the resolver, with two
    # exceptions: two OPTIONAL keys the resolver reads and every other
    # system-agnostic caller ignores.
    #
    #   :strain  Integer - strain inflicted on the ACTING ship (the one
    #            that rolled), added to whatever Resolver.apply_roll_strain
    #            already applies for a botched roll (successes < 0,
    #            config strain.on_botch). This is the FFG hook: an
    #            adapter spends net threat here.
    #   :detail  String  - a short narrative note, rendered alongside the
    #            roll's line in the round report (Display.render_report).
    #            This is where advantage/triumph/despair get described,
    #            since the resolver only ever consumes the :successes
    #            integer for the math itself.
    #
    # Both are additive to the base contract - :successes remains the
    # only required key, and Rules stays untouched by either. The FS3
    # adapter returns neither, so a game that never sets dice_system sees
    # no change in behaviour.
    #
    # Reserved keys an adapter should not return, because something
    # downstream already owns them: :roller and :ability (Crew stamps
    # these after the roll), and :range, :station and :modifier (merged
    # over the roll hash by Sensors.sweep).
    #
    # `known_ability?` exists because of a real FS3 footgun worth
    # repeating for anyone writing an adapter: FS3's get_ability_type
    # answers :background for a name it has never heard of rather than
    # failing, so a typo'd skill silently becomes a one-die everyman roll
    # instead of an error. Any system needs some equivalent "is this
    # real?" answer, or a misconfigured station degrades invisibly.
    #
    # `roll_pool` takes the raw NPC rating (or the configured untrained
    # value) and the modifier SEPARATELY rather than a finished die count.
    # Combining them - and deciding there is a floor of one die - is an
    # FS3 rule, so it belongs in the FS3 adapter rather than being applied
    # to every system on the way in.
    module Dice

      CONTRACT = [ :available?, :known_ability?, :roll_ability, :roll_pool ]

      DEFAULT = "fs3"

      # Resolved per call rather than registered at load: core loads a
      # plugin's files in no guaranteed order (PluginManager#code_files
      # globs directories, and `dice` sorts before `helpers`), so anything
      # self-registering into a table at load time races with whatever
      # populates that table.
      #
      # A bare name is one of ours ("fs3" -> Space::Dice::Fs3Adapter). A
      # name carrying "::" is taken as a fully-qualified constant, so a
      # third-party system can ship its adapter inside its OWN plugin
      # rather than having to reopen this namespace.
      def self.adapter_for(name)
        key = "#{name}".strip
        return nil if key.empty?

        if key.include?("::")
          # Deliberately not const_get on arbitrary input alone: a bare
          # "Kernel" or "Object" would resolve to a real constant that is
          # obviously not a dice system. Anything reachable here still has
          # to satisfy the contract before usable_adapter will call it.
          return nil if key !~ /\A(?:[A-Z][A-Za-z0-9_]*)(?:::[A-Z][A-Za-z0-9_]*)+\z/
          return Object.const_get(key)
        end

        # Bare names are underscore-separated and case-insensitive, so
        # `fs3`, `FS3` and `Fs3` all reach the same module: this is a
        # hand-edited YAML value, not an identifier.
        return nil if key !~ /\A[A-Za-z][A-Za-z0-9_]*\z/
        const = key.downcase.split("_").map { |p| p[0].upcase + p[1..-1].to_s }.join
        return nil if !const_defined?("#{const}Adapter", false)
        const_get("#{const}Adapter", false)
      rescue NameError
        nil
      end

      def self.adapter
        adapter_for(SpaceConfig.dice_system)
      end

      # Which of the four contract methods this module is missing, if
      # any. Surfaced by check_config so a half-written adapter - or a
      # config pointing at some constant that was never a dice system at
      # all - says so at startup instead of raising mid-round.
      def self.missing_contract_methods(adapter)
        return CONTRACT.dup if !adapter
        CONTRACT.reject { |m| adapter.respond_to?(m) }
      end

      # The adapter only if it is safe to actually call.
      def self.usable_adapter
        found = adapter
        return nil if !found
        return nil if !missing_contract_methods(found).empty?
        return nil if !found.available?
        found
      rescue => e
        Global.logger.error "Space: dice system '#{SpaceConfig.dice_system}' failed while reporting availability: #{e}"
        nil
      end

      # Both invocations funnel through here so a broken or missing dice
      # system degrades to "no successes" rather than raising.
      #
      # That matters more than it looks: the resolver spends ammo before
      # it rolls (resolver.rb), so an exception escaping a roll would
      # abandon the round half-applied - ammo gone, movement committed,
      # no report emitted. A zero is a bad roll; a raise is a corrupt
      # round.
      def self.invoke(what)
        adapter = usable_adapter
        if !adapter
          Global.logger.error "Space: dice system '#{SpaceConfig.dice_system}' is unavailable; rolling nothing."
          return unavailable
        end

        result = yield adapter
        return unavailable if !result.is_a?(Hash) || result[:successes].nil?
        result.merge(successes: result[:successes].to_i)
      rescue => e
        Global.logger.error "Space: dice system '#{SpaceConfig.dice_system}' raised on #{what}: #{e}"
        unavailable
      end

      def self.roll_ability(char, ability, modifier = 0)
        invoke("roll_ability") { |a| a.roll_ability(char, ability, modifier.to_i) }
      end

      def self.roll_pool(rating, modifier = 0)
        invoke("roll_pool") { |a| a.roll_pool(rating.to_i, modifier.to_i) }
      end

      def self.known_ability?(ability)
        adapter = usable_adapter
        return false if !adapter
        !!adapter.known_ability?(ability)
      rescue => e
        Global.logger.debug "Space: dice system could not classify ability #{ability}: #{e}"
        false
      end

      def self.available?
        !usable_adapter.nil?
      end

      def self.unavailable
        { successes: 0, success_title: t('space.no_dice_system') }
      end

      # Reported by manage/checkconfig. A misconfigured dice system is
      # worth catching here because the alternative is discovering it as
      # a battle full of zero-success rolls.
      def self.check_config
        name = SpaceConfig.dice_system
        found = adapter

        if !found
          return [ "space: dice_system '#{name}' is not installed. Installed: #{installed.join(', ')}. " \
                   "Adapters live in plugin/dice/; see docs/architecture.md for the contract." ]
        end

        missing = missing_contract_methods(found)
        if !missing.empty?
          return [ "space: dice_system '#{name}' resolves to #{found}, which is missing #{missing.join(', ')}. " \
                   "A dice system must implement all of: #{CONTRACT.join(', ')}." ]
        end

        return [ "space: dice_system '#{name}' is not available. #{unavailable_hint(found)}" ] if !found.available?

        return [] if !found.respond_to?(:check_config)
        Array(found.check_config(SpaceConfig.station_skills || {}))
      rescue => e
        [ "space: dice_system '#{name}' raised while checking its config: #{e}" ]
      end

      def self.unavailable_hint(adapter)
        adapter.respond_to?(:unavailable_hint) ? "#{adapter.unavailable_hint}" : "Is the plugin it needs installed and enabled?"
      end

      # Adapters shipped with this plugin, for a useful error message
      # when someone names one that isn't here.
      def self.installed
        constants(false).map { |c| "#{c}" }
                        .select { |c| c.end_with?("Adapter") }
                        .map { |c| c.sub(/Adapter\z/, "").downcase }
                        .sort
      end
    end
  end
end
