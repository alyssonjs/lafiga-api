# Be sure to restart your server when you modify this file.

# Add new inflection rules using the following format. Inflections
# are locale specific, and you may define rules for as many different
# locales as you wish. All of these examples are active by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.plural /^(ox)$/i, '\1en'
#   inflect.singular /^(ox)en/i, '\1'
#   inflect.irregular 'person', 'people'
#   inflect.uncountable %w( fish sheep )
# end

# These inflection rules are supported but not enabled by default:
# ActiveSupport::Inflector.inflections(:en) do |inflect|
#   inflect.acronym 'RESTful'
# end

# O domínio da vila e da campanha é em português (09/10; L1.1): a tabela `regioes` é do `Regiao` e a `setores`, do
# `Setor` (o padrão daria `regiaos` e `setors`).
ActiveSupport::Inflector.inflections(:en) do |inflect|
  inflect.irregular 'regiao', 'regioes'
  inflect.irregular 'setor', 'setores'
end
