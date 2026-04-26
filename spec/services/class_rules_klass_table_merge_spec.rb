# frozen_string_literal: true

require 'rails_helper'

# BDD — Loop 3: `ClassRules.rules_with_klass_table` funde `klasses.rules` no SRD.
RSpec.describe 'ClassRules klass table merge', type: :model do
  describe 'B5 — merge' do
    it 'B5.0 — sem yields em Klass, merge e igual a rules (SRD puro)' do
      allow(Klass).to receive(:find_each) do
        # nao chama o bloco = nenhum registo
      end
      expect(ClassRules.rules_with_klass_table).to eq(ClassRules.rules)
    end

    it 'B5.1 — classe so no DB aparece no hash' do
      create(
        :klass,
        name: 'Loop3 HB',
        api_index: 'loop3_homebrew_only',
        hit_die: 6,
        rules: {
          id: 'loop3_homebrew_only',
          name: 'Só DB',
          hit_die: 'd6',
          primary_abilities: %w[DEX]
        }
      )
      merged = ClassRules.rules_with_klass_table
      expect(merged[:loop3_homebrew_only]).to be_a(Hash)
      expect(merged[:loop3_homebrew_only][:name]).to eq('Só DB')
    end
  end
end
