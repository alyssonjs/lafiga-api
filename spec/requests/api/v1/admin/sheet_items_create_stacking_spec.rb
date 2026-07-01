# frozen_string_literal: true

require 'rails_helper'

# Espelha o stacking do controller do player no lado admin (Mestre) e garante
# que o endpoint `grant` (auditoria do DM) continua escopado por source.
RSpec.describe 'Api::V1::Admin::SheetItemsController create — stacking', type: :request do
  let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:dm_user) { create(:user, role: dm_role) }
  let(:player_user) { create(:user, role: player_role) }
  let(:dm_headers) { bearer_headers_for(dm_user) }
  let(:race) { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  let(:character) { create(:character, user: player_user, name: 'PC Admin Stack') }
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race) }

  it 'soma a quantidade no create admin ao adicionar o mesmo item duas vezes' do
    post '/api/v1/admin/sheet_items',
         params: { sheet_item: { sheet_id: sheet.id, item_index: 'spec-pocao', item_name: 'Poção de Cura', category: 'Consumíveis', quantity: 1, source: 'manual' } },
         headers: dm_headers, as: :json
    expect(response).to have_http_status(:created), -> { response.body }

    post '/api/v1/admin/sheet_items',
         params: { sheet_item: { sheet_id: sheet.id, item_index: 'spec-pocao', item_name: 'Poção de Cura', category: 'Consumíveis', quantity: 9, source: 'manual' } },
         headers: dm_headers, as: :json
    expect(response).to have_http_status(:ok), -> { response.body }

    rows = SheetItem.where(sheet_id: sheet.id, item_index: 'spec-pocao')
    expect(rows.count).to eq(1)
    expect(rows.first.quantity).to eq(10)
  end

  it 'grant continua empilhando por item_index + source dm_grant (sem mesclar com manual)' do
    manual = SheetItem.create!(
      sheet: sheet, item_index: 'spec-pocao-grant', item_name: 'Poção de Cura', category: 'Consumíveis',
      quantity: 1, equipped: false, source: 'manual'
    )

    2.times do
      post '/api/v1/admin/sheet_items/grant',
           params: { grant: { sheet_id: sheet.id, item_index: 'spec-pocao-grant', item_name: 'Poção de Cura', category: 'Consumíveis', quantity: 1 } },
           headers: dm_headers, as: :json
      expect(response).to have_http_status(:created), -> { response.body }
    end

    expect(manual.reload.quantity).to eq(1) # pilha manual intacta
    granted = SheetItem.where(sheet_id: sheet.id, item_index: 'spec-pocao-grant', source: 'dm_grant')
    expect(granted.count).to eq(1)
    expect(granted.first.quantity).to eq(2)
  end
end
