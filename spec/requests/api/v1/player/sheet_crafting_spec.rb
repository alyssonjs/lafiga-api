# frozen_string_literal: true

require 'rails_helper'

# A oficina para LER — o jogador vê as receitas que conhece e as criações.
RSpec.describe 'Api::V1::Player::SheetCrafting', type: :request do
  let(:dono) { create(:user) }
  let(:sheet) { create(:sheet, character: create(:character, user: dono)) }
  let(:pocao) { oficina_item('alq-pocao-cura', 'Poção de Cura', kind: 'consumable', category: 'potion') }
  let(:receita) { oficina_receita(produto: pocao, ingredientes: []) }

  before { sheet.sheet_known_recipes.create!(crafting_recipe: receita) }

  def ler(user) = get("/api/v1/player/sheets/#{sheet.id}/crafting", headers: bearer_headers_for(user))

  it 'o dono lê', :aggregate_failures do
    ler(dono)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).dig('crafting', 'recipes', 0, 'product', 'name')).to eq('Poção de Cura')
  end

  it 'o Mestre lê a de qualquer um' do
    ler(create(:user, role: Role.find_or_create_by!(name: 'DM')))
    expect(response).to have_http_status(:ok)
  end

  it '⚠️ outro jogador não lê' do
    ler(create(:user))
    expect(response).to have_http_status(:not_found)
  end
end
