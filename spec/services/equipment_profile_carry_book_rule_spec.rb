# frozen_string_literal: true

require 'rails_helper'

# CAPACIDADE DE CARGA pela regra do LIVRO (31/08).
#
# O serviço convertia lb→kg pelo fator FÍSICO (0,45359237) e dava 68,04 kg de
# capacidade para FOR 10, enquanto a barra na tela mostrava 75. O mesmo
# personagem com dois tetos — e a CARGA lida de `weight_lb` encolhia os mesmos
# 9%, porque o mesmo literal estava nos dois lados da comparação.
#
# A convenção desta mesa é a do LIVRO: `EquipmentRules::LB_PER_KG = 2.0`, a
# mesma que o serializer já usava. A espada de 3 lb do PHB pesa 1,5 kg aqui.
RSpec.describe EquipmentProfileService, 'capacidade pela regra do livro' do
  let(:sheet) { create(:sheet) }

  def carry_for(str, metadata: {})
    sheet.update!(str: str, metadata: metadata)
    EquipmentProfileService.new(sheet.reload).call[:carry]
  end

  describe 'o fator' do
    it 'FOR 10 carrega 75 kg — o fator do LIVRO, não os 68,04 do físico' do
      expect(carry_for(10)[:capacity_kg]).to eq(75.0)
    end

    it 'empurrar/arrastar/erguer é o dobro: 150 kg' do
      expect(carry_for(10)[:push_drag_lift_kg]).to eq(150.0)
    end

    it 'escala linear com a Força' do
      expect(carry_for(20)[:capacity_kg]).to eq(150.0)
      expect(carry_for(8)[:capacity_kg]).to eq(60.0)
    end

    it 'bate com a conta do front (FOR × 15 lb ÷ 2)' do
      # Se um dia divergirem outra vez, é aqui que se vê primeiro.
      (1..20).each do |str|
        esperado = (str * 15) / EquipmentRules::LB_PER_KG
        expect(carry_for(str)[:capacity_kg]).to eq(esperado.round(2))
      end
    end
  end

  describe 'a CARGA vem na mesma convenção que a capacidade' do
    it 'item de 3 lb pesa 1,5 kg — e não 1,36' do
      # O numerador e o denominador da comparação têm de falar a mesma língua;
      # senão a barra enche mais devagar do que a regra manda.
      SheetItem.create!(sheet: sheet, item_name: 'Espada Longa', category: 'Armas',
                        quantity: 1, source: 'test', props_json: { 'weight_lb' => 3 })

      expect(carry_for(10)[:total_kg]).to eq(1.5)
    end

    it 'peso já em kg não é convertido duas vezes' do
      SheetItem.create!(sheet: sheet, item_name: 'Barril', category: 'Itens Gerais',
                        quantity: 1, source: 'test', props_json: { 'weight_kg' => 10 })

      expect(carry_for(10)[:total_kg]).to eq(10.0)
    end
  end

  describe 'Construção Poderosa dobra a capacidade' do
    it 'FOR 10 com o traço carrega 150 kg' do
      carry = carry_for(10, metadata: { 'features' => [{ 'name' => 'Construção Poderosa' }] })

      expect(carry[:capacity_kg]).to eq(150.0)
    end

    it 'dobra também os limiares da variante, não só o teto' do
      # Se só o teto dobrasse, o goliath ficava sobrecarregado a meio caminho
      # da própria capacidade.
      SheetItem.create!(sheet: sheet, item_name: 'Carga', category: 'Itens Gerais',
                        quantity: 1, source: 'test', props_json: { 'weight_kg' => 30 })
      meta = { 'encumbrance_variant' => true, 'features' => [{ 'name' => 'Powerful Build' }] }

      # FOR 10 sem traço: 30 kg passa de FOR×5 (25 kg) e seria 'encumbered'.
      expect(carry_for(10, metadata: { 'encumbrance_variant' => true })[:status]).not_to eq('normal')
      expect(carry_for(10, metadata: meta)[:status]).to eq('normal')
    end
  end
end
