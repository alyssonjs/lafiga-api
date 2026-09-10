# frozen_string_literal: true

# De onde uma magia vem para um personagem.
#
# ⚠️ Esta tabela é AUTORIDADE para `Klass` e `SubKlass`: o level-up e as magias
# preparadas leem daqui. Não é registro decorativo — mexer aqui muda o jogo.
#
# Para `Race`, `SubRace`, `Feat` e `Feature` ela começa como REGISTRO derivado
# (fase 0 do plano em `.cursor/dnd-rules/magias-atrelacao-plano.md`); migrar a
# autoridade do YAML racial para cá é uma fase própria, com paridade medida.
class SpellSource < ApplicationRecord
  belongs_to :spell

  # Referência polimórfica sem a polimorfia do Rails, para manter simples.
  SOURCE_TYPES = %w[Klass SubKlass Race SubRace Feat Feature Background].freeze

  # COMO se conjura:
  #   with_slot      gasta espaço de magia (o caso das listas de classe)
  #   at_will        à vontade, sem gastar nada (Taumaturgia do Tiefling)
  #   uses_per_rest  N vezes por descanso (o "1/dia" dos legados de sub-raça)
  #   resource       gasta outro recurso (Monge das Sombras: 2 Chi)
  CASTING_MODES = %w[with_slot at_will uses_per_rest resource].freeze

  # ⚠️ `choice` = a fonte oferece num POOL e o personagem escolhe (o Alto Elfo
  # escolhe 1 truque de mago). Tratar pool como concessão faz o índice mentir —
  # foi o que aconteceu nas proficiências, em 237 linhas.
  GRANT_MODES = %w[fixed choice].freeze
  ORIGINS = %w[derived manual].freeze

  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :casting_mode, inclusion: { in: CASTING_MODES }
  validates :grant_mode, inclusion: { in: GRANT_MODES }
  validates :origin, inclusion: { in: ORIGINS }
  validates :resource_cost, numericality: { greater_than: 0, allow_nil: true }
  validates :choose_count, numericality: { greater_than: 0, allow_nil: true }
  validate :resource_fields_belong_to_resource_mode
  validate :uses_belong_to_uses_mode

  scope :derived, -> { where(origin: 'derived') }
  scope :manual, -> { where(origin: 'manual') }
  scope :innate, -> { where.not(casting_mode: 'with_slot') }

  def source_record
    return nil unless SOURCE_TYPES.include?(source_type)

    source_type.constantize.find_by(id: source_id)
  end

  # Como a ficha descreve o custo: "à vontade", "1/descanso longo", "2 Chi".
  def cost_label
    case casting_mode
    when 'at_will' then 'à vontade'
    when 'resource' then [resource_cost, resource_key].compact.join(' ').presence || 'recurso'
    when 'uses_per_rest'
      if uses_per_long_rest.present? then "#{uses_per_long_rest}/descanso longo"
      elsif uses_per_short_rest.present? then "#{uses_per_short_rest}/descanso curto"
      else 'usos por descanso'
      end
    else 'espaço de magia'
    end
  end

  private

  def resource_fields_belong_to_resource_mode
    return if casting_mode == 'resource'
    return if resource_key.blank? && resource_cost.blank?

    errors.add(:resource_key, 'só se aplica a casting_mode `resource`')
  end

  # ⚠️ Um limite gravado num modo que o ignora seria pior do que não o ter: a
  # ficha mostraria "1/dia" e a regra deixaria conjurar à vontade.
  def uses_belong_to_uses_mode
    return if casting_mode == 'uses_per_rest'
    return if uses_per_long_rest.blank? && uses_per_short_rest.blank?

    errors.add(:uses_per_long_rest, 'só se aplica a casting_mode `uses_per_rest`')
  end
end
