class SubKlass < ApplicationRecord
  NIVEL_MAXIMO = 20

  validates :name, :klass_id, presence: true
  # ⚠️ Unicidade GLOBAL de propósito: o índice do banco é por (klass_id, api_index),
  # mas `SubclassHpBonus#subclass_block` varre todas as classes do YAML por
  # `api_index` — sem esta validação, duas subs homónimas dariam o bónus errado.
  validates :api_index, uniqueness: true, allow_blank: true
  # ⚠️ `levels_json` é a REGRA da sub-classe e tem 14 leitores que a parseiam. Era
  # TEXT sem validação nenhuma: JSON partido virava `[]` em silêncio no meio da
  # ficha (`character_sheet_summary_service.rb` faz `rescue []`). Agora é jsonb e a
  # forma é validada aqui — o banco aceita qualquer JSON, o modelo não.
  validate :levels_json_bem_formado
  before_validation :normaliza_levels_json

  belongs_to :klass
  has_many :sub_klass_levels, dependent: :destroy
  has_many :features, through: :sub_klass_levels
  has_many :sheet_klasses

  # Scopes para facilitar consultas
  scope :by_klass, ->(klass) { where(klass: klass) }
  scope :with_features, -> { includes(:features) }
  scope :with_levels, -> { includes(:sub_klass_levels) }

  # Métodos para verificar se subclasse tem spellcasting
  def has_spellcasting?
    features.any? { |f| f.name.match?(/conjuração|spellcasting/i) }
  end

  # Método para obter features por nível
  def features_at_level(level)
    level_record = sub_klass_levels.find_by(level: level)
    level_record ? level_record.features : []
  end

  # Leitor TOLERANTE e ÚNICO do campo. Antes do jsonb, 14 pontos faziam
  # `JSON.parse(levels_json) rescue []` — com jsonb esse parse recebe um Array,
  # levanta TypeError e o `rescue` devolve LISTA VAZIA: a sub-classe inteira
  # sumiria da ficha sem erro nenhum. Por isso o parse passou a viver num lugar
  # só, e ele ainda aceita a String do TEXT legado (dump antigo, fixture velha).
  def linhas_de_nivel
    valor = levels_json
    valor = (JSON.parse(valor) rescue nil) if valor.is_a?(String) # rubocop:disable Style/RescueModifier
    return [] unless valor.is_a?(Array)

    valor.select { |linha| linha.is_a?(Hash) }
  end

  # Método para verificar se subclasse é customizada (não do PHB)
  def custom_subclass?
    api_index.present? && !api_index.match?(/^(berserker|totem|lore|valor|fiend|great_old_one|celestial|life|light|nature|tempest|trickery|war|land|moon|spores|wild_magic|draconic|divine_soul|shadow_magic|storm_sorcery|champion|battle_master|eldritch_knight|assassin|thief|arcane_trickster|evocation|abjuration|conjuration|divination|enchantment|illusion|necromancy|transmutation|way_of_the_open_hand|way_of_shadow|way_of_the_four_elements|oath_of_devotion|oath_of_the_ancients|oath_of_vengeance|beast_master|hunter|gloom_stalker|horizon_walker|monster_slayer)$/)
  end

  private

  # Escritor CANÔNICO. A coluna é jsonb (LISTA de níveis), mas há escritores que
  # mandam `to_json` — `DndImportHelpers.apply_subclass_overrides!` e
  # `apply_subclass_grants!` — e linhas históricas com `'{}'`. Em jsonb uma String
  # vira ESCALAR JSON (`"[{…}]"`), não lista: normalizar num ponto só é o que
  # permite trocar o tipo da coluna sem tocar em nenhum dos escritores.
  def normaliza_levels_json
    valor = levels_json
    return if valor.is_a?(Array)

    if valor.is_a?(String)
      texto = valor.strip
      return self.levels_json = [] if texto.empty?

      begin
        valor = JSON.parse(texto)
      rescue JSON::ParserError
        return # fica como veio: a validação REPORTA em vez de engolir
      end
    end

    # O `{}` histórico da factory/seed: "sem níveis", não erro de forma.
    self.levels_json = valor.nil? || (valor.is_a?(Hash) && valor.empty?) ? [] : valor
  end

  def levels_json_bem_formado
    linhas = levels_json
    return if linhas.nil?
    return errors.add(:levels_json, 'não é JSON válido') if linhas.is_a?(String)
    return errors.add(:levels_json, 'deve ser uma lista de níveis') unless linhas.is_a?(Array)

    linhas.each_with_index do |linha, i|
      next errors.add(:levels_json, "linha #{i + 1} não é um objeto") unless linha.is_a?(Hash)

      nivel = linha['level'] || linha[:level]
      unless nivel.is_a?(Integer) && nivel.between?(0, NIVEL_MAXIMO)
        next errors.add(:levels_json, "linha #{i + 1}: `level` deve ser inteiro entre 0 e #{NIVEL_MAXIMO}")
      end

      valida_features(linha['features'] || linha[:features], nivel)
    end
  end

  def valida_features(feats, nivel)
    return if feats.nil?
    return errors.add(:levels_json, "nível #{nivel}: `features` deve ser uma lista") unless feats.is_a?(Array)

    feats.each_with_index do |f, j|
      nome = f.is_a?(Hash) ? (f['name'] || f[:name]) : nil
      errors.add(:levels_json, "nível #{nivel}, feature #{j + 1}: `name` é obrigatório") if nome.to_s.strip.empty?
    end
  end
end
