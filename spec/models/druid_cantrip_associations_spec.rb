require 'rails_helper'

# Regressao: o BonusCantripPicker (Druid Circulo da Terra L4 e outras subclasses
# que dao 1 cantrip extra da lista de druid) refletia apenas ~7 cantrips
# porque o backend so tinha 7 SpellSource associadas a Klass(druid). Faltavam:
#
# PHB:
#   - thorn-whip (Chicote De Espinhos)
#
# XGtE:
#   - pt-controlar-chamas, pt-criar-fogueira, pt-infestacao, pt-lufada,
#     pt-moldar-agua, pt-moldar-terra, pt-pedra-encantada, pt-picada-congelante,
#     pt-selvageria-primal, pt-trovoada
#
# Este spec verifica que a migration `EnsureDruidCantripSources` cria todas as
# associacoes esperadas, idempotente. Se uma nova migration de seed esquecer
# de associar uma cantrip, este spec falha.
RSpec.describe 'Druid cantrip associations (PHB + XGtE)', type: :model do
  let!(:druid) do
    Klass.find_by(api_index: 'druid') ||
      Klass.create!(api_index: 'druid', name: 'Druida', hit_die: 8, subclass_level: 2)
  end

  let(:phb_cantrips) do
    %w[druidcraft guidance mending poison-spray produce-flame resistance shillelagh thorn-whip]
  end

  let(:xgte_cantrips) do
    %w[pt-controlar-chamas pt-criar-fogueira pt-picada-congelante pt-trovoada
       pt-selvageria-primal pt-pedra-encantada pt-lufada pt-infestacao
       pt-moldar-terra pt-moldar-agua]
  end

  let(:all_expected) { phb_cantrips + xgte_cantrips }

  before do
    # Garantir que as Spells existem no DB de teste (sem class association).
    # A migration `ensure_druid_cantrip_sources.rb` e' quem cria os SpellSource.
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
      # Roda a logica de associacao definida pela migration
      # (ver db/migrate/20260507050000_ensure_druid_cantrip_sources.rb).
      load Rails.root.join('db/migrate/20260507050000_ensure_druid_cantrip_sources.rb')
      EnsureDruidCantripSources.new.up
    end

    it 'inclui as 8 cantrips canonicas do PHB' do
      indices = cantrip_api_indices_for(druid)
      missing = phb_cantrips - indices
      expect(missing).to be_empty,
        "Cantrips PHB do druida sem SpellSource: #{missing.inspect}"
    end

    it 'inclui as 10 cantrips XGtE associadas ao druida' do
      indices = cantrip_api_indices_for(druid)
      missing = xgte_cantrips - indices
      expect(missing).to be_empty,
        "Cantrips XGtE do druida sem SpellSource: #{missing.inspect}"
    end

    it 'nao cria duplicatas em re-rodada (idempotente)' do
      EnsureDruidCantripSources.new.up
      EnsureDruidCantripSources.new.up

      counts = SpellSource
        .where(source_type: 'Klass', source_id: druid.id, spell_id: Spell.where(api_index: all_expected).pluck(:id))
        .group(:spell_id)
        .count

      counts.values.each do |count|
        expect(count).to eq(1), "esperava 1 SpellSource por spell, encontrou #{count}"
      end
    end

    it 'totaliza pelo menos 17 cantrips associadas (8 PHB + 10 XGtE - sobreposicoes)' do
      indices = cantrip_api_indices_for(druid)
      expect(indices.size).to be >= 17,
        "esperava >= 17 cantrips, recebeu #{indices.size}: #{indices.inspect}"
    end
  end
end
