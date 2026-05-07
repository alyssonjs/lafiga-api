class EnsureSorcererCantripSources < ActiveRecord::Migration[6.0]
  # Cria SpellSource para os cantrips PHB + XGtE do feiticeiro que existem em
  # `spells` mas estavam sem associacao via `spell_sources`.
  #
  # Antes: feiticeiro tinha 14 cantrips PHB associados. Faltavam 2 PHB
  # (Blade Ward, Friends) + 12 XGtE. Total esperado: 28.
  #
  # Idempotente: usa `find_or_create_by!`.
  SORCERER_CANTRIPS = %w[
    acid-splash
    blade-ward
    chill-touch
    dancing-lights
    fire-bolt
    friends
    light
    mage-hand
    mending
    message
    minor-illusion
    poison-spray
    prestidigitation
    ray-of-frost
    shocking-grasp
    true-strike
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
  ].freeze

  def up
    return unless defined?(::Klass) && defined?(::Spell) && defined?(::SpellSource)

    sorcerer = ::Klass.find_by(api_index: 'sorcerer')
    unless sorcerer
      say 'Klass(sorcerer) nao encontrado — pulando criacao de SpellSource'
      return
    end

    SORCERER_CANTRIPS.each do |api_index|
      spell = ::Spell.find_by(api_index: api_index)
      unless spell
        say "Spell(api_index=#{api_index}) nao encontrado — pulando"
        next
      end

      ::SpellSource.find_or_create_by!(
        source_type: 'Klass',
        source_id: sorcerer.id,
        spell_id: spell.id
      )
    end
  end

  def down
    return unless defined?(::Klass) && defined?(::Spell) && defined?(::SpellSource)

    sorcerer = ::Klass.find_by(api_index: 'sorcerer')
    return unless sorcerer

    spell_ids = ::Spell.where(api_index: SORCERER_CANTRIPS).pluck(:id)
    ::SpellSource.where(source_type: 'Klass', source_id: sorcerer.id, spell_id: spell_ids).delete_all
  end
end
