class EnsureWizardCantripSources < ActiveRecord::Migration[6.0]
  # Cria SpellSource para os cantrips PHB + XGtE do mago que existem na
  # tabela `spells` mas estavam sem associacao via `spell_sources`.
  #
  # Antes: o BonusCantripPicker / SpellPicker mostrava 14 cantrips (PHB
  # core via dnd_import.rake). Faltavam 2 PHB (blade-ward, friends) +
  # 13 XGtE — todos ja existiam no DB mas sem `SpellSource` para wizard.
  #
  # Idempotente: usa `find_or_create_by!`.
  WIZARD_CANTRIPS = %w[
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
    pt-pedagio-aos-mortos
    pt-picada-congelante
    pt-rompante-de-espadas
    pt-trovoada
  ].freeze

  def up
    return unless defined?(::Klass) && defined?(::Spell) && defined?(::SpellSource)

    wizard = ::Klass.find_by(api_index: 'wizard')
    unless wizard
      say 'Klass(wizard) nao encontrado — pulando criacao de SpellSource'
      return
    end

    WIZARD_CANTRIPS.each do |api_index|
      spell = ::Spell.find_by(api_index: api_index)
      unless spell
        say "Spell(api_index=#{api_index}) nao encontrado — pulando"
        next
      end

      ::SpellSource.find_or_create_by!(
        source_type: 'Klass',
        source_id: wizard.id,
        spell_id: spell.id
      )
    end
  end

  def down
    return unless defined?(::Klass) && defined?(::Spell) && defined?(::SpellSource)

    wizard = ::Klass.find_by(api_index: 'wizard')
    return unless wizard

    spell_ids = ::Spell.where(api_index: WIZARD_CANTRIPS).pluck(:id)
    ::SpellSource.where(source_type: 'Klass', source_id: wizard.id, spell_id: spell_ids).delete_all
  end
end
