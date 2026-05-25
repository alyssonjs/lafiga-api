# frozen_string_literal: true

FactoryBot.define do
  factory :map_asset do
    sequence(:name) { |n| "Asset #{n}" }
    kind { 'texture' }
    category { 'custom' }
    color { '#4a7c45' }
    enabled { true }
    association :user

    # Anexa um PNG fake p/ satisfazer `image_present_and_valid`.
    after(:build) do |asset|
      asset.image.attach(
        io: StringIO.new("\x89PNG\r\n\x1a\nfake-bytes"),
        filename: 'asset.png',
        content_type: 'image/png',
      )
    end

    trait :texture do
      kind { 'texture' }
      category { 'vegetacao' }
    end

    trait :stamp do
      kind { 'stamp' }
      category { 'natureza' }
    end

    trait :path do
      kind { 'path' }
      category { 'via' }
    end
  end
end
