# frozen_string_literal: true

require 'rails_helper'

# EMPUNHADURA da arma versátil (`props_json['using_two_hands']`).
#
# O contrato já existia no controller e a regra de exclusividade já o lia
# (`SheetItem#enforce_slot_exclusivity_and_conflicts`), mas NADA o exercitava:
# nenhum cliente enviava a chave e nenhum spec a cobria. Estes testes fecham o
# caminho que o front passou a usar em 01/09/2026.
RSpec.describe 'Api::V1::Player::SheetItemsController empunhadura versátil', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:race) { human_race }
  let(:sub_race) { human_standard_subrace(race) }
  let(:character) { create(:character, user: user, name: 'Grip Spec PC') }
  let!(:sheet) { create(:sheet, character: character, race: race, sub_race: sub_race) }

  def criar_espada(nome: 'Espada Longa', index: 'longsword')
    SheetItem.create!(
      sheet: sheet, item_name: nome, item_index: index, category: 'Armas',
      quantity: 1, equipped: false, source: 'test',
      props_json: { 'weapon_props' => { 'versatile' => true, 'versatile_die' => '1d10' } }
    )
  end

  # A "outra mão" ocupada: usamos uma ADAGA na secundária em vez de escudo —
  # escudo exige proficiência (validação do modelo, alheia à empunhadura) e o
  # `enforce_slot_exclusivity_and_conflicts` derruba `off_hand` E `shield` na
  # mesma linha, então a adaga prova a mesma regra sem montar proficiência.
  def criar_adaga_secundaria
    SheetItem.create!(
      sheet: sheet, item_name: 'Adaga', item_index: 'dagger', category: 'Armas',
      quantity: 1, equipped: false, source: 'test', props_json: {}
    )
  end

  it 'persiste `using_two_hands` no equip e devolve em `props`' do
    espada = criar_espada

    post "/api/v1/player/sheet_items/#{espada.id}/equip",
         params: { slot: 'main_hand', props_json: { using_two_hands: true } },
         headers: headers, as: :json

    expect(response).to have_http_status(:ok), -> { response.body }
    body = response.parsed_body['sheet_item']
    expect(body['props']['using_two_hands']).to eq(true)
    expect(espada.reload.props_json['using_two_hands']).to eq(true)
  end

  it 'persiste a escolha de UMA mão (false é estado real, não ausência)' do
    espada = criar_espada

    post "/api/v1/player/sheet_items/#{espada.id}/equip",
         params: { slot: 'main_hand', props_json: { using_two_hands: false } },
         headers: headers, as: :json

    expect(response).to have_http_status(:ok), -> { response.body }
    # ⚠️ `false` TEM de sobreviver: é "escolhi deixar a outra mão livre".
    # Se virasse ausência, o front voltaria a INFERIR duas mãos.
    expect(espada.reload.props_json).to have_key('using_two_hands')
    expect(espada.props_json['using_two_hands']).to eq(false)
  end

  it 'duas mãos ESVAZIA a mão secundária — não dá para segurar as duas coisas' do
    adaga = criar_adaga_secundaria
    espada = criar_espada

    post "/api/v1/player/sheet_items/#{adaga.id}/equip",
         params: { slot: 'off_hand' }, headers: headers, as: :json
    expect(response).to have_http_status(:ok), -> { response.body }
    expect(adaga.reload.equipped).to be true

    post "/api/v1/player/sheet_items/#{espada.id}/equip",
         params: { slot: 'main_hand', props_json: { using_two_hands: true } },
         headers: headers, as: :json
    expect(response).to have_http_status(:ok), -> { response.body }

    expect(adaga.reload.equipped).to be false
    expect(adaga.slot).to be_nil
  end

  it 'UMA mão CONVIVE com a arma secundária' do
    adaga = criar_adaga_secundaria
    espada = criar_espada

    post "/api/v1/player/sheet_items/#{adaga.id}/equip",
         params: { slot: 'off_hand' }, headers: headers, as: :json
    post "/api/v1/player/sheet_items/#{espada.id}/equip",
         params: { slot: 'main_hand', props_json: { using_two_hands: false } },
         headers: headers, as: :json
    expect(response).to have_http_status(:ok), -> { response.body }

    expect(adaga.reload.equipped).to be true
  end

  it 'trocar a empunhadura re-equipando no MESMO slot mescla as props (não zera as outras)' do
    espada = criar_espada
    espada.update!(props_json: espada.props_json.merge('attuned' => true))

    post "/api/v1/player/sheet_items/#{espada.id}/equip",
         params: { slot: 'main_hand', props_json: { using_two_hands: false } },
         headers: headers, as: :json
    post "/api/v1/player/sheet_items/#{espada.id}/equip",
         params: { slot: 'main_hand', props_json: { using_two_hands: true } },
         headers: headers, as: :json
    expect(response).to have_http_status(:ok), -> { response.body }

    espada.reload
    expect(espada.props_json['using_two_hands']).to eq(true)
    expect(espada.props_json['attuned']).to eq(true)   # o merge preserva o resto
    expect(espada.equipped).to be true
    expect(espada.slot).to eq('main_hand')
  end
end
