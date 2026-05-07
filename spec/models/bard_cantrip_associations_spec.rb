require 'rails_helper'

# Regressao: o BonusCantripPicker / SpellPicker do bardo refletia apenas 8
# cantrips. Faltavam:
#
# PHB (existiam no DB sem SpellSource para bard):
#   - blade-ward             (Proteção Contra Lâminas)
#   - friends                (Amizade)
#   - pt-zombaria-viciosa    (Zombaria Viciosa / Vicious Mockery)
#
# XGtE (idem):
#   - pt-trovoada            (Trovoada / Thunderclap)
RSpec.describe 'Bard cantrip associations (PHB + XGtE)', type: :model do
  let!(:bard) do
    Klass.find_by(api_index: 'bard') ||
      Klass.create!(api_index: 'bard', name: 'Bardo', hit_die: 8, subclass_level: 3)
  end

  # PHB bard cantrips — 11 oficiais (Dancing Lights, Friends, Light, Mage Hand,
  # Mending, Message, Minor Illusion, Prestidigitation, True Strike, Vicious
  # Mockery, Blade Ward).
  let(:phb_cantrips) do
    %w[
      dancing-lights friends light mage-hand mending message minor-illusion
      prestidigitation true-strike pt-zombaria-viciosa blade-ward
    ]
  end

  # XGtE bard cantrips
  let(:xgte_cantrips) do
    %w[pt-trovoada]
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
      load Rails.root.join('db/migrate/20260507080000_ensure_bard_cantrip_sources.rb')
      EnsureBardCantripSources.new.up
    end

    it 'inclui as 11 cantrips canonicas do PHB' do
      indices = cantrip_api_indices_for(bard)
      missing = phb_cantrips - indices
      expect(missing).to be_empty,
        "Cantrips PHB do bardo sem SpellSource: #{missing.inspect}"
    end

    it 'inclui Trovoada (XGtE) na lista do bardo' do
      indices = cantrip_api_indices_for(bard)
      missing = xgte_cantrips - indices
      expect(missing).to be_empty,
        "Cantrips XGtE do bardo sem SpellSource: #{missing.inspect}"
    end

    it 'nao cria duplicatas em re-rodada (idempotente)' do
      EnsureBardCantripSources.new.up
      EnsureBardCantripSources.new.up

      counts = SpellSource
        .where(source_type: 'Klass', source_id: bard.id, spell_id: Spell.where(api_index: all_expected).pluck(:id))
        .group(:spell_id)
        .count

      counts.values.each do |count|
        expect(count).to eq(1), "esperava 1 SpellSource por spell, encontrou #{count}"
      end
    end

    it 'totaliza pelo menos 12 cantrips associadas (11 PHB + 1 XGtE)' do
      indices = cantrip_api_indices_for(bard)
      expect(indices.size).to be >= 12,
        "esperava >= 12 cantrips, recebeu #{indices.size}: #{indices.inspect}"
    end
  end
end
