FactoryBot.define do
  factory :spell do
    sequence(:api_index) { |n| "spec_spell_#{n}_#{SecureRandom.hex(4)}" }
    sequence(:name) { |n| "Spec Spell #{n}" }
    level { 1 }
    school { "MyString" }
    range { "MyString" }
    components { "MyText" }
    material { "MyText" }
    ritual { false }
    duration { "MyString" }
    concentration { false }
    casting_time { "MyString" }
    desc { "MyText" }
    higher_level { "MyText" }
  end
end
