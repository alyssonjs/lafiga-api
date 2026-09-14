# frozen_string_literal: true

require 'rails_helper'

# Escudo do catálogo no payload público (14/09/2026). A desvantagem em
# Furtividade que o mestre marca tem de chegar ao compêndio e à bolsa — antes o
# serializer mandava `false` fixo para todo escudo.
RSpec.describe 'Api::V1::Public::Equipment — escudo', type: :request do
  def escudo!(idx, props)
    Item.find_or_initialize_by(api_index: idx).tap do |it|
      it.assign_attributes(name: idx.tr('-', ' ').capitalize, kind: :shield, category: 'shield', props: props)
      it.save!
    end
  end

  it 'o escudo marcado sai com stealth_disadvantage' do
    escudo!('spec-escudo-grande', 'ac_base' => 3, 'stealth_dis' => true)

    get '/api/v1/public/equipment/spec-escudo-grande'

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['stealth_disadvantage']).to be(true)
  end

  it 'o escudo sem a marca sai sem' do
    escudo!('spec-escudo-comum', 'ac_base' => 2)

    get '/api/v1/public/equipment/spec-escudo-comum'

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)['stealth_disadvantage']).to be(false)
  end
end
