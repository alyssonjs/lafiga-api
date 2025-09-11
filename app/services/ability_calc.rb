class AbilityCalc
  def self.mod(score)
    CharacterRules.modifier(score)
  end

  def self.prof_bonus(total_level)
    CharacterRules.proficiency_bonus(total_level)
  end

  def self.passive_perception(wis_mod, proficient: false, prof_bonus: 0)
    10 + wis_mod.to_i + (proficient ? prof_bonus.to_i : 0)
  end

  def self.saving_throw_total(score_mod, proficient: false, prof_bonus: 0)
    score_mod.to_i + (proficient ? prof_bonus.to_i : 0)
  end
end

