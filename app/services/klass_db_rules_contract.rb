# frozen_string_literal: true

# Contrato mínimo para a coluna `klasses.rules` (JSONB), espelhando o formato de
# `ClassRules::CLASS_RULES` (símbolos em Ruby → chaves string em JSON).
#
# * `saving_throws` em DB: usar códigos de atributo em inglês (`str`, `dex`, …) como
#   no hash Ruby — o `KlassClassRulesProvider` aplica `SavingThrowsCatalog` ao ler.
# * Campos além do mínimo são livres; o motor tolera o mesmo subconjunto que o legado.
module KlassDbRulesContract
  # Sem isto, `ClassRules.find` / wizard não têm identidade básica da classe.
  REQUIRED_ROOT_KEYS = %i[id name hit_die].freeze

  # Recomendado para criação de personagem; o rake `class_rules:dump_sample` gera
  # o pacote completo a partir de `ClassRules::CLASS_RULES` (não só o mínimo).
  RECOMMENDED_ROOT_KEYS = %i[
    primary_abilities
    saving_throws
    armor_proficiencies
    weapon_proficiencies
    skill_proficiencies
    features_level1
    subclass
  ].freeze

  def self.coerce_hash(h)
    return {} unless h.is_a?(Hash)

    h.deep_symbolize_keys
  end

  def self.missing_required(h)
    sym = coerce_hash(h)
    REQUIRED_ROOT_KEYS.reject { |k| sym.key?(k) }
  end

  def self.validate!(h)
    missing = missing_required(h)
    return true if missing.empty?

    raise ArgumentError,
          "klasses.rules inválido: faltam chaves obrigatórias #{missing.inspect} " \
          "(veja KlassDbRulesContract::REQUIRED_ROOT_KEYS e rake class_rules:dump_sample)"
  end

  def self.validate_loose(h)
    missing = missing_required(h)
    missing_rec = (RECOMMENDED_ROOT_KEYS - coerce_hash(h).keys)
    { missing_required: missing, missing_recommended: missing_rec }
  end
end
