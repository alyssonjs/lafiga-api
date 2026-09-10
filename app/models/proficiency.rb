# frozen_string_literal: true

# Uma proficiência do catálogo. Ver `db/migrate/*_create_proficiencies.rb`.
#
# FASE 0: só `language` está semeado. As outras categorias existem no enum
# porque a taxonomia foi decidida de uma vez (levantamento em
# `.cursor/dnd-rules/proficiencias-levantamento.md`) — semear é que é por fase.
class Proficiency < ApplicationRecord
  has_many :proficiency_aliases, dependent: :destroy

  CATEGORIES = %w[
    skill saving_throw weapon_category weapon armor tool vehicle language
  ].freeze

  # Sub-categorias válidas por categoria. `nil` = a categoria não subdivide.
  SUB_CATEGORIES = {
    'language' => %w[standard exotic primordial_dialect monster racial class_secret],
    'tool'     => %w[artisan instrument gaming kit other],
    'vehicle'  => %w[land water],
    'armor'    => %w[light medium heavy shield],
    'weapon'   => %w[simple_melee simple_ranged martial_melee martial_ranged],
  }.freeze

  validates :api_index, :name, :category, presence: true
  validates :api_index, uniqueness: true
  validates :category, inclusion: { in: CATEGORIES }
  validate :sub_category_belongs_to_category

  scope :published, -> { where(published: true) }
  scope :of, ->(cat) { where(category: cat) }

  # Forma canônica de comparação: minúscula, sem acento, sem pontuação,
  # espaços colapsados.
  #
  # ⚠️ É a MESMA normalização dos apelidos. Se divergir, o catálogo deixa de
  # resolver e volta-se ao ponto de partida.
  def self.normalize(raw)
    s = raw.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, '')
    s.downcase.gsub(/[^a-z0-9]+/, ' ').strip
  end

  # Resolve uma string crua para a linha canônica, ou `nil`.
  #
  # `category:` restringe a busca. Sem ela a busca é global — e, como o índice
  # de apelido é único globalmente, não há ambiguidade possível.
  def self.resolve(raw, category: nil)
    key = normalize(raw)
    return nil if key.empty?

    escopo = category ? of(category) : all
    escopo.joins(:proficiency_aliases).find_by(proficiency_aliases: { alias_key: key })
  end

  def self.resolve!(raw, category: nil)
    resolve(raw, category: category) ||
      raise(ActiveRecord::RecordNotFound, "proficiência não catalogada: #{raw.inspect}")
  end

  # Registra um apelido apontando para esta linha. Idempotente.
  #
  # Levanta se o apelido já pertence a OUTRA proficiência — ver o comentário do
  # índice único na migration: colisão é para doer.
  def add_alias!(raw)
    key = self.class.normalize(raw)
    return nil if key.empty?

    existente = ProficiencyAlias.find_by(alias_key: key)
    if existente
      return existente if existente.proficiency_id == id

      raise ArgumentError,
            "apelido #{raw.inspect} (#{key.inspect}) já aponta para " \
            "#{existente.proficiency.api_index.inspect}, não para #{api_index.inspect}"
    end
    proficiency_aliases.create!(alias_key: key, raw: raw.to_s)
  end

  private

  def sub_category_belongs_to_category
    permitidas = SUB_CATEGORIES[category]
    return if permitidas.nil? && sub_category.blank?
    return if permitidas.present? && permitidas.include?(sub_category)

    errors.add(:sub_category, "#{sub_category.inspect} não é válida para #{category.inspect}")
  end
end
