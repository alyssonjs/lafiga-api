# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/spell_combat_data_importer.rb').to_s

RSpec.describe SpellCombatDataImporter do
  describe '.merged (função pura)' do
    it 'M1 — mescla raso: override sobre seed por api_index' do
      seed = { 'fireball' => { 'damage' => { 'dice' => '8d6' }, 'range_ft' => 150 } }
      ovr  = { 'fireball' => { 'range_ft' => 999 } }
      out = described_class.merged(seed, ovr)
      expect(out['fireball']).to eq('damage' => { 'dice' => '8d6' }, 'range_ft' => 999)
    end

    it 'M2 — poda chaves nil do override (permite "apagar" campo do seed)' do
      seed = { 'sleep' => { 'resolution' => 'none', 'removes_conditions' => %w[charmed] } }
      ovr  = { 'sleep' => { 'resolution' => 'auto', 'removes_conditions' => nil } }
      out = described_class.merged(seed, ovr)
      expect(out['sleep']).to eq('resolution' => 'auto')
    end

    it 'M3 — entradas só no override (curadoria de magia fora do seed) entram' do
      out = described_class.merged({}, { 'homebrew' => { 'range_ft' => 30 } })
      expect(out['homebrew']).to eq('range_ft' => 30)
    end

    it 'M4 — entrada que fica vazia após poda é descartada' do
      out = described_class.merged({ 'x' => { 'a' => 1 } }, { 'x' => { 'a' => nil } })
      expect(out).not_to have_key('x')
    end
  end

  describe '.import! (integração com o seed real)' do
    it 'I1 — grava combat_data mecânico da Bola de Fogo (dano + upcast + área)' do
      spell = create(:spell, api_index: 'fireball')
      described_class.import!
      cd = spell.reload.combat_data
      expect(cd.dig('damage', 'dice')).to eq('8d6')
      expect(cd.dig('damage', 'types')).to eq(['fire'])
      expect(cd.dig('damage', 'upcast', '4')).to eq('9d6')
      expect(cd.dig('area', 'shape')).to eq('sphere')
      expect(cd['save_ability']).to eq('dex')
    end

    it 'I2 — cantrip: deriva o base e a escala por nível (sacred-flame 2d8→base 1d8)' do
      spell = create(:spell, api_index: 'sacred-flame')
      described_class.import!
      cd = spell.reload.combat_data
      expect(cd.dig('damage', 'dice')).to eq('1d8')
      expect(cd.dig('damage', 'cantrip_scaling')).to include('5' => '2d8', '11' => '3d8', '17' => '4d8')
    end

    it 'I3 — condição infligida com TR + duração em rounds (Imobilizar Pessoa)' do
      spell = create(:spell, api_index: 'hold-person')
      described_class.import!
      cd = spell.reload.combat_data
      expect(cd['inflicts_conditions']).to include(hash_including('key' => 'paralyzed', 'save' => 'wis'))
      expect(cd.dig('duration', 'rounds')).to eq(10)
      expect(cd['concentration']).to be(true)
    end

    it 'I4 — override aplica sobre seed (Sono vira auto + inconsciente, sem "remove")' do
      spell = create(:spell, api_index: 'sleep')
      described_class.import!
      cd = spell.reload.combat_data
      expect(cd['resolution']).to eq('auto')
      expect(cd['inflicts_conditions']).to eq([{ 'key' => 'unconscious', 'polarity' => 'debuff', 'save' => nil, 'repeat_save' => false }])
      expect(cd).not_to have_key('removes_conditions')
    end

    it 'I5 — magia sem entrada fica com combat_data {} (não inventa)' do
      spell = create(:spell, api_index: 'cook-snack-corte-fresco')
      described_class.import!
      expect(spell.reload.combat_data).to eq({})
    end

    it 'I6 — idempotente: 2ª rodada não altera nada' do
      create(:spell, api_index: 'fireball')
      described_class.import!
      res = described_class.import!
      expect(res[:updated]).to eq(0)
    end

    it 'I7 — DRY_RUN não escreve' do
      spell = create(:spell, api_index: 'fireball')
      described_class.import!(dry_run: true)
      expect(spell.reload.combat_data).to eq({})
    end
  end

  describe 'payload público expõe combat_data' do
    it 'P1 — spell.as_json inclui a coluna combat_data' do
      spell = create(:spell, api_index: 'fireball')
      described_class.import!
      expect(spell.reload.as_json).to have_key('combat_data')
      expect(spell.as_json['combat_data']).to be_present
    end
  end
end
