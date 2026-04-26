# frozen_string_literal: true

require 'rails_helper'

# Módulo: `DndImportHelpers` em `app/services/dnd_import_helpers.rb` (Rake: `dnd:apply_subclass_overrides`).

# BDD — small loops: contrato YAML + `apply_subclass_overrides!` + `apply_subclass_grants!` +
# `Subclasses::SyncFeaturesFromLevelsJsonService` (SubKlassLevel + Feature para a ficha).
# Próximo: request público a subclasse / níveis.
RSpec.describe 'DndImportHelpers — Guerreiro (subclass_overrides)', type: :model do
  let(:expected_fighter_sub_keys) do
    %w[
      campeao mestre-de-batalha cavaleiro-arcano
      atirador_inigualavel cavaleiro_implacavel defensor_dedicado
      kensai mestre_correntes mestre_arremesso
    ]
  end

  let!(:fighter_klass) do
    Klass.find_or_create_by!(api_index: 'fighter') do |k|
      k.name = 'Guerreiro'
      k.hit_die = 10
      k.subclass_level = 3
    end
  end

  def apply_fighter_subclass_pipeline!
    DndImportHelpers.apply_subclass_overrides!(fighter_klass)
    DndImportHelpers.apply_subclass_grants!(fighter_klass)
  end

  describe 'A1 — Contrato do YAML' do
    it 'A1.1 — merged_overrides.fighter contém as chaves canónicas de subclass (PHB + novos arquétipos)' do
      f = DndImportHelpers.merged_overrides['fighter'] || {}
      expect(f.keys.map(&:to_s)).to include(*expected_fighter_sub_keys)
    end

    it 'A1.2 — chaves fora de subclass (se existirem) não contam como arquétipo' do
      f = DndImportHelpers.merged_overrides['fighter'] || {}
      # Se no futuro existir chave irmã, filtrar blocos conhecidos
      sub_like = f.reject { |k, v| v.is_a?(Hash) == false }
      sub_like = sub_like.reject { |k, _v| k.to_s == 'rules' } # padrão outras classes
      expect(sub_like.keys.map(&:to_s)).to include(*expected_fighter_sub_keys)
    end
  end

  describe 'A2 — Aplicação em base de dados' do
    it 'A2.1 — apply_subclass_overrides! cria sub_klass com api_index de cada chave do YAML' do
      DndImportHelpers.apply_subclass_overrides!(fighter_klass)
      fighter_klass.sub_klasses.reload
      got = fighter_klass.sub_klasses.pluck(:api_index)
      expect(got).to include(*expected_fighter_sub_keys)
    end

    it 'A2.2 — levels_json preenchido (Campeão) para o compendium / API de níveis' do
      DndImportHelpers.apply_subclass_overrides!(fighter_klass)
      sub = fighter_klass.sub_klasses.find_by!(api_index: 'campeao')
      expect(sub.levels_json).to be_present
      arr = JSON.parse(sub.levels_json)
      expect(arr).to be_a(Array)
      expect(arr.map { |r| r['level'] }).to include(3, 7, 10, 15, 18)
    end
  end

  describe 'A3 — apply_subclass_grants! (regras de topo → level 0, merge em levels_json)' do
    it 'A3.1 — Mestre de Batalha: insere bloco level 0 com rules.superiority_dice (YAML de topo)' do
      apply_fighter_subclass_pipeline!
      sub = fighter_klass.sub_klasses.find_by!(api_index: 'mestre-de-batalha')
      rows = JSON.parse(sub.levels_json)
      z = rows.find { |h| h['level'] == 0 }
      expect(z).to be_present, 'esperado level 0 após merge de `rules` de topo do YAML'
      expect(z['rules']['superiority_dice']['die_start']).to eq('d8')
    end

    it 'A3.2 — Cavaleiro Arcano: level 0 com rules de topo (spellcasting/bonded_weapon/war_magic) do YAML' do
      apply_fighter_subclass_pipeline!
      sub = fighter_klass.sub_klasses.find_by!(api_index: 'cavaleiro-arcano')
      rows = JSON.parse(sub.levels_json)
      z = rows.find { |h| h['level'] == 0 }
      expect(z).to be_present
      expect(z['rules']['spellcasting']['ability']).to eq('Inteligência')
      expect(z['rules']['bonded_weapon']).to be_a(Hash)
      expect(z['rules']['war_magic']['base']).to include('truque')
    end

    it 'A3.3 — Campeão: sem `rules` de nível 0 (YAML sem bloco `rules` no arquétipo)' do
      apply_fighter_subclass_pipeline!
      sub = fighter_klass.sub_klasses.find_by!(api_index: 'campeao')
      levels = JSON.parse(sub.levels_json).map { |h| h['level'] }
      expect(levels).not_to include(0)
    end
  end

  # `SyncFeaturesFromLevelsJsonService` lê `levels_json` (níveis > 0) e povoia sub_klass_levels + features.
  describe 'A4 — Subclasses::SyncFeaturesFromLevelsJsonService' do
    it 'A4.1 — após o pipeline, sync cria 5 SubKlassLevel e 5 Features (Campeão, 1 feature/nível)' do
      apply_fighter_subclass_pipeline!
      sub = fighter_klass.sub_klasses.find_by!(api_index: 'campeao')

      result = Subclasses::SyncFeaturesFromLevelsJsonService.new(sub).call

      expect(result.status).to eq(:synced)
      expect(result.levels_synced).to eq(5)
      expect(result.features_synced).to eq(5)
      sub.reload
      expect(sub.sub_klass_levels.pluck(:level).sort).to eq([3, 7, 10, 15, 18])
      names = sub.sub_klass_levels.includes(:features).flat_map { |l| l.features.map(&:name) }
      expect(names).to match_array(
        [
          'Crítico Aprimorado',
          'Atleta Extraordinário',
          'Estilo de Luta Adicional',
          'Crítico Superior',
          'Sobrevivente',
        ],
      )
    end

    it 'A4.2 — Feature.api_index prefixado (evita colisão com outra subclasse com mesmo nome de feature)' do
      apply_fighter_subclass_pipeline!
      sub = fighter_klass.sub_klasses.find_by!(api_index: 'campeao')
      Subclasses::SyncFeaturesFromLevelsJsonService.new(sub).call

      f = sub.sub_klass_levels.includes(:features).find_by!(level: 3).features.first
      expect(f.api_index).to start_with('campeao-')
    end

    it 'A4.3 — linha `level: 0` (metadados de rules) não gera SubKlassLevel' do
      apply_fighter_subclass_pipeline!
      sub = fighter_klass.sub_klasses.find_by!(api_index: 'mestre-de-batalha')
      expect(JSON.parse(sub.levels_json).map { |h| h['level'] }).to include(0)

      Subclasses::SyncFeaturesFromLevelsJsonService.new(sub).call

      expect(sub.sub_klass_levels.pluck(:level)).not_to include(0)
    end
  end
end
