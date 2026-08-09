# frozen_string_literal: true

require 'rails_helper'

# Cobre os endpoints de arrastar-e-soltar da bolsa: reorder (coleção),
# merge e split (membro) — contrato { sheet_items: [...] }, autorização por dono
# e isolamento entre fichas.
RSpec.describe 'Api::V1::Player::SheetItems reorder/merge/split', type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:other_headers) { bearer_headers_for(other_user) }
  let(:race) { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  let(:character) { create(:character, user: user, name: 'DnD Bag PC') }
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race) }

  def item(name:, index:, qty:, **extra)
    SheetItem.create!(sheet: sheet, item_name: name, item_index: index, category: 'Armas', quantity: qty, source: 'test', **extra)
  end

  describe 'POST /api/v1/player/sheet_items/reorder' do
    it 'grava a ordem enviada e devolve o inventário ordenado' do
      a = item(name: 'Aljava', index: 'aljava', qty: 1)
      b = item(name: 'Corda', index: 'corda', qty: 1)
      c = item(name: 'Tocha', index: 'tocha', qty: 1)

      post '/api/v1/player/sheet_items/reorder',
           params: { sheet_id: sheet.id, ordered_ids: [c.id, a.id, b.id] },
           headers: headers, as: :json

      expect(response).to have_http_status(:ok), -> { response.body }
      names = response.parsed_body['sheet_items'].map { |i| i['name'] }
      expect(names).to eq(%w[Tocha Aljava Corda])
    end

    it 'nega reorder de ficha de outro usuário (403)' do
      a = item(name: 'Aljava', index: 'aljava', qty: 1)

      post '/api/v1/player/sheet_items/reorder',
           params: { sheet_id: sheet.id, ordered_ids: [a.id] },
           headers: other_headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'POST /api/v1/player/sheet_items/:id/merge' do
    it 'unifica duas pilhas do mesmo item' do
      target = item(name: 'Virote de Gelo', index: 'virote-gelo', qty: 14)
      source = item(name: 'Virote de Gelo', index: 'virote-gelo', qty: 6, source: 'map_pickup')

      post "/api/v1/player/sheet_items/#{source.id}/merge",
           params: { target_id: target.id },
           headers: headers, as: :json

      expect(response).to have_http_status(:ok), -> { response.body }
      ids = response.parsed_body['sheet_items'].map { |i| i['id'] }
      expect(ids).to include(target.id)
      expect(ids).not_to include(source.id)
      expect(target.reload.quantity).to eq(20)
    end

    it 'rejeita unir catálogos diferentes (422)' do
      target = item(name: 'Virote de Gelo', index: 'virote-gelo', qty: 14)
      other = item(name: 'Flecha', index: 'flecha', qty: 6)

      post "/api/v1/player/sheet_items/#{other.id}/merge",
           params: { target_id: target.id }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to be_present
    end

    it 'nega merge quando o usuário não é dono da origem (403)' do
      target = item(name: 'Virote de Gelo', index: 'virote-gelo', qty: 14)
      source = item(name: 'Virote de Gelo', index: 'virote-gelo', qty: 6)

      post "/api/v1/player/sheet_items/#{source.id}/merge",
           params: { target_id: target.id }, headers: other_headers, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(target.reload.quantity).to eq(14)
    end
  end

  describe 'POST /api/v1/player/sheet_items/:id/split' do
    it 'separa N unidades numa nova pilha' do
      stack = item(name: 'Virote de Gelo', index: 'virote-gelo', qty: 20)

      post "/api/v1/player/sheet_items/#{stack.id}/split",
           params: { quantity: 5 }, headers: headers, as: :json

      expect(response).to have_http_status(:ok), -> { response.body }
      items = response.parsed_body['sheet_items']
      expect(items.size).to eq(2)
      expect(items.map { |i| i['quantity'] }.sort).to eq([5, 15])
      expect(stack.reload.quantity).to eq(15)
    end

    it 'rejeita separar a pilha inteira (422)' do
      stack = item(name: 'Virote de Gelo', index: 'virote-gelo', qty: 20)

      post "/api/v1/player/sheet_items/#{stack.id}/split",
           params: { quantity: 20 }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(stack.reload.quantity).to eq(20)
    end
  end
end
