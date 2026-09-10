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

  # ===== TREINAMENTO EM HORAS (10/09/2026) =====
  #
  # No sistema da mesa, aprender proficiência custa HORAS. Nem toda
  # proficiência é treinável: idioma secreto de classe e "Armas Simples" vêm com
  # a classe, não com treino.
  #
  # Mora no `metadata` de propósito: é exatamente o que essa coluna existe para
  # guardar — o que é específico sem alargar o schema a cada ideia nova.
  #
  #   metadata: { 'trainable' => true, 'training_hours' => 120 }
  #
  validates :api_index, :name, :category, presence: true
  validates :api_index, uniqueness: true
  validates :category, inclusion: { in: CATEGORIES }
  validate :sub_category_belongs_to_category
  validate :training_block_is_coherent

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

  # Treinável? Ausente conta como NÃO — uma proficiência antiga, semeada antes
  # de isto existir, não pode virar treinável por omissão.
  def trainable?
    metadata.is_a?(Hash) && metadata['trainable'] == true
  end

  # Horas de treino necessárias, ou `nil` quando não é treinável / não definidas.
  def training_hours
    return nil unless trainable?

    horas = metadata['training_hours'].to_i
    horas.positive? ? horas : nil
  end

  # O personagem já treinou o suficiente?
  def trained?(horas_acumuladas)
    necessarias = training_hours
    return false if necessarias.nil?

    horas_acumuladas.to_i >= necessarias
  end

  private

  # ⚠️ Zero ou negativo não é "de graça", é engano: uma proficiência marcada
  # treinável com 0 horas seria aprendida sem treino nenhum, e o erro só
  # apareceria na mesa. `nil`/vazio é diferente — significa "ainda por definir".
  def training_block_is_coherent
    return unless metadata.is_a?(Hash)

    bruto = metadata['training_hours']
    return if bruto.nil? || bruto.to_s.strip.empty?

    if bruto.is_a?(Hash) || bruto.is_a?(Array)
      errors.add(:metadata, 'training_hours precisa ser um número de horas')
      return
    end
    errors.add(:metadata, 'horas de treino precisam ser positivas') unless bruto.to_i.positive?
  end

  def sub_category_belongs_to_category
    permitidas = SUB_CATEGORIES[category]
    return if permitidas.nil? && sub_category.blank?
    return if permitidas.present? && permitidas.include?(sub_category)

    errors.add(:sub_category, "#{sub_category.inspect} não é válida para #{category.inspect}")
  end
end
