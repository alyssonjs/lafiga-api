#!/usr/bin/env ruby
# api/scripts/audit_class_coverage.rb
#
# Cross-references ClassRules + DB (Klass/SubKlass) and emits a markdown
# coverage matrix. Frontend mapper/UI columns are populated only when the
# script is invoked from the host (with HOST_REPO_ROOT pointing at the
# workspace root). When invoked inside the API container, those columns are
# left blank — the wrapper rake task captures stdout and pipes it back to
# `docs/CLASS_SHEET_COVERAGE.md` on the host.
#
# Run via:
#   docker exec lafiga_api bundle exec rake sheets:audit_coverage > docs/CLASS_SHEET_COVERAGE.md

require 'json'

HOST_ROOTS = [
  ENV['HOST_REPO_ROOT'],
  File.expand_path('../..', __dir__),
  File.expand_path('../../..', __dir__),
  '/workspace'
].compact

def find_repo_path(rel)
  HOST_ROOTS.each do |root|
    p = File.join(root, rel)
    return p if File.exist?(p)
  end
  nil
end

def slurp(path)
  path && File.exist?(path) ? File.read(path) : nil
end

def check_box(predicate)
  predicate ? '[x]' : '[ ]'
end

def na = 'n/a'

def main
  classes = Klass.order(:id).to_a
  mapper_src    = slurp(find_repo_path('front-lafiga/src/services/mappers/classDataFromApiSummary.ts'))
  sections_src  = slurp(find_repo_path('front-lafiga/src/app/components/ClassSections.tsx'))
  resources_src = slurp(find_repo_path('front-lafiga/src/app/components/ClassResourcesPanel.tsx'))
  fe_visible    = mapper_src && sections_src && resources_src

  rows = []
  classes.each do |klass|
    api_idx = klass.api_index.to_s
    subs = SubKlass.where(klass_id: klass.id).order(:id).to_a
    rule_known = api_idx.present? && (begin
      ClassRules.respond_to?(:apply) ? ClassRules.apply(klass_id: api_idx, level: 1, picks: {}).present? : false
    rescue StandardError
      false
    end)

    rows << {
      type: :class,
      api_index: api_idx,
      name: klass.name,
      classrules: rule_known,
      mapper: fe_visible ? mapper_src.match?(/['"]#{Regexp.escape(api_idx)}['"]/) : nil,
      ui_section: fe_visible ? sections_src.match?(/#{Regexp.escape(klass.name)}|#{api_idx}Section/i) : nil,
      ui_resources: fe_visible ? resources_src.match?(/#{Regexp.escape(klass.name)}|#{api_idx}/i) : nil,
    }

    subs.each do |sk|
      sub_idx = sk.api_index.to_s
      rows_json = (JSON.parse(sk.levels_json) rescue [])
      has_grants = rows_json.any? { |r| r.is_a?(Hash) && r['grants'].present? }
      rows << {
        type: :sub,
        klass_api_index: api_idx,
        api_index: sub_idx,
        name: sk.name,
        grants_in_levels_json: has_grants,
        ui_section: fe_visible ? (sections_src.include?(sub_idx) || sections_src.match?(/#{Regexp.escape(sk.name)}/i)) : nil,
      }
    end
  end

  out = []
  out << '# Cobertura da ficha por classe e subclasse'
  out << ''
  out << "_Gerado por `api/scripts/audit_class_coverage.rb` em #{Time.now.utc.iso8601}_"
  out << ''
  out << '## Como ler'
  out << ''
  out << '- **ClassRules**: `ClassRules.apply` retorna proficiências e features para a classe.'
  out << '- **Grants DB**: a subclasse tem grants (proficiências/features) carregadas no campo `levels_json`.'
  out << '- **Mapper**: `classDataFromApiSummary.ts` constrói `classData` para essa classe.'
  out << '- **UI Section**: `ClassSections.tsx` renderiza um painel dedicado.'
  out << '- **UI Resources**: `ClassResourcesPanel.tsx` mostra trackers de recurso.'
  out << ''
  out << '> **Nota:** colunas com `?` significam que o script foi executado dentro do container e não enxergou os arquivos do front-lafiga. Rode com `HOST_REPO_ROOT` apontando para a raiz do repo para hidratar essas colunas.'
  out << ''
  out << '| Classe / Subclasse | api_index | ClassRules | Grants DB | Mapper | UI Section | UI Resources |'
  out << '|---|---|---|---|---|---|---|'

  rows.each do |r|
    if r[:type] == :class
      out << "| **#{r[:name]}** | `#{r[:api_index]}` | #{check_box(r[:classrules])} | #{na} | #{cell(r[:mapper])} | #{cell(r[:ui_section])} | #{cell(r[:ui_resources])} |"
    else
      out << "| ↳ #{r[:name]} | `#{r[:api_index]}` | #{na} | #{check_box(r[:grants_in_levels_json])} | #{na} | #{cell(r[:ui_section])} | #{na} |"
    end
  end

  out << ''
  out << '## Próximas ações sugeridas'
  out << ''
  out << '- Para classes sem [x] em **ClassRules**: adicionar definição em `api/app/services/class_rules.rb`.'
  out << '- Para subclasses sem [x] em **Grants DB**: rodar `rake apply_subclass_overrides` ou adicionar overrides em `api/config/subclass_overrides.yml`.'
  out << '- Para classes sem [x] em **Mapper**: extender `front-lafiga/src/services/mappers/classDataFromApiSummary.ts` lendo `metadata.class_choices.per_level[N]`.'
  out << '- Para classes sem [x] em **UI Section**: adicionar componente em `front-lafiga/src/app/components/ClassSections.tsx`.'
  out << ''

  puts out.join("\n")
end

def cell(v)
  return '?' if v.nil?
  check_box(v)
end

main if defined?(Rake) || $PROGRAM_NAME == __FILE__
