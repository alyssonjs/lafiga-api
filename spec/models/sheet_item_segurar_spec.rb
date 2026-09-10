# frozen_string_literal: true

require 'rails_helper'

# SEGURAR com duas mãos — qualquer item, não só arma.
#
# ⚠️ A regra de conflito estava gated em `EquipmentRules.is_weapon?`: um item
# comum gravava `using_two_hands: true` e a regra IGNORAVA. O personagem ficava
# a segurar um baú com "as duas mãos" e um escudo ao mesmo tempo.
RSpec.describe SheetItem, 'segurar com duas mãos', type: :model do
  # Subclasse leve, no molde do irmão `sheet_item_spec`: o que se afere aqui é
  # a REGRA DE CONFLITO entre slots, não a proficiência em escudo nem o resto
  # das validações de equipagem.
  before(:all) do
    Object.const_set(:SheetItemSegurarTest, Class.new(SheetItem) do
      self.table_name = 'sheet_items'
      clear_validators!
    end)
  end
  after(:all) do
    Object.send(:remove_const, :SheetItemSegurarTest) if Object.const_defined?(:SheetItemSegurarTest)
  end

  let(:sheet) { create(:sheet, character: create(:character, user: create(:user))) }

  def equipar(nome, slot, props = {})
    SheetItemSegurarTest.create!(
      sheet_id: sheet.id, item_name: nome, quantity: 1,
      equipped: true, slot: slot, props_json: props
    )
  end

  it '⚠️ item COMUM com duas mãos derruba o escudo' do
    escudo = equipar('Escudo', 'shield')
    equipar('Baú Pesado', 'main_hand', { 'using_two_hands' => true })

    expect(escudo.reload.equipped).to be(false)
    expect(escudo.slot).to be_nil
  end

  it '⚠️ e derruba a mão secundária' do
    secundaria = equipar('Tocha', 'off_hand')
    equipar('Baú Pesado', 'main_hand', { 'using_two_hands' => true })

    expect(secundaria.reload.equipped).to be(false)
  end

  it 'com UMA mão, o escudo fica', :aggregate_failures do
    escudo = equipar('Escudo', 'shield')
    equipar('Orbe', 'main_hand', { 'using_two_hands' => false })

    expect(escudo.reload.equipped).to be(true)
    expect(escudo.slot).to eq('shield')
  end

  it '⚠️ AUSENTE não é duas mãos — não rebaixa o que já estava equipado' do
    # Mesma disciplina do resto da casa: ausente ≠ falso, e tratar ausente como
    # "duas mãos" derrubaria escudos de fichas antigas em silêncio.
    escudo = equipar('Escudo', 'shield')
    equipar('Orbe', 'main_hand', {})

    expect(escudo.reload.equipped).to be(true)
  end

  it 'a exclusividade do slot continua: dois itens não cabem na mesma mão' do
    primeiro = equipar('Orbe', 'main_hand')
    equipar('Cristal', 'main_hand')

    expect(primeiro.reload.equipped).to be(false)
  end
end
