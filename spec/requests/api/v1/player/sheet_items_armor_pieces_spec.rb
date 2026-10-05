# frozen_string_literal: true

require 'rails_helper'

# PEÇAS DE ARMADURA (04/10/2026). Pedido da mesa: "slots de vestimenta e slots de armadura — os slots de armadura
# devem sobrescrever os de vestimenta". O elmo vive AO LADO do chapéu (`armor_head` × `helmet`), a manopla ao lado da
# luva, o escarpe ao lado da bota; o peitoral segue sendo o `armor`, o único (com o escudo) que dá CA.
RSpec.describe 'SheetItems — casas de PEÇA DE ARMADURA', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:character) { create(:character, user: user, name: 'Armor Pieces Spec') }
  let!(:sheet) { create(:sheet, character: character) }

  def catalogo!(nome, kind, props: {})
    Item.create!(name: nome, api_index: "spec-#{nome.parameterize}-#{SecureRandom.hex(3)}", kind: kind, props: props)
  end

  def linha!(item)
    SheetItem.create!(sheet: sheet, item_name: item.name, item_index: item.api_index,
                      category: 'Equipamento', quantity: 1, source: 'test')
  end

  def equipa!(linha, slot)
    post "/api/v1/player/sheet_items/#{linha.id}/equip", params: { slot: slot }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
  end

  it 'as seis casas novas são aceitas, ao lado das de sempre' do
    expect(SheetItem::ARMOR_PIECE_SLOTS).to eq(%w[armor_head armor_shoulders armor_arms armor_hands armor_legs armor_feet])
    expect(SheetItem::ALL_SLOTS).to include(*SheetItem::ARMOR_PIECE_SLOTS, 'armor', 'helmet', 'gloves', 'boots')
  end

  it 'o chapéu e o elmo ficam vestidos AO MESMO TEMPO (casas diferentes)' do
    chapeu = linha!(catalogo!('Spec Chapéu', 'gear', props: { 'equip_slot' => 'helmet' }))
    elmo = linha!(catalogo!('Spec Elmo', 'armor', props: { 'equip_slot' => 'armor_head' }))

    equipa!(chapeu, 'helmet')
    equipa!(elmo, 'armor_head')

    expect(chapeu.reload).to have_attributes(equipped: true, slot: 'helmet')
    expect(elmo.reload).to have_attributes(equipped: true, slot: 'armor_head')
  end

  it 'o catálogo declara a casa: o inventário responde armor_head para o elmo' do
    item = catalogo!('Spec Bacinete', 'armor', props: { 'equip_slot' => 'armor_head' })
    linha!(item)

    get "/api/v1/player/sheet_items?sheet_id=#{sheet.id}", headers: headers, as: :json
    expect(response.parsed_body['sheet_items'].find { |r| r['index'] == item.api_index }['equip_slot']).to eq('armor_head')
  end

  it 'uma peça por casa: a segunda manopla tira a primeira' do
    uma = linha!(catalogo!('Spec Manoplas A', 'armor', props: { 'equip_slot' => 'armor_hands' }))
    outra = linha!(catalogo!('Spec Manoplas B', 'armor', props: { 'equip_slot' => 'armor_hands' }))

    equipa!(uma, 'armor_hands')
    equipa!(outra, 'armor_hands')

    expect(outra.reload).to have_attributes(equipped: true, slot: 'armor_hands')
    expect(uma.reload).to have_attributes(equipped: false, slot: nil)
  end

  it 'a peça de armadura não vira o peitoral: a CA segue a do corpo' do
    sem = EquipmentProfileService.new(sheet).call[:ac]
    grevas = linha!(catalogo!('Spec Grevas', 'armor', props: { 'equip_slot' => 'armor_legs' }))
    equipa!(grevas, 'armor_legs')

    expect(EquipmentProfileService.new(sheet.reload).call[:ac]).to eq(sem)
  end

  it 'a foto do token leva a peça (os outros jogadores veem o elmo)' do
    elmo = linha!(catalogo!('Spec Armete', 'armor', props: { 'equip_slot' => 'armor_head' }))
    equipa!(elmo, 'armor_head')

    snapshot = BattleMapTokenEquipment.snapshot_for(character.reload)
    expect(snapshot.map { |i| i['slot'] }).to include('armor_head')
  end
end
