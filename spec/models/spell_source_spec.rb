# frozen_string_literal: true

require 'rails_helper'

# ⚠️ Esta tabela é AUTORIDADE para `Klass` e `SubKlass` (1.302 linhas vivas): o
# level-up e as magias preparadas leem dela. O que a fase 0 acrescenta é a
# conjuração INATA — raça, sub-raça, talento e feature — e os modos de custo.
RSpec.describe SpellSource do
  let!(:spell) { Spell.create!(api_index: 'thaumaturgy', name: 'Taumaturgia', level: 0) }
  let!(:race) { Race.create!(api_index: 'tiefling-x', name: 'Tiefling') }

  def cria(attrs = {})
    described_class.new({ source_type: 'Race', source_id: race.id, spell: spell }.merge(attrs))
  end

  describe 'vocabulários' do
    it 'aceita os tipos que o pedido cobre' do
      %w[Race SubRace Feat Feature].each do |t|
        expect(cria(source_type: t)).to be_valid, "#{t} devia ser aceite"
      end
    end

    it 'recusa tipo inventado' do
      expect(cria(source_type: 'Planeta')).not_to be_valid
    end

    it 'o default é `with_slot` — o que as 1.302 linhas existentes significam' do
      expect(described_class.new.casting_mode).to eq('with_slot')
    end
  end

  describe '⚠️ o limite só existe no modo que o respeita' do
    it 'recusa "1/descanso longo" num modo que ignora usos' do
      # Seria pior do que não ter: a ficha mostraria "1/dia" e a regra deixaria
      # conjurar à vontade.
      s = cria(casting_mode: 'at_will', uses_per_long_rest: 1)
      expect(s).not_to be_valid
      expect(s.errors[:uses_per_long_rest].join).to match(/uses_per_rest/)
    end

    it 'aceita no modo certo' do
      expect(cria(casting_mode: 'uses_per_rest', uses_per_long_rest: 1)).to be_valid
    end

    it 'recusa recurso fora do modo `resource`' do
      expect(cria(casting_mode: 'at_will', resource_key: 'ki', resource_cost: 2)).not_to be_valid
    end

    it 'aceita o Monge das Sombras: 2 Chi, sem espaço' do
      s = cria(casting_mode: 'resource', resource_key: 'ki', resource_cost: 2)
      expect(s).to be_valid
      expect(s.cost_label).to eq('2 ki')
    end
  end

  describe '#cost_label — o que a ficha mostra' do
    it 'diz o custo por extenso' do
      expect(cria(casting_mode: 'at_will').cost_label).to eq('à vontade')
      expect(cria(casting_mode: 'uses_per_rest', uses_per_long_rest: 1).cost_label)
        .to eq('1/descanso longo')
      expect(cria(casting_mode: 'with_slot').cost_label).to eq('espaço de magia')
    end
  end

  describe 'pool vs concessão' do
    it '⚠️ `grant_mode` existe desde o dia 1' do
      # O Alto Elfo ESCOLHE 1 truque de mago. Tratar pool como concessão fez o
      # índice de proficiências mentir em 237 linhas antes de ser corrigido.
      expect(cria(grant_mode: 'choice', choose_count: 1)).to be_valid
      expect(cria(grant_mode: 'talvez')).not_to be_valid
    end
  end

  describe '#source_record' do
    it 'resolve a fonte real' do
      s = described_class.create!(source_type: 'Race', source_id: race.id, spell: spell)
      expect(s.source_record).to eq(race)
    end

    it 'devolve nil sem estourar quando a fonte sumiu' do
      # Não há FK em `source_id` (é polimórfica), então fonte órfã É possível —
      # ao contrário de `spell_id`, que o banco protege.
      s = described_class.create!(source_type: 'Race', source_id: 999_999, spell: spell)
      expect(s.source_record).to be_nil
    end
  end
end
