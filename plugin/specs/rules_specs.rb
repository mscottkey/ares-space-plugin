require_relative "../helpers/rules"

module AresMUSH
  module Space
    describe Rules do

      let(:scale_rules) do
        {
          "fighter_weapon_full_damage_max_silhouette" => 5,
          "fighter_weapon_vs_larger" => "systems_only",
          "fighter_weapon_reduced_multiplier" => 0.5,
          "capital_weapon_min_silhouette" => 5,
          "capital_weapon_small_target_penalty" => -3
        }
      end

      describe :silhouette_mod do
        it "is zero between equals" do
          expect(Rules.silhouette_mod(3, 3)).to eq 0
        end

        it "helps a fighter shooting a capital" do
          expect(Rules.silhouette_mod(3, 8, 3)).to eq 3
        end

        it "hurts a capital shooting a fighter" do
          expect(Rules.silhouette_mod(8, 3, 3)).to eq(-3)
        end

        it "clamps to the configured limit in both directions" do
          expect(Rules.silhouette_mod(1, 20, 2)).to eq 2
          expect(Rules.silhouette_mod(20, 1, 2)).to eq(-2)
        end

        it "leaves small differences unclamped" do
          expect(Rules.silhouette_mod(3, 4, 3)).to eq 1
        end
      end

      describe :scale_tohit_mod do
        it "penalizes capital weapons against small targets" do
          expect(Rules.scale_tohit_mod("capital", 3, scale_rules)).to eq(-3)
        end

        it "does not penalize capital weapons against capital targets" do
          expect(Rules.scale_tohit_mod("capital", 8, scale_rules)).to eq 0
        end

        it "never penalizes fighter weapons" do
          expect(Rules.scale_tohit_mod("fighter", 3, scale_rules)).to eq 0
          expect(Rules.scale_tohit_mod("fighter", 8, scale_rules)).to eq 0
        end
      end

      describe :damage_for_scale do
        it "lets fighter guns hurt small craft normally" do
          result = Rules.damage_for_scale(3, "fighter", 4, scale_rules)
          expect(result[:damage]).to eq 3
          expect(result[:systems_only]).to be false
        end

        it "limits fighter guns against capitals to systems damage" do
          result = Rules.damage_for_scale(3, "fighter", 8, scale_rules)
          expect(result[:damage]).to eq 3
          expect(result[:systems_only]).to be true
        end

        it "can instead scale fighter damage down when configured" do
          rules = scale_rules.merge("fighter_weapon_vs_larger" => "reduced")
          result = Rules.damage_for_scale(5, "fighter", 8, rules)
          expect(result[:damage]).to eq 2
          expect(result[:systems_only]).to be false
        end

        it "leaves capital weapons at full damage against anything" do
          result = Rules.damage_for_scale(8, "capital", 3, scale_rules)
          expect(result[:damage]).to eq 8
          expect(result[:systems_only]).to be false
        end
      end

      describe :range_mod do
        it "gives a bonus at point blank" do
          expect(Rules.range_mod(1, 4, { "point_blank" => 1, "normal" => 0 })).to eq 1
        end

        it "gives nothing at normal range" do
          expect(Rules.range_mod(3, 4, { "point_blank" => 1, "normal" => 0 })).to eq 0
        end

        it "returns nil beyond the weapon's reach" do
          expect(Rules.range_mod(5, 4, {})).to be_nil
        end

        it "treats exactly half range as point blank" do
          expect(Rules.range_mod(2, 4, { "point_blank" => 1 })).to eq 1
        end
      end

      describe :attack_modifier do
        it "sums silhouette, scale, range and situational modifiers" do
          mod = Rules.attack_modifier(
            attacker_sil: 8, target_sil: 3, weapon_scale: "capital",
            silhouette_clamp: 3, scale_rules: scale_rules,
            range_mod: 1, terrain_mod: -1, extra_mod: 2
          )
          # -3 silhouette, -3 capital-vs-small, +1 range, -1 terrain, +2 extra
          expect(mod).to eq(-4)
        end

        it "favours a fighter closing on a capital" do
          mod = Rules.attack_modifier(
            attacker_sil: 3, target_sil: 8, weapon_scale: "fighter",
            silhouette_clamp: 3, scale_rules: scale_rules, range_mod: 1
          )
          expect(mod).to eq 4
        end
      end

      describe :hit? do
        it "hits when successes beat the banked evade margin" do
          expect(Rules.hit?(3, 1, 1)).to be true
        end

        it "misses when the pilot's evasion holds" do
          expect(Rules.hit?(2, 2, 1)).to be false
          expect(Rules.hit?(1, 3, 1)).to be false
        end

        it "respects a raised hit threshold" do
          expect(Rules.hit?(3, 1, 3)).to be false
          expect(Rules.hit?(4, 1, 3)).to be true
        end
      end

      describe :damage_bonus do
        it "adds nothing for a marginal hit" do
          expect(Rules.damage_bonus(1)).to eq 0
        end

        it "scales with how badly the defender was beaten" do
          expect(Rules.damage_bonus(3)).to eq 2
        end
      end

      describe :apply_damage do
        let(:fighter) do
          { "hull" => { "shields" => 6, "max_shields" => 6, "hull" => 4, "max_hull" => 4, "systems" => [] } }
        end

        let(:capital) do
          {
            "fore"  => { "shields" => 10, "max_shields" => 10, "hull" => 12, "max_hull" => 12, "systems" => [ "sensors", "weapons" ] },
            "aft"   => { "shields" => 8,  "max_shields" => 8,  "hull" => 12, "max_hull" => 12, "systems" => [ "engines" ] }
          }
        end

        it "burns shields before hull" do
          result = Rules.apply_damage(fighter, "hull", 4)
          expect(result[:sections]["hull"]["shields"]).to eq 2
          expect(result[:sections]["hull"]["hull"]).to eq 4
        end

        it "carries overflow through to the hull" do
          result = Rules.apply_damage(fighter, "hull", 8)
          expect(result[:sections]["hull"]["shields"]).to eq 0
          expect(result[:sections]["hull"]["hull"]).to eq 2
        end

        it "does not mutate the ship it was given" do
          Rules.apply_damage(fighter, "hull", 8)
          expect(fighter["hull"]["shields"]).to eq 6
          expect(fighter["hull"]["hull"]).to eq 4
        end

        it "reports the section destroyed and its systems lost" do
          result = Rules.apply_damage(capital, "aft", 30)
          expect(result[:sections]["aft"]["hull"]).to eq 0
          destroyed = result[:events].find { |e| e.is_a?(Hash) && e[:type] == :section_destroyed }
          expect(destroyed).to_not be_nil
          expect(destroyed[:systems]).to eq [ "engines" ]
        end

        it "leaves other sections untouched" do
          result = Rules.apply_damage(capital, "aft", 30)
          expect(result[:sections]["fore"]["hull"]).to eq 12
          expect(result[:sections]["fore"]["shields"]).to eq 10
        end

        it "stops systems-only damage one point short of gutting a section" do
          result = Rules.apply_damage(capital, "fore", 100, true)
          expect(result[:sections]["fore"]["shields"]).to eq 0
          expect(result[:sections]["fore"]["hull"]).to eq 1
          expect(result[:events].any? { |e| e.is_a?(Hash) && e[:type] == :scale_capped }).to be true
        end

        it "never drives a wrecked section below zero hull" do
          once = Rules.apply_damage(capital, "aft", 30)
          twice = Rules.apply_damage(once[:sections], "aft", 30)
          expect(twice[:sections]["aft"]["hull"]).to eq 0
        end

        it "reports a section destroyed only on the blow that wrecks it" do
          once = Rules.apply_damage(capital, "aft", 30)
          twice = Rules.apply_damage(once[:sections], "aft", 30)
          destroyed = twice[:events].select { |e| e.is_a?(Hash) && e[:type] == :section_destroyed }
          expect(destroyed).to be_empty
        end

        it "keeps a ship alive when only one section is wrecked, however hard it is hit" do
          once = Rules.apply_damage(capital, "aft", 30)
          twice = Rules.apply_damage(once[:sections], "aft", 100)
          expect(Rules.destroyed?(twice[:sections], 1.0)).to be false
        end

        it "ignores damage to a section that does not exist" do
          result = Rules.apply_damage(fighter, "nose", 5)
          expect(result[:sections]["hull"]["hull"]).to eq 4
        end
      end

      describe :destroyed? do
        it "is false while hull remains" do
          sections = { "hull" => { "hull" => 1, "max_hull" => 4 } }
          expect(Rules.destroyed?(sections)).to be false
        end

        it "is true when every point of hull is gone" do
          sections = { "hull" => { "hull" => 0, "max_hull" => 4 } }
          expect(Rules.destroyed?(sections)).to be true
        end

        it "can kill a capital before every section is gone" do
          sections = {
            "fore" => { "hull" => 0, "max_hull" => 12 },
            "aft"  => { "hull" => 3, "max_hull" => 12 }
          }
          expect(Rules.destroyed?(sections, 1.0)).to be false
          expect(Rules.destroyed?(sections, 0.7)).to be true
        end
      end

      describe :systems_offline do
        it "lists systems in gutted sections only" do
          sections = {
            "fore" => { "hull" => 0, "systems" => [ "sensors" ] },
            "aft"  => { "hull" => 5, "systems" => [ "engines" ] }
          }
          expect(Rules.systems_offline(sections)).to eq [ "sensors" ]
          expect(Rules.system_online?(sections, "engines")).to be true
          expect(Rules.system_online?(sections, "sensors")).to be false
        end
      end

      describe :regen_shields do
        it "recharges toward the maximum but never past it" do
          sections = { "hull" => { "shields" => 4, "max_shields" => 6, "hull" => 4 } }
          once = Rules.regen_shields(sections, 1)
          expect(once["hull"]["shields"]).to eq 5
          topped = Rules.regen_shields(once, 5)
          expect(topped["hull"]["shields"]).to eq 6
        end

        it "skips sections that were just hit" do
          sections = { "hull" => { "shields" => 2, "max_shields" => 6, "hull" => 4 } }
          expect(Rules.regen_shields(sections, 1, [ "hull" ])["hull"]["shields"]).to eq 2
        end

        it "does not recharge a gutted section" do
          sections = { "fore" => { "shields" => 0, "max_shields" => 8, "hull" => 0 } }
          expect(Rules.regen_shields(sections, 2)["fore"]["shields"]).to eq 0
        end
      end
    end
  end
end
