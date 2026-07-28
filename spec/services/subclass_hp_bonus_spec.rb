# frozen_string_literal: true

require 'rails_helper'

# BDD — Bug "PV do Sargento Alimentar não aplicado".
#
# O `subclass_overrides.yml` declara para Cozinheiro › Sargento Alimentar ›
# "Nunca Satisfeito" (Nv 3):
#   rules: { max_hp_bonus_immediate: 3, max_hp_bonus_per_level: 1 }
# mas NADA consumia essas chaves — o hp_max ficava sem o bônus (nem backend nem
# front, que só exibia um badge). Este serviço passa a somar o bônus ao hp_max
# via `SheetHpFromProgression.expected_max` e `LevelUpService`.
RSpec.describe SubclassHpBonus, type: :service do
  describe '.bonus_for (Sargento Alimentar "Nunca Satisfeito")' do
    it 'devolve o imediato (3) no nível de aquisição (Nv 3)' do
      expect(described_class.bonus_for('sargento-alimentar', 3)).to eq(3)
    end

    it 'soma imediato + per_level nos níveis seguintes (Nv 13 = 3 + 1×10)' do
      expect(described_class.bonus_for('sargento-alimentar', 13)).to eq(13)
      expect(described_class.bonus_for('sargento-alimentar', 20)).to eq(20)
    end

    it 'devolve 0 antes de adquirir a feature (Nv 2)' do
      expect(described_class.bonus_for('sargento-alimentar', 2)).to eq(0)
    end

    it 'devolve 0 para subclasse sem as chaves de PV (ex.: sous-chef)' do
      expect(described_class.bonus_for('sous-chef', 10)).to eq(0)
    end

    it 'devolve 0 para subclasse inexistente' do
      expect(described_class.bonus_for('nao-existe', 5)).to eq(0)
    end
  end

  describe '.step_bonus_for_klass (delta por level up)' do
    def klass_double(api, level = nil)
      sub = instance_double('SubKlass', api_index: api, name: api)
      instance_double('SheetKlass', sub_klass: sub, level: level)
    end

    it 'devolve o imediato (3) ao ATINGIR o nível de aquisição (3)' do
      expect(described_class.step_bonus_for_klass(klass_double('sargento-alimentar'), 3)).to eq(3)
    end

    it 'devolve o per_level (1) nos níveis seguintes' do
      expect(described_class.step_bonus_for_klass(klass_double('sargento-alimentar'), 4)).to eq(1)
      expect(described_class.step_bonus_for_klass(klass_double('sargento-alimentar'), 13)).to eq(1)
    end

    it 'devolve 0 antes do nível de aquisição' do
      expect(described_class.step_bonus_for_klass(klass_double('sargento-alimentar'), 2)).to eq(0)
    end

    it 'devolve 0 quando não há subclasse' do
      sk = instance_double('SheetKlass', sub_klass: nil, level: 5)
      expect(described_class.step_bonus_for_klass(sk, 5)).to eq(0)
    end
  end
end
