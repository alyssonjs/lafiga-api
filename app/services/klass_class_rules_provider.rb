# frozen_string_literal: true

# Leitura de regras de classe a partir de `klasses.rules` (JSONB), com a mesma
# pós-processamento que `ClassRules.find` (ex.: saving_throws PT-BR).
# Formato esperado: ver `KlassDbRulesContract` e `bin/rails class_rules:dump_sample[fighter]`.
# Retorna nil se não houver registo, coluna em branco ou {} — o caller usa ClassRules em Ruby.
class KlassClassRulesProvider
  def self.call(api_index)
    new(api_index).call
  end

  def initialize(api_index)
    @api_index = api_index.to_s
  end

  def call
    k = Klass.find_by(api_index: @api_index)
    return nil unless k

    raw = k[:rules]
    return nil if raw.blank?

    rule = deep_symbolize(raw)
    rule = rule.deep_dup
    if rule[:saving_throws].present?
      rule[:saving_throws] = SavingThrowsCatalog.translate_array(rule[:saving_throws])
    end
    rule
  end

  private

  def deep_symbolize(obj)
    case obj
    when Hash
      obj.each_with_object({}) { |(key, val), h| h[key.to_sym] = deep_symbolize(val) }
    when Array
      obj.map { |e| deep_symbolize(e) }
    else
      obj
    end
  end
end
