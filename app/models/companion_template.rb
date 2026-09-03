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

  # PNG do TOKEN — o desenho que representa a criatura no mapa. Mesma casa do
  # `MapAsset#image`: ActiveStorage, e o mapa referencia a URL em vez de embutir
  # a imagem (o token avulso guarda um data-URL de 500 KB no JSONB do mapa; um
  # companheiro do catálogo entraria em TODO mapa onde fosse invocado).
  ALLOWED_TOKEN_TYPES = %w[image/png image/jpeg image/webp image/gif].freeze
  MAX_TOKEN_BYTES = 2.megabytes

  has_one_attached :token_image

  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true
  validates :companion_type, inclusion: { in: TYPES }
  validates :origin, inclusion: { in: ORIGINS }
  validates :size, inclusion: { in: SIZES }, allow_blank: true

  before_validation :normalizar_slug
  before_save :normalizar_ataques
  validate :token_image_valido

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
      # Em PÉS, o mesmo shape de `combat_npcs.speed_modes` e do bestiário.
      # A string `speed` acima é a EXIBIÇÃO; isto é o que o combate usa.
      speedModes: speed_modes.presence || {},
      attacks: attacks || [],
      specialActions: special_actions || [],
      profBonus: prof_bonus.to_i,
      carryCapacity: carry_capacity,
      description: description,
      source: source,
      tags: tags || [],
      skillProficiencies: skill_proficiencies || [],
      saveProficiencies: save_proficiencies || [],
      # `image` e não `tokenImageUrl`: é o campo que o `Companion` da ficha já
      # tem, então instanciar o modelo (spread) leva o token junto sem tradutor.
      image: token_image_url,
      # As bandeiras viajam achatadas: é assim que o `Companion` as espera.
      **bandeiras_json,
    }
  end

  # Path relativo (sem host) — o front prefixa com a baseURL da API.
  #
  # ⚠️ Duas fontes, com precedência: o PNG PRÓPRIO (upload) vence a biblioteca.
  # É a ordem que respeita a última escolha do Mestre — subir um arquivo depois
  # de escolher da biblioteca tem de valer.
  #
  # O da biblioteca aponta para o endpoint do `map_assets`, que já serve o blob
  # com cache imutável e SEM gate de DM (o token é da mesa inteira).
  def token_image_url
    return proprio_token_url if token_image.attached?
    return biblioteca_token_url if token_map_asset_id.present?

    nil
  rescue StandardError
    nil
  end

  private

  # Endpoint PRÓPRIO: 1 requisição com cache imutável, sem o redirect 302 do
  # ActiveStorage. `v=` é o id do blob — muda só no re-upload.
  def proprio_token_url
    ver = token_image.blob&.id || updated_at.to_i
    "/api/v1/public/companion_templates/#{id}/token_image?v=#{ver}"
  end

  def biblioteca_token_url
    "/api/v1/admin/map_assets/#{token_map_asset_id}/image?v=#{token_map_asset_id}"
  end

  public

  private

  def token_image_valido
    return unless token_image.attached?

    if token_image.blob.byte_size.to_i > MAX_TOKEN_BYTES
      errors.add(:token_image, "muito grande (máx. #{MAX_TOKEN_BYTES / 1.megabyte} MB)")
    end
    return if ALLOWED_TOKEN_TYPES.include?(token_image.blob.content_type)

    errors.add(:token_image, 'tipo inválido (use PNG, JPEG, WebP ou GIF)')
  end

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

  # ⚠️ `proficient` chega como STRING ("true"/"false") quando o corpo nao e JSON.
  # O front decide por `=== false`, entao a string "false" concederia a
  # proficiencia que o Mestre acabou de desligar — falha ABERTA, a pior.
  # Guardamos sempre booleano de verdade.
  def normalizar_ataques
    return if attacks.blank?

    self.attacks = attacks.map do |a|
      linha = a.respond_to?(:to_h) ? a.to_h : a
      next linha unless linha.is_a?(Hash)

      linha = linha.stringify_keys
      linha['proficient'] = ActiveModel::Type::Boolean.new.cast(linha['proficient']).present? if linha.key?('proficient')
      linha
    end
  end

  def normalizar_slug
    self.slug = slug.presence || name.to_s.parameterize
    self.slug = slug.to_s.parameterize
  end
end
