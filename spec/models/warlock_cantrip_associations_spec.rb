require 'rails_helper'

# Regressao: o picker do bruxo refletia 7 cantrips. Faltavam:
#
# PHB:
#   - blade-ward (Proteção Contra Lâminas)
#   - friends    (Amizade)
#
# XGtE:
#   - pt-atracao-chocante       (Lightning Lure)
#   - pt-criar-fogueira         (Create Bonfire)
#   - pt-infestacao             (Infestation)
#   - pt-lamina-da-chama-esverdeada (Green-Flame Blade)
#   - pt-lamina-estrondosa      (Booming Blade)
#   - pt-pedagio-aos-mortos     (Toll the Dead)
#   - pt-picada-congelante      (Frostbite)
#   - pt-rompante-de-espadas    (Sword Burst)
#   - pt-trovoada               (Thunderclap)
RSpec.describe 'Warlock cantrip associations (PHB + XGtE)', type: :model do
  let!(:warlock) do
    Klass.find_by(api_index: 'warlock') ||
      Klass.create!(api_index: 'warlock', name: 'Bruxo', hit_die: 8, subclass_level: 1)
  end

  # PHB warlock cantrips — 9 oficiais (Chill Touch, Eldritch Blast, Friends,
  # Mage Hand, Minor Illusion, Poison Spray, Prestidigitation, True Strike,
  # Blade Ward).
  let(:phb_cantrips) do
    %w[
      blade-ward chill-touch eldritch-blast friends mage-hand minor-illusion
      poison-spray prestidigitation true-strike
    ]
  end

  # XGtE warlock cantrips
  let(:xgte_cantrips) do
    %w[
      pt-atracao-chocante
      pt-criar-fogueira
      pt-infestacao
      pt-lamina-da-chama-esverdeada
      pt-lamina-estrondosa
      pt-pedagio-aos-mortos
      pt-picada-congelante
      pt-rompante-de-espadas
      pt-trovoada
    ]
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
      load Rails.root.join('db/migrate/20260507100000_ensure_warlock_cantrip_sources.rb')
      EnsureWarlockCantripSources.new.up
    end

    it 'inclui as 9 cantrips canonicas do PHB' do
      indices = cantrip_api_indices_for(warlock)
      missing = phb_cantrips - indices
      expect(missing).to be_empty,
        "Cantrips PHB do bruxo sem SpellSource: #{missing.inspect}"
    end

    it 'inclui as 9 cantrips XGtE do bruxo' do
      indices = cantrip_api_indices_for(warlock)
      missing = xgte_cantrips - indices
      expect(missing).to be_empty,
        "Cantrips XGtE do bruxo sem SpellSource: #{missing.inspect}"
    end

    it 'nao cria duplicatas em re-rodada (idempotente)' do
      EnsureWarlockCantripSources.new.up
      EnsureWarlockCantripSources.new.up

      counts = SpellSource
        .where(source_type: 'Klass', source_id: warlock.id, spell_id: Spell.where(api_index: all_expected).pluck(:id))
        .group(:spell_id)
        .count

      counts.values.each do |count|
        expect(count).to eq(1), "esperava 1 SpellSource por spell, encontrou #{count}"
      end
    end

    it 'totaliza pelo menos 18 cantrips associadas (9 PHB + 9 XGtE)' do
      indices = cantrip_api_indices_for(warlock)
      expect(indices.size).to be >= 18,
        "esperava >= 18 cantrips, recebeu #{indices.size}: #{indices.inspect}"
    end
  end
end
