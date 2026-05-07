class EnsureDruidCantripSources < ActiveRecord::Migration[6.0]
  # Cria SpellSource para os cantrips PHB + XGtE do druida que existem na
  # tabela `spells` mas estavam sem associacao via `spell_sources`.
  #
  # Antes: o BonusCantripPicker (Druid Circulo da Terra L4 etc.) refletia
  # apenas 7 cantrips do druida. Faltavam Chicote de Espinhos (PHB) +
  # 10 cantrips XGtE — todos ja existiam em `spells` (via spells_import_xlsx)
  # mas sem `SpellSource` associado a Klass(druid), entao nao apareciam em
  # nenhuma listagem por classe.
  #
  # Idempotente: usa `find_or_create_by!` — nao cria duplicatas em re-rodadas.
  DRUID_CANTRIPS = %w[
    druidcraft
    guidance
    mending
    poison-spray
    produce-flame
    resistance
    shillelagh
    thorn-whip
    pt-controlar-chamas
    pt-criar-fogueira
    pt-picada-congelante
    pt-trovoada
    pt-selvageria-primal
    pt-pedra-encantada
    pt-lufada
    pt-infestacao
    pt-moldar-terra
    pt-moldar-agua
  ].freeze

  def up
    return unless defined?(::Klass) && defined?(::Spell) && defined?(::SpellSource)

    druid = ::Klass.find_by(api_index: 'druid')
    unless druid
      say 'Klass(druid) nao encontrado — pulando criacao de SpellSource'
      return
    end

    DRUID_CANTRIPS.each do |api_index|
      spell = ::Spell.find_by(api_index: api_index)
      unless spell
        say "Spell(api_index=#{api_index}) nao encontrado — pulando"
        next
      end

      ::SpellSource.find_or_create_by!(
        source_type: 'Klass',
        source_id: druid.id,
        spell_id: spell.id
      )
    end
  end

  def down
    return unless defined?(::Klass) && defined?(::Spell) && defined?(::SpellSource)

    druid = ::Klass.find_by(api_index: 'druid')
    return unless druid

    spell_ids = ::Spell.where(api_index: DRUID_CANTRIPS).pluck(:id)
    ::SpellSource.where(source_type: 'Klass', source_id: druid.id, spell_id: spell_ids).delete_all
  end
end
