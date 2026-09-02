# frozen_string_literal: true

# Modelo de COMPANHEIRO do catálogo — o que o Mestre cria no compêndio e o
# jogador escolhe no "Adicionar companheiro".
#
# ⚠️ Espelha o shape que o front já consome (`Companion` em modifierTypes.ts).
# Os campos ricos ficam em jsonb DE PROPÓSITO: traduzi-los para colunas criaria
# uma fronteira a manter em dia sem ganho — quem lê é uma tela só.
class CompanionTemplate < ApplicationRecord
  TYPES = %w[
    familiar beast_companion mount greater_mount
    homunculus summon undead_servant steel_defender wildfire_spirit
  ].freeze

  ORIGINS = %w[purchased spell class_feature].freeze

  SIZES = %w[Tiny Small Medium Large Huge].freeze

  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true
  validates :companion_type, inclusion: { in: TYPES }
  validates :origin, inclusion: { in: ORIGINS }
  validates :size, inclusion: { in: SIZES }, allow_blank: true

  before_validation :normalizar_slug

  scope :do_tipo, ->(t) { where(companion_type: t) if t.present? }
  scope :busca, lambda { |q|
    next if q.blank?

    termo = "%#{q.to_s.strip.downcase}%"
    where('LOWER(name) LIKE :t OR LOWER(slug) LIKE :t', t: termo)
  }

  # Shape que o front consome. As chaves são as do `Companion` (camelCase),
  # porque é o modelo que o `createCompanionFromTemplate` já monta — o template
  # da API entra no MESMO caminho do estático, sem adaptador novo.
  def as_template_json
    {
      templateId: slug,
      name: name,
      type: companion_type,
      origin: origin,
      originSpellId: origin_spell_id,
      originClassFeature: origin_class_feature,
      creatureType: creature_type,
      size: size,
      stats: stats.presence || { 'str' => 10, 'dex' => 10, 'con' => 10, 'int' => 10, 'wis' => 10, 'cha' => 10 },
      ac: ac.to_i,
      hpMax: hp_max.to_i,
      speed: speed,
      attacks: attacks || [],
      specialActions: special_actions || [],
      profBonus: prof_bonus.to_i,
      carryCapacity: carry_capacity,
      description: description,
      source: source,
      tags: tags || [],
      # As bandeiras viajam achatadas: é assim que o `Companion` as espera.
      **bandeiras_json,
    }
  end

  private

  # `flags` guarda só o que o TIPO usa; o default de cada uma é `false`, e a
  # ausência significa isso — não gravamos oito booleanos em toda linha.
  def bandeiras_json
    f = (flags || {}).stringify_keys
    {
      useOwnerProficiency: !!f['use_owner_proficiency'],
      scalesWithOwnerLevel: !!f['scales_with_owner_level'],
      ownerLevelRequired: f['owner_level_required'],
      sharesSenses: !!f['shares_senses'],
      deliverTouchSpells: !!f['deliver_touch_spells'],
      temporary: !!f['temporary'],
      duration: f['duration'],
      requiresConcentration: !!f['requires_concentration'],
    }.compact
  end

  def normalizar_slug
    self.slug = slug.presence || name.to_s.parameterize
    self.slug = slug.to_s.parameterize
  end
end
