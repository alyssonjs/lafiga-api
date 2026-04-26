# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Public::MagicItems', type: :request do
  describe 'GET /api/v1/public/magic_items' do
    let!(:mi) do
      MagicItem.create!(
        slug: "req-spec-mi-#{SecureRandom.hex(3)}",
        name: 'Item Request Spec',
        rarity: 'uncommon',
        category: 'weapon',
        requires_attunement: false,
        effects: [],
      )
    end

    it 'inclui is_magical e tags com magico em cada item' do
      get '/api/v1/public/magic_items'
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      row = json['magic_items'].find { |r| r['slug'] == mi.slug }
      expect(row).to be_present
      expect(row['is_magical']).to be true
      expect(row['tags']).to include('magico')
      expect(row['rarity']).to eq('uncommon')
    end
  end
end
