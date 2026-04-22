# Configuração do enforcement de escolhas obrigatórias (Kit 1.fix-autochoice / gap #6).
#
# Quando STRICT é true, LevelUpGuardService e AutoChoiceService NÃO preenchem
# silenciosamente escolhas faltantes (fighting_style, metamagic, invocations,
# pact_boon). Em vez disso:
#   - O guard reporta `missing` corretamente (deixando o front responsável)
#   - Ambos serviços emitem `Rails.logger.warn` indicando qual chave teria sido
#     auto-preenchida (visibilidade para auditoria)
#
# Default por ambiente:
#   - rspec  : true (decidido em LevelUpGuardService.strict_required_choices? via defined?(RSpec))
#   - dev    : false (compat até Kit 1.PoC.front migrar)
#   - prod   : false (compat — flip via env var quando front estiver pronto)
#
# Override via ENV: LAFIGA_STRICT_REQUIRED_CHOICES=true|false
#
# NOTA: o container roda com RAILS_ENV=development mesmo durante rspec,
# por isso a precedência final do gate vive no service (LevelUpGuardService),
# não aqui. Este initializer apenas seta o default de produção/dev.
#
# Migração planejada: depois de Kit 1.PoC.front + audit_choice_gaps zerado,
# tornar default `true` em todos ambientes e remover a flag.
Rails.application.config.x.lafiga ||= ActiveSupport::OrderedOptions.new
Rails.application.config.x.lafiga.strict_required_choices = ENV.fetch(
  'LAFIGA_STRICT_REQUIRED_CHOICES',
  'false'
).to_s.downcase == 'true'
