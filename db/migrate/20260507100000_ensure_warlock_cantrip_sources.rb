class EnsureWarlockCantripSources < ActiveRecord::Migration[6.0]
  # Cria SpellSource para os cantrips PHB + XGtE do bruxo que existem em
  # `spells` mas estavam sem associacao via `spell_sources`.
  #
  # Antes: bruxo tinha 7 cantrips. Faltavam 2 PHB (Blade Ward, Friends) +
  # 9 XGtE. Total esperado: 18.
  #
  # Idempotente: usa `find_or_create_by!`.
  WARLOCK_CANTRIPS = %w[
    blade-ward
    chill-touch
    eldritch-blast
    friends
    mage-hand
    minor-illusion
    poison-spray
    prestidigitation
    true-strike
    pt-atracao-chocante
    pt-criar-fogueira
    pt-infestacao
    pt-lamina-da-chama-esverdeada
    pt-lamina-estrondosa
    pt-pedagio-aos-mortos
    pt-picada-congelante
    pt-rompante-de-espadas
    pt-trovoada
  ].freeze

  def up
    return unless defined?(::Klass) && defined?(::Spell) && defined?(::SpellSource)

    warlock = ::Klass.find_by(api_index: 'warlock')
    unless warlock
      say 'Klass(warlock) nao encontrado — pulando criacao de SpellSource'
      return
    end

    WARLOCK_CANTRIPS.each do |api_index|
      spell = ::Spell.find_by(api_index: api_index)
      unless spell
        say "Spell(api_index=#{api_index}) nao encontrado — pulando"
        next
      end

      ::SpellSource.find_or_create_by!(
        source_type: 'Klass',
        source_id: warlock.id,
        spell_id: spell.id
      )
    end
  end

  def down
    return unless defined?(::Klass) && defined?(::Spell) && defined?(::SpellSource)

    warlock = ::Klass.find_by(api_index: 'warlock')
    return unless warlock

    spell_ids = ::Spell.where(api_index: WARLOCK_CANTRIPS).pluck(:id)
    ::SpellSource.where(source_type: 'Klass', source_id: warlock.id, spell_id: spell_ids).delete_all
  end
end
