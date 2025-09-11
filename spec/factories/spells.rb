FactoryBot.define do
  factory :spell do
    api_index { "MyString" }
    name { "MyString" }
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
