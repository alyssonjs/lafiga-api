require 'rails_helper'

# Regressao: o picker do feiticeiro refletia 14 cantrips. Faltavam:
#
# PHB:
#   - blade-ward (Proteção Contra Lâminas)
#   - friends    (Amizade)
#
# XGtE:
#   - pt-atracao-chocante       (Lightning Lure)
#   - pt-controlar-chamas       (Control Flames)
#   - pt-criar-fogueira         (Create Bonfire)
#   - pt-infestacao             (Infestation)
#   - pt-lamina-da-chama-esverdeada (Green-Flame Blade)
#   - pt-lamina-estrondosa      (Booming Blade)
#   - pt-lufada                 (Gust)
#   - pt-moldar-agua            (Shape Water)
#   - pt-moldar-terra           (Mold Earth)
#   - pt-picada-congelante      (Frostbite)
#   - pt-rompante-de-espadas    (Sword Burst)
#   - pt-trovoada               (Thunderclap)
RSpec.describe 'Sorcerer cantrip associations (PHB + XGtE)', type: :model do
  let!(:sorcerer) do
    Klass.find_by(api_index: 'sorcerer') ||
      Klass.create!(api_index: 'sorcerer', name: 'Feiticeiro', hit_die: 6, subclass_level: 1)
  end

  # PHB sorcerer cantrips — 16 oficiais
  let(:phb_cantrips) do
    %w[
      acid-splash blade-ward chill-touch dancing-lights fire-bolt friends
      light mage-hand mending message minor-illusion poison-spray
      prestidigitation ray-of-frost shocking-grasp true-strike
    ]
  end

  # XGtE sorcerer cantrips
  let(:xgte_cantrips) do
    %w[
      pt-atracao-chocante
      pt-controlar-chamas
      pt-criar-fogueira
      pt-infestacao
      pt-lamina-da-chama-esverdeada
      pt-lamina-estrondosa
      pt-lufada
      pt-moldar-agua
      pt-moldar-terra
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
      load Rails.root.join('db/migrate/20260507090000_ensure_sorcerer_cantrip_sources.rb')
      EnsureSorcererCantripSources.new.up
    end

    it 'inclui as 16 cantrips canonicas do PHB' do
      indices = cantrip_api_indices_for(sorcerer)
      missing = phb_cantrips - indices
      expect(missing).to be_empty,
        "Cantrips PHB do feiticeiro sem SpellSource: #{missing.inspect}"
    end

    it 'inclui as 12 cantrips XGtE do feiticeiro' do
      indices = cantrip_api_indices_for(sorcerer)
      missing = xgte_cantrips - indices
      expect(missing).to be_empty,
        "Cantrips XGtE do feiticeiro sem SpellSource: #{missing.inspect}"
    end

    it 'nao cria duplicatas em re-rodada (idempotente)' do
      EnsureSorcererCantripSources.new.up
      EnsureSorcererCantripSources.new.up

      counts = SpellSource
        .where(source_type: 'Klass', source_id: sorcerer.id, spell_id: Spell.where(api_index: all_expected).pluck(:id))
        .group(:spell_id)
        .count

      counts.values.each do |count|
        expect(count).to eq(1), "esperava 1 SpellSource por spell, encontrou #{count}"
      end
    end

    it 'totaliza pelo menos 28 cantrips associadas (16 PHB + 12 XGtE)' do
      indices = cantrip_api_indices_for(sorcerer)
      expect(indices.size).to be >= 28,
        "esperava >= 28 cantrips, recebeu #{indices.size}: #{indices.inspect}"
    end
  end
end
