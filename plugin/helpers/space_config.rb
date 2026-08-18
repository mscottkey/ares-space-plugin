module AresMUSH
  module Space

    # Every tuning number lives in YAML; this is the only place that reads
    # it. Helpers take the values as arguments so the rules stay pure.
    module SpaceConfig

      def self.setting(*path)
        Global.read_config("space", *path)
      end

      def self.default_geometry
        setting("default_geometry") || "square"
      end

      def self.arc_diagonal_bias
        setting("arc_diagonal_bias") || "forward"
      end

      def self.evade_model
        setting("evade_model") || "banked"
      end

      def self.auto_resolve?
        !!setting("auto_resolve")
      end

      def self.hit_threshold
        (setting("hit_threshold") || 1).to_i
      end

      def self.untrained_dice
        (setting("untrained_dice") || 2).to_i
      end

      # Which dice system crew rolls go out to. Defaults to FS3, so a
      # game that never sets this behaves exactly as it always has.
      def self.dice_system
        setting("dice_system") || Dice::DEFAULT
      end

      def self.silhouette_clamp
        (setting("silhouette_tohit_clamp") || 3).to_i
      end

      def self.scale_rules
        setting("scale_rules") || {}
      end

      def self.range_mods
        setting("range_mods") || {}
      end

      def self.station_skills
        setting("station_skills") || {}
      end

      def self.skill_for_station(station)
        station_skills["#{station}"]
      end

      def self.passive_sensor_range
        (setting("sensors", "passive_range") || 6).to_i
      end

      def self.active_sensor_range
        (setting("sensors", "active_range") || 12).to_i
      end

      def self.destruction_fraction
        (setting("damage", "destruction_hull_fraction") || 1.0).to_f
      end

      def self.shield_regen
        (setting("damage", "shield_regen") || 0).to_i
      end

      # ---------------------------------------------------------------
      # Strain
      # ---------------------------------------------------------------

      def self.strain_regen
        (setting("strain", "regen") || 0).to_i
      end

      # FS3 botches at -1; "the manoeuvre went badly and you stressed the
      # frame" is what gives strain a role for a game that never wires up
      # the roll side-effects channel (see Resolver.apply_roll_strain).
      def self.strain_on_botch
        (setting("strain", "on_botch") || 1).to_i
      end

      # ---------------------------------------------------------------
      # Ship classes and weapons
      # ---------------------------------------------------------------

      def self.ship_classes
        Global.read_config("space", "ship_classes") || {}
      end

      # Class lookup is case-insensitive so players can type "talon".
      def self.ship_class(name)
        return nil if name.nil?
        classes = ship_classes
        classes[name] || classes.find { |k, _v| k.downcase == "#{name}".downcase }&.last
      end

      def self.ship_class_name(name)
        return nil if name.nil?
        ship_classes.keys.find { |k| k.downcase == "#{name}".downcase }
      end

      def self.weapons
        Global.read_config("space", "weapons") || {}
      end

      def self.weapon(name)
        return nil if name.nil?
        all = weapons
        all[name] || all.find { |k, _v| k.downcase == "#{name}".downcase }&.last
      end

      def self.weapon_stat(name, stat)
        w = weapon(name)
        w ? w[stat] : nil
      end
    end
  end
end
