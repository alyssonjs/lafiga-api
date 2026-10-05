# frozen_string_literal: true

require 'rails_helper'

# LPC no MAPA (02/10, "vamos ligar o catálogo de itens às peças LPC"): o mestre declara no catálogo qual PEÇA do
# personagem em camadas o item veste (`props.lpc_pecas`). Ela chega ao front pelo inventário da ficha e pela foto de
# equipamento do token — que agora leva também o que se VESTE (armadura, botas…), não só as mãos.
RSpec.describe 'Peças LPC declaradas no catálogo', type: :service do
  let(:character) { create(:character) }
  let!(:sheet) { create(:sheet, character: character) }

  def catalogo!(slug, kind: 'armor', props: {})
    Item.find_by(api_index: slug) || Item.create!(api_index: slug, name: slug.tr('-', ' '), kind: kind, props: props)
  end

  def linha!(catalogo, nome, slot: nil)
    linha = SheetItem.create!(sheet: sheet, item: catalogo, item_name: nome, item_index: catalogo&.api_index,
                              category: 'Armaduras', quantity: 1, props_json: {})
    linha.update_columns(equipped: true, slot: slot) if slot
    linha
  end

  describe 'EquipmentRules.lpc_pecas' do
    it 'devolve só parte e cores de material conhecido (o props do catálogo é livre)' do
      gibao = catalogo!('gibao-lpc', props: {
        'lpc_pecas' => [
          { 'parte' => 'couro', 'cor' => { 'cloth' => 'red', 'tinta' => 'x', 'metal' => 'Ouro!' } },
          'lixo',
          { 'parte' => 'couro; drop table' },
          { 'parte' => 'placas' },
        ],
      })

      expect(EquipmentRules.lpc_pecas(linha!(gibao, 'Gibão'))).to eq([
        { 'parte' => 'couro', 'cor' => { 'cloth' => 'red' } },
        { 'parte' => 'placas' },
      ])
    end

    it 'aceita peça da BIBLIOTECA do LPC (lpc:<id>) e o material madeira' do
      arco = catalogo!('arco-lpc', kind: 'weapon', props: {
        'lpc_pecas' => [{ 'parte' => 'lpc:weapon_ranged_bow_normal', 'cor' => { 'wood' => 'walnut' } }, { 'parte' => 'lpc:x:y' }],
      })

      expect(EquipmentRules.lpc_pecas(linha!(arco, 'Arco'))).to eq([
        { 'parte' => 'lpc:weapon_ranged_bow_normal', 'cor' => { 'wood' => 'walnut' } },
      ])
    end

    it 'sem declaração é nil — o front deduz a peça do tipo do item' do
      expect(EquipmentRules.lpc_pecas(linha!(catalogo!('cota-comum'), 'Cota'))).to be_nil
      expect(EquipmentRules.lpc_pecas(linha!(nil, 'Feita à mão'))).to be_nil
    end
  end

  it 'o inventário da ficha leva as peças declaradas (e nil sem declaração)' do
    gibao = catalogo!('gibao-do-mestre', props: { 'lpc_pecas' => [{ 'parte' => 'couro', 'cor' => { 'cloth' => 'navy' } }] })

    expect(linha!(gibao, 'Gibão do Mestre').as_inventory_json[:lpc_pecas]).to eq([{ 'parte' => 'couro', 'cor' => { 'cloth' => 'navy' } }])
    expect(linha!(catalogo!('peles'), 'Peles').as_inventory_json[:lpc_pecas]).to be_nil
  end

  describe 'a foto de equipamento do token' do
    it 'leva o que o personagem VESTE, com as peças, além das mãos; anel não entra' do
      placas = catalogo!('placas-do-rei', props: { 'lpc_pecas' => [{ 'parte' => 'placas', 'cor' => { 'metal' => 'gold' } }] })
      linha!(placas, 'Placas do Rei', slot: 'armor')
      linha!(catalogo!('botas-de-couro', kind: 'gear'), 'Botas de Couro', slot: 'boots')
      linha!(catalogo!('espada-curta', kind: 'weapon'), 'Espada Curta', slot: 'main_hand')
      linha!(catalogo!('anel-de-ouro', kind: 'gear'), 'Anel de Ouro', slot: 'ring_left')

      foto = BattleMapTokenEquipment.snapshot_for(character)

      expect(foto.map { |i| i['slot'] }).to contain_exactly('armor', 'boots', 'main_hand')
      expect(foto.find { |i| i['slot'] == 'armor' }['lpcPecas']).to eq([{ 'parte' => 'placas', 'cor' => { 'metal' => 'gold' } }])
      expect(foto.find { |i| i['slot'] == 'boots' }).not_to have_key('lpcPecas')
    end
  end
end
