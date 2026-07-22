# frozen_string_literal: true

FactoryBot.define do
  factory :bug_report do
    association :user
    sequence(:title) { |n| "Bug ##{n}" }
    description { 'Algo quebrou na tela X ao clicar em Y.' }
    steps_to_reproduce { '1. Abrir X. 2. Clicar Y. 3. Erro.' }
    severity { :medium }
    status { :aberto }
    context { {} }
    metadata { {} }

    trait :with_attachment do
      after(:build) do |report|
        report.attachments.attach(
          io: StringIO.new("\x89PNG\r\n\x1a\nfake"),
          filename: 'shot.png',
          content_type: 'image/png',
        )
      end
    end
  end
end
