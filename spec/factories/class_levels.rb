FactoryBot.define do
  factory :class_level do
    dnd_class { nil }
    level { 1 }
    prof_bonus { 1 }
    ability_score_bonuses { 1 }
  end
end
