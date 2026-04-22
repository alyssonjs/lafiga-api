# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/imported_sheets_seeder')

# Phase 4 — Auditoria proativa de aliases do SubklassSlugResolver
#
# Por que isso existe:
# Já achamos 5 bugs do mesmo tipo no mesmo arquivo (todos com a mesma
# assinatura: alias mapeando PT-BR → slug SRD que NUNCA foi seedado no DB).
#
#   - Phase 3.0: 'escola-de-evocacao' => 'evocation'  (FIXED)
#   - Phase 4:   'berserker'         => 'caminho-do-furioso'  (FIXED)
#   - Phase 4:   'juramento-de-devocao' => 'oath_of_devotion'  (FIXED)
#   - Phase 4:   'juramento-dos-ancioes' => 'oath_of_the_ancients'  (FIXED)
#   - Phase 4:   'juramento-de-vinganca' => 'oath_of_vengeance'  (FIXED)
#
# Cada um quebrava o LevelUpService no nível em que a subclasse é escolhida,
# travando a evolução do personagem na produção.
#
# Esta spec é uma rede de proteção: para cada entry de `SubklassSlugResolver::SLUG`,
# o `value` (api_index esperado) DEVE existir no `canonical_indexes.json`
# (snapshot da DB de produção pós-`dnd:import` + `subclass_overrides`).
#
# Quando alguém adicionar um novo alias errado, este spec falha imediatamente
# com mensagem explícita.
RSpec.describe 'SubklassSlugResolver — alias audit (Phase 4)' do
  before(:all) { ImportedSheetsSeeder.seed_all! }

  let(:canonical_subklass_indexes) do
    canonical = JSON.parse(Rails.root.join('docs/canonical_indexes.json').read)
    canonical['subklasses'].values.flat_map(&:keys).to_set
  end

  let(:db_subklass_indexes) { SubKlass.pluck(:api_index).to_set }

  it 'cada alias mapeia para um api_index existente em canonical_indexes.json' do
    broken = SubklassSlugResolver::SLUG.reject do |_from, to|
      canonical_subklass_indexes.include?(to)
    end

    expect(broken).to be_empty, lambda {
      lines = broken.map do |from, to|
        suggestions = canonical_subklass_indexes.grep(/#{Regexp.escape(to.split(/[-_]/).first)}/i).first(3)
        "  - '#{from}' => '#{to}' (NÃO existe; talvez quis dizer: #{suggestions.inspect})"
      end
      "Aliases quebrados em SubklassSlugResolver::SLUG (api_index não existe no canonical):\n#{lines.join("\n")}"
    }
  end

  it 'cada alias mapeia para um api_index existente no test DB seeded' do
    # Defesa secundária: confirma que o seeder cria os api_indexes esperados.
    # Se canonical_indexes.json estiver dessincronizado da DB real, este spec
    # ainda assim protege a stack de testes.
    broken = SubklassSlugResolver::SLUG.reject do |_from, to|
      db_subklass_indexes.include?(to)
    end

    expect(broken).to be_empty,
      "Aliases quebrados (não estão no test DB pós-seed):\n  - #{broken.map { |f, t| "'#{f}' => '#{t}'" }.join("\n  - ")}"
  end
end
