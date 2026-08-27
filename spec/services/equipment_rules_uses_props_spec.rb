# frozen_string_literal: true

require 'rails_helper'

# Cargas de item mágico: o teto vem de `items.props['uses_max']` OU, quando o
# espelho não o tem, de `magic_items.charges`.
RSpec.describe 'EquipmentRules.uses_props — cargas de item mágico' do
  # A linha da FICHA é o que carrega `magical` — é esse o portão que evita uma
  # consulta a MagicItem por linha de bolsa.
  def linha(item, magical: true)
    OpenStruct.new(item: item, item_index: item.api_index, item_id: item.id,
                   props_json: magical ? { 'magical' => true } : {})
  end

  describe 'ponte MagicItem → cano de usos' do
    let!(:espelho) do
      Item.create!(api_index: 'varinha-spec', name: 'Varinha de Teste', kind: 'magic_item')
    end
    let!(:magico) do
      MagicItem.create!(slug: 'varinha-spec', name: 'Varinha de Teste', category: 'wand',
                        rarity: 'uncommon', charges: 7, recharge: 'long')
    end

    it '⚠️ lê as cargas do MagicItem quando o espelho não tem uses_max' do
      # Sem esta ponte o cano não via carga nenhuma e TODO item mágico com
      # cargas ficava inerte — medido na base: os 2 itens com `charges > 0`
      # tinham `uses_max` nulo no espelho.
      expect(espelho.props['uses_max']).to be_nil

      out = EquipmentRules.uses_props(linha(espelho))
      expect(out).to eq('uses_max' => 7, 'uses_recharge' => 'long')
    end

    it 'o espelho VENCE quando declara o próprio teto (autoridade local)' do
      espelho.update!(props: { 'uses_max' => 3, 'uses_recharge' => 'short' })
      out = EquipmentRules.uses_props(linha(espelho.reload))
      expect(out['uses_max']).to eq(3)
      expect(out['uses_recharge']).to eq('short')
    end

    it 'casa por NOME quando o slug diverge do api_index' do
      outro = Item.create!(api_index: 'indice-antigo', name: 'Varinha de Teste', kind: 'magic_item')
      expect(EquipmentRules.uses_props(linha(outro))['uses_max']).to eq(7)
    end

    it 'item mágico SEM cargas continua sem usos (não inventa contador)' do
      magico.update!(charges: 0)
      expect(EquipmentRules.uses_props(linha(espelho))).to be_nil
    end

    it 'item comum (sem MagicItem) segue sem usos' do
      comum = Item.create!(api_index: 'corda-spec', name: 'Corda', kind: 'gear')
      expect(EquipmentRules.uses_props(linha(comum))).to be_nil
    end

    it '⚠️ linha NÃO-mágica nem consulta o MagicItem (gate de performance)' do
      # Sem o gate a busca correria em toda linha sem `uses_max` — ~90 por bolsa.
      expect(MagicItem).not_to receive(:find_by)
      expect(EquipmentRules.uses_props(linha(espelho, magical: false))).to be_nil
    end
  end
end
