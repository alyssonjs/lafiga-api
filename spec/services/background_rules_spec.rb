# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BackgroundRules do
  after { BackgroundRules.clear_cache! }
  describe '.find' do
    it 'resolves string slugs to RULES entries (symbol keys in RULES hash)' do
      bg = described_class.find('acolyte')
      expect(bg).to be_a(Hash)
      expect(bg[:id]).to eq('acolyte')
      expect(bg[:equipment]).to be_an(Array)
      expect(bg[:equipment].first).to include('símbolo')
    end

    it 'resolves symbol keys' do
      bg = described_class.find(:acolyte)
      expect(bg[:name]).to eq('Acólito')
    end
  end

  describe '.apply' do
    it 'returns equipment list for acolyte' do
      summary = described_class.apply(key: 'acolyte', choices: { languages: %w[Goblin Halfling] })
      expect(summary[:equipment].size).to be >= 5
      expect(summary[:equipment]).to include(a_string_matching(/símbolo/i))
    end

    it 'resolves outlander instrument from choices[:tools] queue' do
      summary = described_class.apply(
        key: 'outlander',
        choices: { tools: ['Flauta'] }
      )
      expect(summary[:tools]).to include('Flauta')
    end

    it 'resolves noble gaming set from choices[:tools] queue' do
      summary = described_class.apply(
        key: 'noble',
        choices: { tools: ['Baralho de cartas'] }
      )
      expect(summary[:tools].first).to eq('Jogo de Baralho de cartas')
    end

    it 'resolves guild artisan tool from choices[:tools] queue and language' do
      summary = described_class.apply(
        key: 'guild-artisan',
        choices: { tools: ['Ferramentas de Ferreiro'], languages: ['Élfico'] }
      )
      expect(summary[:tools]).to include('Ferramentas de Ferreiro')
      expect(summary[:languages]).to eq(['Élfico'])
    end

    it 'resolves folk hero artisan tool and land vehicle proficiency' do
      summary = described_class.apply(
        key: 'folk-hero',
        choices: { tools: ['Ferramentas de Carpinteiro'] }
      )
      expect(summary[:tools]).to include('Ferramentas de Carpinteiro')
      expect(summary[:tools]).to include('Veículos Terrestres')
    end
  end

  describe 'PHB catalog completeness' do
    it 'includes all 13 PHB backgrounds (YAML slugs)' do
      expect(described_class.all.keys.map(&:to_s)).to include(
        'acolyte', 'charlatan', 'criminal', 'entertainer', 'folk-hero',
        'guild-artisan', 'hermit', 'noble', 'outlander', 'sage', 'sailor',
        'soldier', 'urchin'
      )
    end
  end

  describe 'variants (DB overlay)' do
    it 'merges variant rules onto parent and sets lineage keys' do
      parent = Background.create!(
        api_index: 'bg_variant_parent_spec',
        name: 'Pai Spec',
        published: true,
        rules: {
          'id' => 'bg_variant_parent_spec',
          'name' => 'Pai Spec',
          'skills' => ['Atletismo'],
          'tools' => [],
          'languages' => { 'choose' => 0 },
          'equipment' => %w[ItemBase],
          'feature' => { 'name' => 'FEAT', 'desc' => 'base' }
        }
      )
      Background.create!(
        api_index: 'bg_variant_child_spec',
        name: 'Filho Spec',
        parent_api_index: parent.api_index,
        published: true,
        rules: {
          'feature' => { 'name' => 'FEAT', 'desc' => 'sobreposto' }
        }
      )
      described_class.clear_cache!
      row = described_class.find('bg_variant_child_spec')
      expect(row[:skills]).to eq(['Atletismo'])
      expect(row[:equipment]).to eq(%w[ItemBase])
      expect(row[:feature][:desc]).to eq('sobreposto')
      expect(row[:parent_background_index]).to eq(parent.api_index)
      expect(row[:parent_background_name]).to eq('Pai Spec')
      expect(row[:is_variant]).to be true
      parent.destroy!
      Background.find_by(api_index: 'bg_variant_child_spec')&.destroy!
    end

    it 'resolves variant-of-variant after enough passes (child before parent in id order)' do
      gp = Background.create!(
        api_index: 'bg_v_gp',
        name: 'Avô',
        published: true,
        rules: {
          'id' => 'bg_v_gp',
          'name' => 'Avô',
          'skills' => ['Acrobacia'],
          'tools' => [],
          'languages' => { 'choose' => 0 },
          'equipment' => %w[A],
          'feature' => { 'name' => 'F', 'desc' => 'g' }
        }
      )
      # Filho criado primeiro → id menor que do neto
      mid = Background.create!(
        api_index: 'bg_v_mid',
        name: 'Meio',
        parent_api_index: gp.api_index,
        published: true,
        rules: {}
      )
      leaf = Background.create!(
        api_index: 'bg_v_leaf',
        name: 'Folha',
        parent_api_index: mid.api_index,
        published: true,
        rules: {
          'feature' => { 'name' => 'Folha', 'desc' => 'só na folha' }
        }
      )
      expect(leaf.id).to be > mid.id

      described_class.clear_cache!
      row = described_class.find('bg_v_leaf')
      expect(row[:skills]).to eq(['Acrobacia'])
      expect(row[:equipment]).to eq(%w[A])
      expect(row[:feature][:name]).to eq('Folha')
      expect(row[:parent_background_index]).to eq(mid.api_index)
      expect(row[:parent_background_name]).to eq('Meio')

      [leaf, mid, gp].each(&:destroy!)
    end
  end

  describe 'database overlay' do
    it 'prefers published Background.rules over FALLBACK for same api_index' do
      bg = Background.create!(
        api_index: 'bg_rules_overlay_spec',
        name: 'Overlay Test',
        published: true,
        rules: {
          'id' => 'bg_rules_overlay_spec',
          'name' => 'Overlay Test',
          'skills' => ['Sobrevivência'],
          'tools' => [],
          'languages' => { 'choose' => 0 },
          'equipment' => [],
          'feature' => { 'name' => 'TEST', 'desc' => 'x' }
        }
      )
      described_class.clear_cache!
      row = described_class.find('bg_rules_overlay_spec')
      expect(row[:skills]).to eq(['Sobrevivência'])
      bg.destroy!
    end
  end
end
