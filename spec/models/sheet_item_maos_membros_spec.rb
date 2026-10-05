# frozen_string_literal: true

require 'rails_helper'

# MEMBRO PERDIDO nas MÃOS (05/10, Guia do Mestre): sem uma mão (ou com gancho/lâmina no lugar), nada com duas mãos e
# um objeto por vez — o que estava na outra casa sai; sem as duas, nada nas mãos.
RSpec.describe SheetItem, 'as mãos que sobram', type: :model do
  # A subclasse leve do `sheet_item_segurar_spec`: só a regra das mãos (sem a proficiência em escudo e o catálogo).
  before(:all) do
    Object.const_set(:SheetItemMaosTest, Class.new(SheetItem) do
      self.table_name = 'sheet_items'
      clear_validators!
      validate :cabe_nas_maos_que_sobram
    end)
  end
  after(:all) do
    Object.send(:remove_const, :SheetItemMaosTest) if Object.const_defined?(:SheetItemMaosTest)
  end

  let(:sheet) { create(:sheet, character: create(:character, user: create(:user))) }

  def membros!(m)
    sheet.update!(avatar_customization: { 'membros' => m })
  end

  def equipar(nome, slot, props = {})
    SheetItemMaosTest.create!(sheet_id: sheet.id, item_name: nome, quantity: 1, equipped: true, slot: slot, props_json: props)
  end

  it 'com as duas mãos, nada muda' do
    escudo = equipar('Escudo', 'shield')
    equipar('Orbe', 'main_hand')
    expect(escudo.reload.equipped).to be(true)
  end

  it 'com UMA mão, o que estava na outra casa sai (um objeto por vez)', :aggregate_failures do
    membros!('mao_esquerdo' => { 'estado' => 'perdido' })
    escudo = equipar('Escudo', 'shield')
    equipar('Orbe', 'main_hand')
    expect(escudo.reload.equipped).to be(false)
    expect(escudo.slot).to be_nil
  end

  it 'com UMA mão (o gancho conta como sem mão), nada com as duas', :aggregate_failures do
    membros!('mao_direito' => { 'estado' => 'substituido', 'substituto' => { 'tipo' => 'gancho' } })
    expect { equipar('Baú', 'main_hand', { 'using_two_hands' => true }) }.to raise_error(ActiveRecord::RecordInvalid, /duas mãos/)
  end

  it 'a prótese devolve a mão' do
    membros!('mao_direito' => { 'estado' => 'substituido', 'substituto' => { 'tipo' => 'protese' } })
    escudo = equipar('Escudo', 'shield')
    equipar('Orbe', 'main_hand')
    expect(escudo.reload.equipped).to be(true)
  end

  it 'sem as duas, nada nas mãos' do
    membros!('braco_direito' => { 'estado' => 'perdido' }, 'antebraco_esquerdo' => { 'estado' => 'perdido' })
    expect { equipar('Orbe', 'main_hand') }.to raise_error(ActiveRecord::RecordInvalid, /Sem mãos/)
  end

  it '⚠️ salvar o que JÁ estava na mão (gastar a adaga) não esbarra na regra' do
    adaga = equipar('Adaga', 'main_hand')
    membros!('braco_direito' => { 'estado' => 'perdido' }, 'braco_esquerdo' => { 'estado' => 'perdido' })
    expect { adaga.update!(quantity: 2) }.not_to raise_error
  end
end
