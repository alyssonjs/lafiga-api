# frozen_string_literal: true

require 'rails_helper'
require 'json'
require Rails.root.join('spec/support/imported_sheets_seeder')

# Phase 8 — Auditoria do mapeamento STATIC_CLASS_SUBCLASS_TO_API_INDEX (front)
#
# A Phase 4 (`subklass_slug_resolver_audit_spec`) garantiu que o backend não
# tenha aliases quebrados. Mas todo o pipeline do wizard começa NO FRONT, e o
# arquivo `front-lafiga/src/services/draftToProvisionPayload.ts` mantém uma
# tabela própria (`STATIC_CLASS_SUBCLASS_TO_API_INDEX`) que mapeia ids do mock
# estático (`cl-*:sub-*`) para api_indexes que vão para `POST /provision`.
#
# Na Phase 8 descobrimos 5 bugs do mesmo tipo nesse arquivo:
#   - 'cl-1:sub-1'  => 'caminho-do-furioso'   (DB tem 'berserker')
#   - 'cl-8:sub-1'  => 'oath_of_devotion'     (DB tem 'devotion')
#   - 'cl-9:sub-1'  => 'cacador'              (DB tem 'hunter')
#   - 'cl-11:sub-1' => 'linhagem-draconica'   (DB tem 'draconic')
#   - 'cl-12:sub-5' => 'evocation'            (DB tem 'escola-de-evocacao')
#
# Cada um quebrava o LevelUpService no nível em que a subclasse era escolhida
# pelo wizard (L3 para a maioria, L1/L2 para clérigo/druida/feiticeiro).
#
# Estratégia (importante porque o container Docker não monta o front-lafiga):
#   1. O snapshot autoritativo do mapping vive em
#      `api/spec/fixtures/front_static_subclass_mapping.json` — gerado pela
#      task `rake front:snapshot_subclass_mapping` (ou manualmente).
#   2. Este spec carrega o snapshot e prova que cada slug existe no DB seeded
#      OU resolve via SubklassSlugResolver.
#   3. O lado simétrico (verificar que o snapshot está em sincronia com o TS)
#      é coberto pelo Vitest `draftToProvisionPayload.canonical.bdd.test.ts`
#      (Phase 8) — a defesa front-side é fora do Docker.
#
# Se um bug futuro escapar nesse mapeamento, OU este spec OU o Vitest pegam.
RSpec.describe 'Front STATIC_CLASS_SUBCLASS_TO_API_INDEX → backend audit (Phase 8)' do
  before(:all) { ImportedSheetsSeeder.seed_all! }

  SNAPSHOT_PATH = Rails.root.join('spec/fixtures/front_static_subclass_mapping.json')

  let(:front_mappings) do
    raise "Snapshot ausente em #{SNAPSHOT_PATH}. Rode `rake front:snapshot_subclass_mapping`." unless SNAPSHOT_PATH.exist?

    JSON.parse(SNAPSHOT_PATH.read)
  end

  let(:db_subklass_indexes) { SubKlass.pluck(:api_index).to_set }

  it 'snapshot do front está populado' do
    expect(front_mappings).to be_a(Hash)
    expect(front_mappings.size).to be >= 20
  end

  it 'cada api_index do front existe no DB (com fallback no SubklassSlugResolver)' do
    broken = front_mappings.reject do |_from, raw_slug|
      resolved = SubklassSlugResolver.normalize(raw_slug)
      db_subklass_indexes.include?(resolved)
    end

    expect(broken).to be_empty, lambda {
      lines = broken.map do |from, raw_slug|
        prefix = raw_slug.split(/[-_]/).first
        suggestions = db_subklass_indexes.grep(/#{Regexp.escape(prefix)}/i).first(3)
        "  - #{from} => '#{raw_slug}' (não resolve; sugestões DB: #{suggestions.inspect})"
      end
      "Mapeamentos do front que NÃO chegam a um SubKlass real:\n#{lines.join("\n")}\n" \
        "Corrija em front-lafiga/src/services/draftToProvisionPayload.ts e atualize o snapshot."
    }
  end

  describe 'regressão dos 5 bugs corrigidos na Phase 8' do
    {
      'cl-1:sub-1'  => 'berserker',          # Bárbaro/Caminho do Furioso
      'cl-8:sub-1'  => 'devotion',           # Paladino/Devoção
      'cl-9:sub-1'  => 'hunter',             # Ranger/Caçador
      'cl-11:sub-1' => 'draconic',           # Sorcerer/Linhagem Dracônica
      'cl-12:sub-5' => 'escola-de-evocacao', # Wizard/Evocação
    }.each do |mock_id, expected_slug|
      it "#{mock_id} continua mapeando para '#{expected_slug}' (regressão)" do
        expect(front_mappings[mock_id]).to eq(expected_slug),
          "REGRESSÃO Phase 8: alguém alterou #{mock_id} de '#{expected_slug}' " \
          "para '#{front_mappings[mock_id]}' no front. Esse mock id deve apontar " \
          "para o api_index do SRD, não para o slug PT-BR (que não foi seedado)."

        expect(db_subklass_indexes).to include(expected_slug),
          "DB seeded não tem SubKlass '#{expected_slug}'. " \
          "Verifique se ImportedSheetsSeeder ou dnd:import o cria."
      end
    end
  end
end
