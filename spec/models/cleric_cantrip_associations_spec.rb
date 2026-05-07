require 'rails_helper'

# Regressao: o BonusCantripPicker / SpellPicker do clerigo refletia apenas as
# 7 cantrips PHB iniciais. Faltavam:
#
# XGtE (existiam no DB sem SpellSource para cleric):
#   - pt-mao-do-esplendor    (Word of Radiance / Mão do Esplendor)
#   - pt-pedagio-aos-mortos  (Toll the Dead / Pedágio aos Mortos)
#
# PHB ja estava completo (7 cantrips: Guidance, Light, Mending, Resistance,
# Sacred Flame, Spare the Dying, Thaumaturgy).
RSpec.describe 'Cleric cantrip associations (PHB + XGtE)', type: :model do
  let!(:cleric) do
    Klass.find_by(api_index: 'cleric') ||
      Klass.create!(api_index: 'cleric', name: 'Clérigo', hit_die: 8, subclass_level: 1)
  end

  # PHB cleric cantrips — 7 oficiais
  let(:phb_cantrips) do
    %w[guidance light mending resistance sacred-flame spare-the-dying thaumaturgy]
  end

  # XGtE cleric cantrips
  let(:xgte_cantrips) do
    %w[pt-mao-do-esplendor pt-pedagio-aos-mortos]
  end

  let(:all_expected) { phb_cantrips + xgte_cantrips }

  before do
    all_expected.each do |api_index|
      Spell.find_or_create_by!(api_index: api_index) do |s|
        s.name = api_index.titleize
        s.level = 0
        s.school = 'evocation'
      end
    end
  end

  def cantrip_api_indices_for(klass)
    Spell
      .joins('INNER JOIN spell_sources ON spell_sources.spell_id = spells.id')
      .where(level: 0, spell_sources: { source_type: 'Klass', source_id: klass.id })
      .pluck(:api_index)
      .sort
  end

  describe 'apos rodar a migration de associacoes' do
    before do
      load Rails.root.join('db/migrate/20260507070000_ensure_cleric_cantrip_sources.rb')
      EnsureClericCantripSources.new.up
    end

    it 'inclui as 7 cantrips canonicas do PHB' do
      indices = cantrip_api_indices_for(cleric)
      missing = phb_cantrips - indices
      expect(missing).to be_empty,
        "Cantrips PHB do clerigo sem SpellSource: #{missing.inspect}"
    end

    it 'inclui as 2 cantrips XGtE do clerigo (Word of Radiance, Toll the Dead)' do
      indices = cantrip_api_indices_for(cleric)
      missing = xgte_cantrips - indices
      expect(missing).to be_empty,
        "Cantrips XGtE do clerigo sem SpellSource: #{missing.inspect}"
    end

    it 'nao cria duplicatas em re-rodada (idempotente)' do
      EnsureClericCantripSources.new.up
      EnsureClericCantripSources.new.up

      counts = SpellSource
        .where(source_type: 'Klass', source_id: cleric.id, spell_id: Spell.where(api_index: all_expected).pluck(:id))
        .group(:spell_id)
        .count

      counts.values.each do |count|
        expect(count).to eq(1), "esperava 1 SpellSource por spell, encontrou #{count}"
      end
    end

    it 'totaliza pelo menos 9 cantrips associadas (7 PHB + 2 XGtE)' do
      indices = cantrip_api_indices_for(cleric)
      expect(indices.size).to be >= 9,
        "esperava >= 9 cantrips, recebeu #{indices.size}: #{indices.inspect}"
    end
  end
end
