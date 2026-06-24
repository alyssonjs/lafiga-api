# frozen_string_literal: true

require 'rails_helper'

# R7 — dedup / ocultação de placeholders na lista `features` da ficha.
RSpec.describe FeaturesAggregator do
  # Helpers de montagem direta (HABTM Feature <-> *_levels) ─────────────
  def feature!(name:, api_index: nil)
    create(:feature, name: name, api_index: api_index || "spec_feat_#{SecureRandom.hex(4)}")
  end

  def class_level_with!(klass:, level:, features:)
    cl = ClassLevel.create!(klass: klass, level: level, prof_bonus: 2, ability_score_bonuses: 0)
    cl.features = features
    cl
  end

  def sub_level_with!(sub_klass:, level:, features:)
    sl = SubKlassLevel.create!(sub_klass: sub_klass, level: level)
    sl.features = features
    sl
  end

  let(:klass) do
    Klass.find_or_create_by!(api_index: "spec_klass_#{SecureRandom.hex(3)}") do |k|
      k.name = 'Classe Spec'
      k.hit_die = 8
      k.subclass_level = 1
    end
  end

  let(:sub_klass) do
    create(:sub_klass, klass: klass, name: 'Sub Spec', levels_json: levels_json)
  end

  let(:levels_json) { '{}' }

  def build_sheet(level:)
    sheet = create(:sheet)
    create(:sheet_klass, sheet: sheet, klass: klass, sub_klass: sub_klass, level: level)
    sheet.reload
  end

  def names_visible(result)
    result.select { |i| i[:show] != false }.map { |i| [i[:level], i[:name]] }
  end

  describe '#call — dedup por (nível, nome normalizado)' do
    it 'mantém uma só feature quando há duas com mesmo nível e nome normalizado igual' do
      f1 = feature!(name: 'Fúria Espiritual')
      f2 = feature!(name: 'fúria  espiritual') # mesma, caixa/espacos diferentes
      sub_level_with!(sub_klass: sub_klass, level: 3, features: [f1, f2])
      sheet = build_sheet(level: 3)

      result = described_class.new(sheet, sync: false).call
      visible = result.select do |i|
        i[:show] != false && i[:level] == 3 &&
          i[:name].to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '').downcase.gsub(/\s+/, ' ').include?('furia espiritual')
      end
      expect(visible.size).to eq(1)
    end

    it 'NÃO deduplica features de mesmo nome em NÍVEIS diferentes (ASI repete por nível)' do
      asi4 = feature!(name: 'Aumento de Valor de Atributo')
      asi6 = feature!(name: 'Aumento de Valor de Atributo')
      class_level_with!(klass: klass, level: 4, features: [asi4])
      class_level_with!(klass: klass, level: 6, features: [asi6])
      sheet = build_sheet(level: 6)

      result = described_class.new(sheet, sync: false).call
      asi_levels = result.select { |i| i[:show] != false && i[:name] == 'Aumento de Valor de Atributo' }
                         .map { |i| i[:level] }.sort
      expect(asi_levels).to eq([4, 6])
    end
  end

  describe '#call — ocultar placeholders genéricos' do
    it 'oculta placeholder de classe quando há feature REAL de subclasse no mesmo nível' do
      placeholder = feature!(name: 'Recurso de patrono de outro mundo', api_index: 'otherworldly-patron-improvement-1')
      class_level_with!(klass: klass, level: 6, features: [placeholder])
      real = feature!(name: 'Sorte do Próprio Obscuro')
      sub_level_with!(sub_klass: sub_klass, level: 6, features: [real])
      sheet = build_sheet(level: 6)

      result = described_class.new(sheet, sync: false).call
      ph = result.find { |i| i[:name] == 'Recurso de patrono de outro mundo' }
      rl = result.find { |i| i[:name] == 'Sorte do Próprio Obscuro' }
      expect(ph[:show]).to eq(false)
      expect(rl[:show]).not_to eq(false)
    end

    it 'oculta o slot-chooser (Patrono de Outro Mundo) quando subclasse preenche o nível' do
      chooser = feature!(name: 'Patrono de Outro Mundo', api_index: 'otherworldly-patron')
      class_level_with!(klass: klass, level: 1, features: [chooser])
      real = feature!(name: 'Bênção do Obscuro')
      sub_level_with!(sub_klass: sub_klass, level: 1, features: [real])
      sheet = build_sheet(level: 1)

      result = described_class.new(sheet, sync: false).call
      expect(result.find { |i| i[:name] == 'Patrono de Outro Mundo' }[:show]).to eq(false)
      expect(result.find { |i| i[:name] == 'Bênção do Obscuro' }[:show]).not_to eq(false)
    end

    it 'NÃO oculta placeholder quando o nível não tem feature real de subclasse' do
      placeholder = feature!(name: 'Recurso de caminho', api_index: 'primal-path-improvement-1')
      class_level_with!(klass: klass, level: 6, features: [placeholder])
      sheet = build_sheet(level: 6)

      result = described_class.new(sheet, sync: false).call
      ph = result.find { |i| i[:name] == 'Recurso de caminho' }
      expect(ph[:show]).not_to eq(false)
    end
  end

  describe '#call — pares legado×canônico (mesmo nível, mesma SubKlass)' do
    let(:levels_json) do
      JSON.dump([
        { 'level' => 1, 'features' => [{ 'name' => 'Bênção do Obscuro' }] },
        { 'level' => 6, 'features' => [{ 'name' => 'Sorte do Próprio Obscuro' }] }
      ])
    end

    it 'oculta a legada (id menor, fora do levels_json) e mantém a canônica (1:1)' do
      # IMPORTANT: legacy precisa ter id MENOR que a canônica.
      legacy = feature!(name: 'Bênção do Diabo')          # criada antes => id menor
      canon  = feature!(name: 'Bênção do Obscuro')        # casa com levels_json
      sub_level_with!(sub_klass: sub_klass, level: 1, features: [legacy, canon])
      sheet = build_sheet(level: 1)

      result = described_class.new(sheet, sync: false).call
      expect(result.find { |i| i[:name] == 'Bênção do Diabo' }[:show]).to eq(false)
      expect(result.find { |i| i[:name] == 'Bênção do Obscuro' }[:show]).not_to eq(false)
    end

    it 'oculta a legada por overlap de palavra de conteúdo (nível multi-slot)' do
      # 3 legadas vs 2 canônicas => contagem NÃO é 1:1; só oculta por overlap.
      multi_sub = create(:sub_klass, klass: klass, name: 'Multi Spec', levels_json: JSON.dump([
        { 'level' => 3, 'features' => [{ 'name' => 'Inspiração em Combate' }, { 'name' => 'Proficiência Adicional' }] }
      ]))
      legacy_a = feature!(name: 'Inspiração de Combate')
      legacy_b = feature!(name: 'Sopro Aleatório Antigo')
      legacy_c = feature!(name: 'Outra Coisa Velha')
      canon_a  = feature!(name: 'Inspiração em Combate')
      canon_b  = feature!(name: 'Proficiência Adicional')
      SubKlassLevel.create!(sub_klass: multi_sub, level: 3).features = [legacy_a, legacy_b, legacy_c, canon_a, canon_b]
      sheet = create(:sheet)
      create(:sheet_klass, sheet: sheet, klass: klass, sub_klass: multi_sub, level: 3)
      sheet.reload

      result = described_class.new(sheet, sync: false).call
      # legacy_a compartilha "inspiração"/"combate" com canon_a → oculta
      expect(result.find { |i| i[:name] == 'Inspiração de Combate' }[:show]).to eq(false)
      # legacy_b não compartilha palavra com nenhuma canônica e contagem não é 1:1 → fica visível (D1/D2)
      expect(result.find { |i| i[:name] == 'Sopro Aleatório Antigo' }[:show]).not_to eq(false)
      expect(result.find { |i| i[:name] == 'Inspiração em Combate' }[:show]).not_to eq(false)
    end

    it 'NÃO oculta feature legítima nova (id maior) que não casa com levels_json' do
      canon = feature!(name: 'Bênção do Obscuro')  # menor id, canônica
      newer = feature!(name: 'Magia de Pacto Spec') # maior id, legítima ausente do levels_json
      sub_level_with!(sub_klass: sub_klass, level: 1, features: [canon, newer])
      sheet = build_sheet(level: 1)

      result = described_class.new(sheet, sync: false).call
      expect(result.find { |i| i[:name] == 'Magia de Pacto Spec' }[:show]).not_to eq(false)
    end
  end
end
