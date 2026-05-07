class EnsureBardCantripSources < ActiveRecord::Migration[6.0]
  # Cria SpellSource para os cantrips PHB + XGtE do bardo que existem em
  # `spells` mas estavam sem associacao via `spell_sources`.
  #
  # Antes: bardo tinha 8 cantrips associados. Faltavam 3 PHB (Blade Ward,
  # Friends, Vicious Mockery) + 1 XGtE (Thunderclap). Total esperado: 12.
  #
  # Idempotente: usa `find_or_create_by!`.
  BARD_CANTRIPS = %w[
    dancing-lights
    friends
    light
    mage-hand
    mending
    message
    minor-illusion
    prestidigitation
    true-strike
    pt-zombaria-viciosa
    blade-ward
    pt-trovoada
  ].freeze

  def up
    return unless defined?(::Klass) && defined?(::Spell) && defined?(::SpellSource)

    bard = ::Klass.find_by(api_index: 'bard')
    unless bard
      say 'Klass(bard) nao encontrado — pulando criacao de SpellSource'
      return
    end

    BARD_CANTRIPS.each do |api_index|
      spell = ::Spell.find_by(api_index: api_index)
      unless spell
        say "Spell(api_index=#{api_index}) nao encontrado — pulando"
        next
      end

      ::SpellSource.find_or_create_by!(
        source_type: 'Klass',
        source_id: bard.id,
        spell_id: spell.id
      )
    end
  end

  def down
    return unless defined?(::Klass) && defined?(::Spell) && defined?(::SpellSource)

    bard = ::Klass.find_by(api_index: 'bard')
    return unless bard

    spell_ids = ::Spell.where(api_index: BARD_CANTRIPS).pluck(:id)
    ::SpellSource.where(source_type: 'Klass', source_id: bard.id, spell_id: spell_ids).delete_all
  end
end
