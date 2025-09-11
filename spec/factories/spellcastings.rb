FactoryBot.define do
  factory :spellcasting do
    class_level { nil }
    level { 1 }
    cantrips_known { 1 }
    spells_known { 1 }
    spell_slots { "MyText" }
  end
end
