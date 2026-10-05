# frozen_string_literal: true

require 'rails_helper'

# O MODELO de cada armadura e escudo (05/10, a mesa: "não vamos adotar o modelo por nome, é muito vago. Vamos associar
# os modelos pelo banco de dados"). O yml SEMEIA pelo api_index exato ou pela categoria; o modelo VESTIDO é o do banco
# (`items.props.lpc_pecas`), e a armadura mágica herda o da armadura-base pelo `sub_category`.
RSpec.describe LpcModelosDoCatalogo do
  def item!(idx, kind:, category: nil, name: nil, props: {})
    Item.where(api_index: idx).delete_all
    Item.create!(api_index: idx, name: name || idx.tr('-', ' ').capitalize, kind: kind, category: category, props: props)
  end

  it 'pelo api_index EXATO: as armaduras do livro e os escudos do banco' do
    expect(described_class.para(item!('plate', kind: 'armor', category: 'heavy')).map { |p| p['parte'] }).to eq(%w[
      lpc:torso_armour_plate lpc:shoulders_legion lpc:arms_armour lpc:arms_gloves lpc:legs_armour lpc:feet_armour
    ])
    expect(described_class.para(item!('escudo-de-madeira', kind: 'shield')))
      .to eq([{ 'parte' => 'lpc:shield_round', 'cor' => { 'cloth' => 'brown' } }])
    expect(described_class.para(item!('escudo-grande', kind: 'shield', category: 'shield')))
      .to eq([{ 'parte' => 'lpc:shield_scutum' }, { 'parte' => 'lpc:shield_scutum_trim' }])
  end

  it 'sem o índice, pela CATEGORIA do banco; o escudo sem categoria, pelo kind; a armadura sem categoria fica sem' do
    expect(described_class.para(item!('brigantina-da-mesa', kind: 'armor', category: 'medium')))
      .to eq([{ 'parte' => 'lpc:torso_chainmail', 'cor' => { 'metal' => 'iron' } }])
    expect(described_class.para(item!('escudo-m', kind: 'shield'))).to eq([{ 'parte' => 'escudo' }])
    expect(described_class.para(item!('cota-de-malha-roupa', kind: 'armor'))).to be_nil
  end

  it 'nunca pelo NOME: "Armadura de Placas" com outro índice e sem categoria não vira placas' do
    expect(described_class.para(item!('armadura-do-joao', kind: 'armor', name: 'Armadura de Placas'))).to be_nil
  end
end

RSpec.describe EquipmentRules, '.lpc_pecas — o modelo vestido é o do banco' do
  let(:sheet) { create(:sheet) }
  let(:placas) { [{ 'parte' => 'lpc:torso_armour_plate', 'cor' => { 'metal' => 'silver' } }, { 'parte' => 'lpc:legs_armour' }] }

  def item!(idx, kind:, category: nil, props: {})
    Item.where(api_index: idx).delete_all
    Item.create!(api_index: idx, name: idx.tr('-', ' ').capitalize, kind: kind, category: category, props: props)
  end

  def vestido!(item, idx, props_json: {}, slot: 'armor')
    si = SheetItem.create!(sheet: sheet, item: item, item_index: idx, item_name: idx, category: 'Armaduras', quantity: 1,
                           equipped: false, props_json: props_json)
    si.update_columns(equipped: slot.present?, slot: slot)
    si.reload
  end

  it 'o modelo gravado no item do catálogo' do
    base = item!('plate', kind: 'armor', category: 'heavy', props: { 'lpc_pecas' => placas })
    expect(described_class.lpc_pecas(vestido!(base, 'plate'))).to eq(placas)
  end

  it 'a armadura MÁGICA (a linha do catálogo é uma casca) veste o da armadura-base; o declarado nela vence' do
    item!('plate', kind: 'armor', category: 'heavy', props: { 'lpc_pecas' => placas })
    casca = item!('armadura-divina-spec', kind: 'gear')
    MagicItem.where(slug: 'armadura-divina-spec').delete_all
    magico = MagicItem.create!(name: 'Armadura Divina', slug: 'armadura-divina-spec', rarity: 'rare', category: 'armor',
                               sub_category: 'plate', requires_attunement: false, effects: [])
    si = vestido!(casca, 'armadura-divina-spec', props_json: { 'magical' => true })
    expect(described_class.lpc_pecas(si)).to eq(placas)

    magico.update!(properties: { 'lpc_pecas' => [{ 'parte' => 'lpc:torso_chainmail', 'cor' => { 'metal' => 'gold' } }] })
    expect(described_class.lpc_pecas(si)).to eq([{ 'parte' => 'lpc:torso_chainmail', 'cor' => { 'metal' => 'gold' } }])
  end

  it 'só a linha mágica VESTIDA numa casa de armadura consulta o item mágico (o inventário não paga a busca)' do
    item!('plate', kind: 'armor', category: 'heavy', props: { 'lpc_pecas' => placas })
    casca = item!('armadura-guardada-spec', kind: 'gear')
    MagicItem.where(slug: 'armadura-guardada-spec').delete_all
    MagicItem.create!(name: 'Guardada', slug: 'armadura-guardada-spec', rarity: 'rare', category: 'armor',
                      sub_category: 'plate', requires_attunement: false, effects: [])
    expect(described_class.lpc_pecas(vestido!(casca, 'armadura-guardada-spec', props_json: { 'magical' => true }, slot: nil))).to be_nil
    expect(described_class.lpc_pecas(vestido!(casca, 'armadura-guardada-spec', props_json: {}))).to be_nil
  end
end
