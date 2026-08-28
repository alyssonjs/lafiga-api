# frozen_string_literal: true

# Applies field-level token mutations under a row lock. A client never replaces
# the complete JSONB array, so a second tab can move a token while another one
# changes its equipment/customization without either operation restoring stale
# fields from its local snapshot.
class BattleMapTokenMutations
  MAX_MUTATIONS = 500
  MAX_TOKEN_ID_LENGTH = 160
  SERVER_OWNED_CHARACTER_FIELDS = %w[chibiEquipment chibiCustomization].freeze

  class Invalid < StandardError; end

  Result = Struct.new(:mutation, :version, keyword_init: true)

  def self.call(map:, mutation:, allow_character_visuals: false, session_layer: nil)
    new(
      map: map,
      mutation: mutation,
      allow_character_visuals: allow_character_visuals,
      session_layer: session_layer,
    ).call
  end

  def initialize(map:, mutation:, allow_character_visuals: false, session_layer: nil)
    @map = map
    @raw = normalize_hash(mutation)
    @allow_character_visuals = allow_character_visuals
    @session_layer = session_layer
  end

  # Sem camada explicita, o mapa e o alvo — preserva os chamadores antigos.
  def write_target
    @session_layer || @map
  end

  # A camada ja devolve tabuleiro + mesa mesclados; o mapa responde inteiro.
  def read_source
    @session_layer ? @session_layer.tokens : @map.tokens
  end

  def call
    additions = normalize_additions(@raw['additions'])
    patches = normalize_patches(@raw['patches'])
    delete_ids = normalize_ids(@raw['delete_ids'] || @raw['deleteIds'])
    validate_count!(additions, patches, delete_ids)

    applied = { additions: [], patches: [], delete_ids: [] }

    @map.with_lock do
      @map.reload
      # Le do MESMO alvo em que grava (camada da mesa ou mapa) — ler do mapa e
      # gravar na camada perderia o token de vista.
      tokens = Array(read_source).map(&:deep_dup)
      index_by_id = token_index(tokens)

      delete_ids.each do |token_id|
        index = index_by_id[token_id]
        next unless index

        tokens[index] = nil
        applied[:delete_ids] << token_id
      end
      tokens.compact!
      index_by_id = token_index(tokens)

      # Retrying an addition is a no-op when that id already exists. Treating it
      # as a replacement would let a delayed retry restore stale token fields.
      additions.each do |token|
        token_id = token.fetch('id')
        next if index_by_id.key?(token_id)

        tokens << token
        index_by_id[token_id] = tokens.length - 1
        applied[:additions] << token.deep_dup
      end

      patches.each do |patch|
        token_id = patch.fetch('token_id')
        index = index_by_id[token_id]
        next unless index

        token = tokens[index]
        actual_changes = {}
        actual_unset = []

        patch.fetch('changes').each do |key, value|
          next if protected_character_field?(token, key)
          next if key == 'id' || token[key] == value

          token[key] = value
          actual_changes[key] = value
        end
        patch.fetch('unset').each do |key|
          next if protected_character_field?(token, key)
          next if key == 'id' || !token.key?(key)

          token.delete(key)
          actual_unset << key
        end

        next if actual_changes.empty? && actual_unset.empty?

        applied[:patches] << {
          token_id: token_id,
          changes: actual_changes,
          unset: actual_unset,
        }
      end

      # Alvo pode ser a camada da MESA (sessao) ou o proprio mapa.
      write_target.update!(tokens: tokens) unless mutation_empty?(applied)
    end

    Result.new(
      mutation: applied,
      # Da CAMADA que gravou: numa sessao as criaturas vao para o vinculo e o
      # `map.updated_at` fica parado — a versao congelada fazia o cliente
      # descartar as mutacoes seguintes do mesmo token.
      version: @session_layer&.persistence_version ||
        (@map.updated_at.to_f * 1_000_000).round,
    )
  end

  private

  def normalize_hash(value)
    hash = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
    raise Invalid, 'token_mutation deve ser um objeto' unless hash.is_a?(Hash)

    hash.deep_stringify_keys
  end

  def normalize_additions(value)
    Array(value).map do |entry|
      token = normalize_hash(entry)
      token_id = normalize_id(token['id'])
      token['id'] = token_id
      token
    end
  end

  def normalize_patches(value)
    Array(value).map do |entry|
      patch = normalize_hash(entry)
      changes = normalize_hash(patch['changes'] || {})
      changes.delete('id')
      {
        'token_id' => normalize_id(patch['token_id'] || patch['tokenId']),
        'changes' => changes,
        'unset' => normalize_ids(patch['unset']).reject { |key| key == 'id' },
      }
    end
  end

  def normalize_ids(value)
    Array(value).map { |id| normalize_id(id) }.uniq
  end

  def normalize_id(value)
    id = value.to_s
    if id.blank? || id.length > MAX_TOKEN_ID_LENGTH
      raise Invalid, 'id de token invalido'
    end
    id
  end

  def validate_count!(*collections)
    total = collections.sum(&:length)
    raise Invalid, "mutacoes demais (maximo #{MAX_MUTATIONS})" if total > MAX_MUTATIONS
  end

  def token_index(tokens)
    tokens.each_with_index.each_with_object({}) do |(token, index), out|
      token_id = (token['id'] || token[:id]).to_s
      out[token_id] = index if token_id.present?
    end
  end

  def mutation_empty?(mutation)
    mutation.values.all?(&:empty?)
  end

  def protected_character_field?(token, key)
    return false if @allow_character_visuals
    return false if (token['characterId'] || token[:characterId]).blank?

    SERVER_OWNED_CHARACTER_FIELDS.include?(key.to_s)
  end
end
