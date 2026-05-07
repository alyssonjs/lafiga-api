class EnsureClericCantripSources < ActiveRecord::Migration[6.0]
  # Cria SpellSource para os cantrips XGtE do clerigo que existem na tabela
  # `spells` mas estavam sem associacao via `spell_sources`.
  #
  # Antes: clerigo tinha 7 cantrips PHB associados (Chama Sagrada, Consertar,
  # Estabilizar, Luz, Orientação, Resistência, Taumaturgia). Faltavam os 2
  # XGtE (Word of Radiance e Toll the Dead) — ja existiam no DB mas sem
  # `SpellSource` para cleric.
  #
  # Idempotente: usa `find_or_create_by!`.
  CLERIC_CANTRIPS = %w[
    guidance
    light
    mending
    resistance
    sacred-flame
    spare-the-dying
    thaumaturgy
    pt-mao-do-esplendor
    pt-pedagio-aos-mortos
  ].freeze

  def up
    return unless defined?(::Klass) && defined?(::Spell) && defined?(::SpellSource)

    cleric = ::Klass.find_by(api_index: 'cleric')
    unless cleric
      say 'Klass(cleric) nao encontrado — pulando criacao de SpellSource'
      return
    end

    CLERIC_CANTRIPS.each do |api_index|
      spell = ::Spell.find_by(api_index: api_index)
      unless spell
        say "Spell(api_index=#{api_index}) nao encontrado — pulando"
        next
      end

      ::SpellSource.find_or_create_by!(
        source_type: 'Klass',
        source_id: cleric.id,
        spell_id: spell.id
      )
    end
  end

  def down
    return unless defined?(::Klass) && defined?(::Spell) && defined?(::SpellSource)

    cleric = ::Klass.find_by(api_index: 'cleric')
    return unless cleric

    spell_ids = ::Spell.where(api_index: CLERIC_CANTRIPS).pluck(:id)
    ::SpellSource.where(source_type: 'Klass', source_id: cleric.id, spell_id: spell_ids).delete_all
  end
end
