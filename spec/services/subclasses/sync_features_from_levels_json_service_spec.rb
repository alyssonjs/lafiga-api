# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subclasses::SyncFeaturesFromLevelsJsonService, type: :service do
  let(:klass) { Klass.find_or_create_by!(api_index: 'ranger') { |k| k.name = 'Patrulheiro' } }

  def make_sub(api_index:, name:, levels_json:)
    sk = SubKlass.find_or_initialize_by(api_index: api_index, klass_id: klass.id)
    sk.name = name
    sk.levels_json = levels_json.to_json
    sk.save!
    SubKlassLevel.where(sub_klass_id: sk.id).destroy_all
    sk
  end

  let(:batedor_levels) do
    [
      {
        'level' => 3,
        'features' => [
          { 'name' => 'Tática de Batedor', 'description' => 'Trilhas seguras; alertas à distância.' },
          { 'name' => 'Escaramuça', 'description' => '+2d6 no primeiro ataque do turno.' },
        ],
      },
      {
        'level' => 7,
        'features' => [
          { 'name' => 'Movimento de Batedor', 'description' => '+3 m de deslocamento.' },
        ],
        'grants' => { 'movement' => { 'walk_bonus_ft' => 10 } },
      },
      {
        'level' => 11,
        'features' => [{ 'name' => 'Percepção Instintiva', 'description' => 'Vantagem em Percepção.' }],
      },
      {
        'level' => 15,
        'features' => [{ 'name' => 'Liberdade de Movimentos', 'description' => 'Imune.' }],
      },
    ]
  end

  describe '#call' do
    it 'cria SubKlassLevel + Feature para cada nivel/feature em levels_json (Batedor)' do
      sub = make_sub(api_index: 'batedor_test', name: 'Batedor', levels_json: batedor_levels)

      result = described_class.new(sub).call

      expect(result.status).to eq(:synced)
      expect(result.levels_synced).to eq(4)
      expect(result.features_synced).to eq(5)

      sub.reload
      expect(sub.sub_klass_levels.count).to eq(4)
      level_7 = sub.sub_klass_levels.includes(:features).find_by(level: 7)
      expect(level_7.features.map(&:name)).to include('Movimento de Batedor')
      level_3 = sub.sub_klass_levels.includes(:features).find_by(level: 3)
      expect(level_3.features.map(&:name)).to contain_exactly('Tática de Batedor', 'Escaramuça')
    end

    it 'eh idempotente — segunda chamada nao duplica features' do
      sub = make_sub(api_index: 'batedor_test_idem', name: 'Batedor', levels_json: batedor_levels)
      described_class.new(sub).call
      expect(sub.reload.sub_klass_levels.count).to eq(4)
      total_assocs_first = sub.sub_klass_levels.includes(:features).flat_map { |l| l.features.map(&:id) }.size

      described_class.new(sub).call

      expect(sub.reload.sub_klass_levels.count).to eq(4)
      total_assocs_second = sub.sub_klass_levels.includes(:features).flat_map { |l| l.features.map(&:id) }.size
      expect(total_assocs_second).to eq(total_assocs_first)
    end

    it 'gera api_index estavel e prefixado por subclasse para evitar colisoes' do
      sub_a = make_sub(
        api_index: 'sub_a', name: 'A',
        levels_json: [{ 'level' => 3, 'features' => [{ 'name' => 'Movimento Rápido' }] }],
      )
      sub_b = make_sub(
        api_index: 'sub_b', name: 'B',
        levels_json: [{ 'level' => 3, 'features' => [{ 'name' => 'Movimento Rápido' }] }],
      )

      described_class.new(sub_a).call
      described_class.new(sub_b).call

      f_a = sub_a.sub_klass_levels.includes(:features).find_by(level: 3).features.first
      f_b = sub_b.sub_klass_levels.includes(:features).find_by(level: 3).features.first
      expect(f_a.api_index).not_to eq(f_b.api_index)
      expect(f_a.api_index).to start_with('sub_a-')
      expect(f_b.api_index).to start_with('sub_b-')
    end

    it 'pula subclasses sem levels_json (defensivo)' do
      sub = SubKlass.create!(api_index: 'vazio', klass_id: klass.id, name: 'Vazia', levels_json: nil)
      result = described_class.new(sub).call
      expect(result.status).to eq(:skipped_empty)
    end

    it 'category de Feature criada eh subclass_feature' do
      sub = make_sub(api_index: 'sub_cat', name: 'Cat', levels_json: batedor_levels)
      described_class.new(sub).call
      f = sub.sub_klass_levels.includes(:features).flat_map { |l| l.features }.first
      expect(f.category).to eq('subclass_feature')
    end

    it 'atualiza description quando levels_json tem versao mais nova (force: true)' do
      sub = make_sub(
        api_index: 'sub_update', name: 'U',
        levels_json: [{ 'level' => 3, 'features' => [{ 'name' => 'X', 'description' => 'velha' }] }],
      )
      described_class.new(sub).call

      sub.update!(levels_json: [{ 'level' => 3, 'features' => [{ 'name' => 'X', 'description' => 'nova' }] }].to_json)
      described_class.new(sub, update_descriptions: true).call

      f = sub.sub_klass_levels.includes(:features).find_by(level: 3).features.first
      expect(f.description).to eq('nova')
    end
  end

  describe '.run_all' do
    it 'processa todas as subklasses com levels_json e devolve resumo por status' do
      make_sub(api_index: 'sub_run_a', name: 'A', levels_json: batedor_levels)
      make_sub(api_index: 'sub_run_b', name: 'B', levels_json: batedor_levels)

      results = described_class.run_all
      synced = results.count { |r| r.status == :synced }
      expect(synced).to be >= 2
    end
  end
end
