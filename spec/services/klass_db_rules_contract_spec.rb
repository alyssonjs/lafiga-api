# frozen_string_literal: true

require 'rails_helper'

# BDD — Loop 2: contrato mínimo `klasses.rules` + paridade com ClassRules::CLASS_RULES
RSpec.describe KlassDbRulesContract, type: :model do
  describe 'B3 — Contrato' do
    it 'B3.1 — rejeita hash vazio' do
      expect(described_class.missing_required({})).to include(:id, :name, :hit_die)
      expect { described_class.validate!({}) }.to raise_error(ArgumentError, /faltam chaves/)
    end

    it 'B3.2 — aceita só o mínimo (homebrew mínima)' do
      h = { id: 'bdd_min', name: 'BDD Mín', hit_die: 'd8' }
      expect { described_class.validate!(h) }.not_to raise_error
    end

    it 'B3.3 — aceita regra SRD bruta (fighter) de ClassRules::CLASS_RULES' do
      rule = ClassRules::CLASS_RULES[:fighter]
      expect(rule).to be_a(Hash)
      expect { described_class.validate!(rule) }.not_to raise_error
    end

    it 'B3.4 — validate_loose sinaliza vazio para recomendáveis com hash mínimo' do
      h = { id: 'a', name: 'A', hit_die: 'd6' }
      lo = described_class.validate_loose(h)
      expect(lo[:missing_required]).to be_empty
      expect(lo[:missing_recommended].length).to be > 0
    end
  end

  describe 'B4 — Roundtrip mínimo (DB JSON → provider → hash)' do
    it 'B4.1 — JSON mínimo válido persiste e lê com mesmas chaves de topo' do
      h = { 'id' => 'bdd_rt', 'name' => 'Roundtrip', 'hit_die' => 'd8', 'primary_abilities' => %w[STR] }
      described_class.validate!(h)
      k = create(:klass, api_index: 'bdd_rt', rules: h)
      k.reload
      out = KlassClassRulesProvider.call('bdd_rt')
      expect(out[:id]).to eq('bdd_rt')
      expect(out[:name]).to eq('Roundtrip')
      expect(out[:hit_die]).to eq('d8')
      expect(out[:primary_abilities]).to eq(%w[STR])
    end
  end
end
