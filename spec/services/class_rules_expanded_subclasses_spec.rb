# frozen_string_literal: true

require 'rails_helper'

# BDD — sub-opções alinhadas a config/subclass_overrides.yml (compendium / wizard).
RSpec.describe 'ClassRules — subclasses expandidas no catálogo', type: :model do
  describe 'B7 — Feiticeiro' do
    it 'B7.1 — sete origens (SRD 2 + extras do YAML) em subclass.options' do
      opts = ClassRules::CLASS_RULES[:sorcerer][:subclass][:options]
      expect(opts.keys).to include(
        'draconic',
        'wild',
        'feiticaria-da-espada',
        'feiticaria-do-sangue',
        'linhagem-elemental',
        'origem-aberrante',
        'origem-abissal',
        'origem-mutavel'
      )
    end
  end

  describe 'B8 — Bruxo' do
    it 'B8.1 — SRD 3 + patrono-* extras do YAML' do
      keys = ClassRules::CLASS_RULES[:warlock][:subclass][:options].keys
      expect(keys).to include('fiend', 'archfey', 'great_old_one', 'patrono-morte', 'patrono-vazio')
    end
  end
end
