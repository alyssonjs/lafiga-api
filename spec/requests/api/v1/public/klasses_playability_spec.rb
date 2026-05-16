# frozen_string_literal: true

require 'rails_helper'

# Espelha `public/races_playability_spec.rb`. Os controllers públicos de
# klass/sub_klass serializam o registro cru (`Klass.all`), então a coluna
# `playable` (migration `add_playable_to_klasses_and_sub_klasses`) aparece
# automaticamente no JSON.
RSpec.describe 'Api::V1::Public::Klasses playability', type: :request do
  it 'exposes playable flag for klasses' do
    klass = create(:klass, name: 'Classe Escondida', playable: false)

    get '/api/v1/public/klasses'

    expect(response).to have_http_status(:ok)
    row = response.parsed_body['klasses'].find { |k| k['id'] == klass.id }
    expect(row).to be_present
    expect(row['playable']).to eq(false)
  end

  it 'exposes playable flag for sub-klasses' do
    klass = create(:klass)
    sub_klass = create(:sub_klass, klass: klass, name: 'Subclasse Secreta', playable: false)

    get '/api/v1/public/sub_klasses'

    expect(response).to have_http_status(:ok)
    row = response.parsed_body['sub_klasses'].find { |sk| sk['id'] == sub_klass.id }
    expect(row).to be_present
    expect(row['playable']).to eq(false)
  end

  it 'defaults playable to true when not set' do
    klass = create(:klass)

    get '/api/v1/public/klasses'

    row = response.parsed_body['klasses'].find { |k| k['id'] == klass.id }
    expect(row['playable']).to eq(true)
  end
end
