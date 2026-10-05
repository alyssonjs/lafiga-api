# frozen_string_literal: true

require 'rails_helper'

# As CORES DO EXEMPLAR (05/10, a mesa: "as cores delas devem ser customizáveis para o player na área de equipamentos"):
# o jogador pinta a armadura ou o escudo dele — por peça do modelo, por material — e a mesa vê no token.
RSpec.describe 'Api::V1::Player::SheetItemsController lpc_cores', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:race) { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  let(:character) { create(:character, user: user, name: 'Cores Spec PC') }
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race) }

  let(:couro) do
    item = SheetItem.new(
      sheet: sheet, item_name: 'Couro', item_index: 'leather', category: 'Armaduras', quantity: 1,
      equipped: true, slot: 'armor', source: 'test', props_json: { 'attuned' => true }
    )
    item.save!(validate: false)
    item
  end

  def pinta(cores, quem: headers)
    patch "/api/v1/player/sheet_items/#{couro.id}/lpc_cores", params: { lpc_cores: cores }, headers: quem, as: :json
  end

  it 'grava as cores do exemplar por peça e MESCLA o resto do props', :aggregate_failures do
    pinta({ 'lpc:torso_armour_leather' => { cloth: 'red', metal: 'gold' } })

    expect(response).to have_http_status(:ok), -> { response.body }
    expect(couro.reload.props_json['lpc_cores']).to eq('lpc:torso_armour_leather' => { 'cloth' => 'red', 'metal' => 'gold' })
    expect(couro.props_json['attuned']).to eq(true)
    expect(response.parsed_body.dig('sheet_item', 'props', 'lpc_cores')).to be_present
  end

  it 'só peça válida e só pano, metal e madeira, com nome de paleta', :aggregate_failures do
    pinta({ 'lpc:torso_armour_leather' => { cloth: 'red', body: 'olive', metal: 'NOT valid' }, '<script>' => { cloth: 'red' } })
    expect(couro.reload.props_json['lpc_cores']).to eq('lpc:torso_armour_leather' => { 'cloth' => 'red' })
  end

  it '`null` volta às cores do modelo' do
    pinta({ 'lpc:torso_armour_leather' => { cloth: 'red' } })
    pinta(nil)
    expect(couro.reload.props_json).not_to have_key('lpc_cores')
  end

  it 'outro jogador não pinta' do
    pinta({ 'lpc:torso_armour_leather' => { cloth: 'red' } }, quem: bearer_headers_for(create(:user)))
    expect(response.status).to be_in([403, 404])
    expect(couro.reload.props_json).not_to have_key('lpc_cores')
  end

  it 'a foto do token leva as cores do exemplar' do
    pinta({ 'lpc:torso_armour_leather' => { cloth: 'red' } })
    foto = BattleMapTokenEquipment.snapshot_for(character).find { |i| i['slot'] == 'armor' }
    expect(foto['lpcCores']).to eq('lpc:torso_armour_leather' => { 'cloth' => 'red' })
  end

  it 'o Mestre pinta pela rota admin (a ficha que estiver a editar) — e devolve ao modelo', :aggregate_failures do
    dm = create(:user, role: Role.find_by(name: 'DM') || create(:role, name: 'DM'))
    patch "/api/v1/admin/sheet_items/#{couro.id}/lpc_cores", params: { lpc_cores: { escudo: { wood: 'oak' } } }, headers: bearer_headers_for(dm), as: :json
    expect(response).to have_http_status(:ok), -> { response.body }
    expect(couro.reload.props_json['lpc_cores']).to eq('escudo' => { 'wood' => 'oak' })

    patch "/api/v1/admin/sheet_items/#{couro.id}/lpc_cores", params: { lpc_cores: nil }, headers: bearer_headers_for(dm), as: :json
    expect(couro.reload.props_json).not_to have_key('lpc_cores')
  end
end
