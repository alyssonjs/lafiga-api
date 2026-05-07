require 'rails_helper'

# Regressao: o BonusCantripPicker / SpellPicker do mago refletia apenas as 14
# cantrips PHB iniciais associadas via SpellSource. Faltavam:
#
# PHB (estavam no DB sem SpellSource para wizard):
#   - blade-ward (Proteção Contra Lâminas)
#   - friends    (Amizade)
#
# XGtE (idem):
#   - pt-atracao-chocante       (Lightning Lure)
#   - pt-controlar-chamas       (Control Flames)
#   - pt-criar-fogueira         (Create Bonfire)
#   - pt-infestacao             (Infestation)
#   - pt-lamina-da-chama-esverdeada (Green-Flame Blade)
#   - pt-lamina-estrondosa      (Booming Blade)
#   - pt-lufada                 (Gust)
#   - pt-moldar-agua            (Shape Water)
#   - pt-moldar-terra           (Mold Earth)
#   - pt-pedagio-aos-mortos     (Toll the Dead)
#   - pt-picada-congelante      (Frostbite)
#   - pt-rompante-de-espadas    (Sword Burst)
#   - pt-trovoada               (Thunderclap)
RSpec.describe 'Wizard cantrip associations (PHB + XGtE)', type: :model do
  let!(:wizard) do
    Klass.find_by(api_index: 'wizard') ||
      Klass.create!(api_index: 'wizard', name: 'Mago', hit_die: 6, subclass_level: 2)
  end

  # PHB wizard cantrips — 16 oficiais (Acid Splash, Blade Ward, Chill Touch,
  # Dancing Lights, Fire Bolt, Friends, Light, Mage Hand, Mending, Message,
  # Minor Illusion, Poison Spray, Prestidigitation, Ray of Frost, Shocking
  # Grasp, True Strike).
  let(:phb_cantrips) do
    %w[
      acid-splash blade-ward chill-touch dancing-lights fire-bolt
      friends light mage-hand mending message minor-illusion poison-spray
      prestidigitation ray-of-frost shocking-grasp true-strike
    ]
  end

  # XGtE wizard cantrips canonicos.
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
      load Rails.root.join('db/migrate/20260507060000_ensure_wizard_cantrip_sources.rb')
      EnsureWizardCantripSources.new.up
    end

    it 'inclui as 16 cantrips canonicas do PHB' do
      indices = cantrip_api_indices_for(wizard)
      missing = phb_cantrips - indices
      expect(missing).to be_empty,
        "Cantrips PHB do mago sem SpellSource: #{missing.inspect}"
    end

    it 'inclui as 13 cantrips XGtE do mago' do
      indices = cantrip_api_indices_for(wizard)
      missing = xgte_cantrips - indices
      expect(missing).to be_empty,
        "Cantrips XGtE do mago sem SpellSource: #{missing.inspect}"
    end

    it 'nao cria duplicatas em re-rodada (idempotente)' do
      EnsureWizardCantripSources.new.up
      EnsureWizardCantripSources.new.up

      counts = SpellSource
        .where(source_type: 'Klass', source_id: wizard.id, spell_id: Spell.where(api_index: all_expected).pluck(:id))
        .group(:spell_id)
        .count

      counts.values.each do |count|
        expect(count).to eq(1), "esperava 1 SpellSource por spell, encontrou #{count}"
      end
    end

    it 'totaliza pelo menos 29 cantrips associadas (16 PHB + 13 XGtE)' do
      indices = cantrip_api_indices_for(wizard)
      expect(indices.size).to be >= 29,
        "esperava >= 29 cantrips, recebeu #{indices.size}: #{indices.inspect}"
    end
  end
end
