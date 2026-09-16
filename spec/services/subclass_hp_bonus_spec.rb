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
    # ⚠️ `linhas_de_nivel` entrou no duplo porque o serviço passou a ler o BANCO
    # primeiro — sem isso o duplo verificador mente sobre a interface real da
    # `SubKlass`. Vazio significa "esta sub ainda não tem regra gravada", que é o
    # caso destes exemplos: eles medem a aritmética do delta contra o YAML.
    def klass_double(api, level = nil, linhas = [])
      sub = instance_double('SubKlass', api_index: api, name: api, linhas_de_nivel: linhas)
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

  # ⚠️ O BANCO manda. Este serviço lia SÓ o YAML: mexer no bônus de PV pela
  # página do compêndio não tinha efeito nenhum — a ficha seguia com o número do
  # livro, sem erro em lugar nenhum.
  describe 'precedência do `levels_json` sobre o YAML' do
    let(:klass) do
      Klass.find_by(api_index: 'cozinheiro') ||
        Klass.create!(name: 'Cozinheiro', api_index: 'cozinheiro', hit_die: 8)
    end

    it 'usa o que está GRAVADO, não o que o livro diz' do
      SubKlass.create!(
        name: 'Sargento Alimentar', api_index: 'sargento-alimentar', klass: klass,
        levels_json: [{ 'level' => 3,
                        'features' => [{ 'name' => 'Nunca Satisfeito',
                                         'rules' => { 'max_hp_bonus_immediate' => 10,
                                                      'max_hp_bonus_per_level' => 0 } }] }]
      )

      # O YAML daria 13 no nível 13 (3 + 1×10); o que o mestre gravou dá 10.
      expect(described_class.bonus_for('sargento-alimentar', 13)).to eq(10)
    end

    it 'e cai no YAML enquanto a sub-classe não tiver regra gravada' do
      SubKlass.create!(name: 'Sargento Alimentar', api_index: 'sargento-alimentar',
                       klass: klass, levels_json: [])

      expect(described_class.bonus_for('sargento-alimentar', 13)).to eq(13)
    end
  end
end
