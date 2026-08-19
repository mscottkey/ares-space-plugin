module AresMUSH
  module Space

    # The combat math, as pure functions over plain values.
    #
    # Nothing here touches Ohm, Redis, the dice or config directly -
    # callers pass in the numbers and the rules hash. That keeps the
    # tuning surface in YAML, the dice behind Space::Dice, and this file
    # unit-testable.
    #
    # The successes these functions compare are a plain integer scalar,
    # which is the whole contract with whatever dice system rolled them.
    module Rules

      # -----------------------------------------------------------------
      # Silhouette
      # -----------------------------------------------------------------

      # Shooting something bigger than you is easier; smaller, harder.
      def self.silhouette_mod(attacker_sil, target_sil, clamp = 3)
        c = clamp.to_i.abs
        diff = target_sil.to_i - attacker_sil.to_i
        [ [ diff, c ].min, -c ].max
      end

      # Capital guns track badly against small, nimble targets.
      def self.scale_tohit_mod(weapon_scale, target_sil, scale_rules = {})
        return 0 unless "#{weapon_scale}".downcase == "capital"
        min_sil = (scale_rules["capital_weapon_min_silhouette"] || 5).to_i
        return 0 if target_sil.to_i >= min_sil
        (scale_rules["capital_weapon_small_target_penalty"] || -3).to_i
      end

      # What a hit from this weapon actually does to a hull of this size.
      #
      # Returns { damage:, systems_only: }. `systems_only` means the hit
      # can wreck sections and the systems in them but will never breach
      # the core hull - a Talon's cannons scarring the Covenant.
      def self.damage_for_scale(base_damage, weapon_scale, target_sil, scale_rules = {})
        dmg = base_damage.to_i
        return { damage: dmg, systems_only: false } unless "#{weapon_scale}".downcase == "fighter"

        max_full = (scale_rules["fighter_weapon_full_damage_max_silhouette"] || 5).to_i
        return { damage: dmg, systems_only: false } if target_sil.to_i <= max_full

        case "#{scale_rules['fighter_weapon_vs_larger'] || 'systems_only'}".downcase
        when "reduced"
          mult = (scale_rules["fighter_weapon_reduced_multiplier"] || 0.5).to_f
          { damage: [ (dmg * mult).floor, 1 ].max, systems_only: false }
        else
          { damage: dmg, systems_only: true }
        end
      end

      # -----------------------------------------------------------------
      # Range
      # -----------------------------------------------------------------

      # nil means out of range - the weapon simply cannot fire.
      def self.range_mod(distance, weapon_range, range_mods = {})
        d = distance.to_i
        r = weapon_range.to_i
        return nil if d > r
        return (range_mods["point_blank"] || 1).to_i if d * 2 <= r
        (range_mods["normal"] || 0).to_i
      end

      # -----------------------------------------------------------------
      # Attack resolution
      # -----------------------------------------------------------------

      # Total modifier for a gunnery roll, before the dice system sees
      # it. Signed integer; each system decides what it means (FS3 reads
      # it as bonus/penalty dice).
      def self.attack_modifier(opts)
        silhouette_mod(opts[:attacker_sil], opts[:target_sil], opts[:silhouette_clamp] || 3) +
          scale_tohit_mod(opts[:weapon_scale], opts[:target_sil], opts[:scale_rules] || {}) +
          (opts[:range_mod] || 0) +
          (opts[:terrain_mod] || 0) +
          (opts[:extra_mod] || 0)
      end

      # Did it land? Attack successes are checked against the margin the
      # target's pilot banked this round.
      def self.hit?(attack_successes, evade_margin, hit_threshold = 1)
        net_successes(attack_successes, evade_margin) >= hit_threshold.to_i
      end

      def self.net_successes(attack_successes, evade_margin)
        attack_successes.to_i - evade_margin.to_i
      end

      # Beating the defender badly drives damage up.
      def self.damage_bonus(net)
        n = net.to_i
        return 0 if n <= 1
        n - 1
      end

      # -----------------------------------------------------------------
      # Damage application
      # -----------------------------------------------------------------

      # Applies damage to one section of a ship profile.
      #
      # `sections` is a hash of section name => { "shields" =>, "hull" =>,
      # "max_shields" =>, "max_hull" =>, "systems" => [...] }. Small craft
      # have a single section named "hull" - that is the one shield bubble.
      #
      # Returns { sections:, events: [...] } and never mutates the input.
      def self.apply_damage(sections, section_name, damage, systems_only = false)
        out = deep_copy_sections(sections)
        events = []
        section = out[section_name]
        return { sections: out, events: [ "no such section: #{section_name}" ] } if !section

        remaining = damage.to_i
        return { sections: out, events: events } if remaining <= 0

        shields = section["shields"].to_i
        if shields > 0
          absorbed = [ shields, remaining ].min
          section["shields"] = shields - absorbed
          remaining -= absorbed
          events << { type: :shields, section: section_name, amount: absorbed,
                      remaining: section["shields"] }
          events << { type: :shields_down, section: section_name } if section["shields"] == 0
        end

        return { sections: out, events: events } if remaining <= 0

        hull_before = section["hull"].to_i

        if systems_only
          # Can chew a section down to its last point but never past it,
          # so fighter guns cripple a capital rather than killing it.
          floor = 1
          applied = [ remaining, [ hull_before - floor, 0 ].max ].min
          section["hull"] = hull_before - applied
          events << { type: :hull, section: section_name, amount: applied,
                      remaining: section["hull"], systems_only: true } if applied > 0
          events << { type: :scale_capped, section: section_name } if applied < remaining
        else
          # Clamp at zero: a wrecked section stays wrecked rather than
          # accumulating negative hull that would skew the ship's totals
          # and make it read as destroyed before it is.
          applied = [ remaining, [ hull_before, 0 ].max ].min
          section["hull"] = [ hull_before - remaining, 0 ].max
          events << { type: :hull, section: section_name, amount: applied,
                      remaining: section["hull"] } if applied > 0
        end

        if section["hull"].to_i <= 0 && hull_before > 0
          events << { type: :section_destroyed, section: section_name,
                      systems: section["systems"] || [] }
        end

        { sections: out, events: events }
      end

      # A ship dies when its whole hull is gone, not when one section is -
      # crippled hulks stay in the fiction as wrecks and objectives.
      def self.destroyed?(sections, destruction_fraction = 1.0)
        totals = hull_totals(sections)
        return false if totals[:max] <= 0
        lost = totals[:max] - totals[:current]
        lost >= (totals[:max] * destruction_fraction.to_f)
      end

      def self.hull_totals(sections)
        current = 0
        max = 0
        sections.each do |_name, s|
          current += s["hull"].to_i
          max += (s["max_hull"] || s["hull"]).to_i
        end
        { current: current, max: max }
      end

      def self.systems_offline(sections)
        offline = []
        sections.each do |_name, s|
          next if s["hull"].to_i > 0
          offline.concat(s["systems"] || [])
        end
        offline.uniq
      end

      def self.system_online?(sections, system_name)
        !systems_offline(sections).include?("#{system_name}")
      end

      def self.regen_shields(sections, amount, skip = [])
        out = deep_copy_sections(sections)
        out.each do |name, s|
          next if skip.include?(name)
          next if s["hull"].to_i <= 0
          max = (s["max_shields"] || 0).to_i
          next if max <= 0
          s["shields"] = [ s["shields"].to_i + amount.to_i, max ].min
        end
        out
      end

      def self.deep_copy_sections(sections)
        copy = {}
        sections.each do |name, s|
          dup = {}
          s.each { |k, v| dup[k] = v.is_a?(Array) ? v.dup : v }
          copy[name] = dup
        end
        copy
      end

      # -----------------------------------------------------------------
      # System strain
      # -----------------------------------------------------------------

      # A second, whole-ship damage track - "stressed, not broken" rather
      # than the per-section shields/hull above. Ship-level because it's
      # the crew and the frame under load, not any one arc.
      #
      # Returns { strain:, events: [] }, never negative. Emits
      # :strained_out only on the transition that crosses the threshold,
      # the same way apply_damage emits :section_destroyed once rather
      # than on every blow after a section is already wrecked.
      def self.apply_strain(current, amount, threshold)
        before = current.to_i
        after = [ before + amount.to_i, 0 ].max
        events = []
        events << :strained_out if after >= threshold.to_i && before < threshold.to_i
        { strain: after, events: events }
      end

      # Passive regen and a venting engineering order both just remove
      # strain; neither cares about the threshold, so this stays a plain
      # clamp rather than sharing apply_strain's event bookkeeping.
      def self.recover_strain(current, amount)
        [ current.to_i - amount.to_i, 0 ].max
      end

      def self.strained_out?(strain, threshold)
        strain.to_i >= threshold.to_i
      end
    end
  end
end
