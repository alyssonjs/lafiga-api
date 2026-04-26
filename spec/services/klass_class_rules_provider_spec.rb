# frozen_string_literal: true

require 'rails_helper'

# BDD — fonte de regras em `klasses.rules` (Loop 1 da migração ClassRules -> DB).
# Garante que o provider e `ClassRules.find` não quebram o legado (CLASS_RULES).
RSpec.describe KlassClassRulesProvider, type: :model do
  describe 'B1 — Provider' do
    it 'B1.1 — retorna nil quando nao existe klass' do
      expect(described_class.call('__no_such_index__')).to be_nil
    end

    it 'B1.2 — retorna nil quando rules em branco' do
      create(:klass, api_index: 'bdd_empty_rules', rules: nil)
      expect(described_class.call('bdd_empty_rules')).to be_nil
    end

    it 'B1.3 — retorna nil quando rules e {}' do
      create(:klass, api_index: 'bdd_hash_empty', rules: {})
      expect(described_class.call('bdd_hash_empty')).to be_nil
    end

    it 'B1.4 — chaves simbolo + saving_throws traduzidos como ClassRules' do
      create(
        :klass,
        api_index: 'bdd_saves',
        rules: {
          'saving_throws' => %w[str wis],
          'primary_abilities' => %w[STR WIS]
        }
      )
      out = described_class.call('bdd_saves')
      expect(out[:primary_abilities]).to eq(%w[STR WIS])
      expect(out[:saving_throws]).to eq(
        SavingThrowsCatalog.translate_array(%w[str wis])
      )
    end
  end
end

RSpec.describe 'ClassRules.find + DB (integração)', type: :model do
  describe 'B2 — Paridade e preferência DB' do
    it 'B2.1 — com nenhum rules no DB, find == find_from_rules_constant (legado SRD)' do
      Klass.where(api_index: 'fighter').update_all(rules: nil) if Klass.find_by(api_index: 'fighter')

      expect(KlassClassRulesProvider.call('fighter')).to be_nil
      expect(ClassRules.find('fighter')).to eq(ClassRules.find_from_rules_constant('fighter'))
    end

    it 'B2.2 — rules em klasses.tem prioridade (api_index nao precisa existir no Ruby)' do
      create(
        :klass,
        name: 'BDD',
        api_index: 'bdd_homebrew_class_only',
        hit_die: 8,
        rules: {
          'name' => 'Apenas DB',
          'primary_abilities' => %w[CHA DEX]
        }
      )
      r = ClassRules.find('bdd_homebrew_class_only')
      expect(r).to be_a(Hash)
      expect(r[:name]).to eq('Apenas DB')
      expect(r[:primary_abilities]).to eq(%w[CHA DEX])
    end
  end
end
