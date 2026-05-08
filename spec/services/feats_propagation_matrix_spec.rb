# frozen_string_literal: true

require 'rails_helper'

# ----------------------------------------------------------------------------
# Matriz de cobertura: feat × entry-point.
#
# **Propósito.** Histórico do bug Perito (28/abr → 8/mai): o fix foi aplicado em
# `FeatRules.apply` mas o teste de regressão cobriu APENAS o caminho ASI no
# level-up. Variant Human L1 (provisioning + race_edit) ficou descoberto, mais
# fichas LEGADAS ficaram com `metadata.feats[].proficiency_bonuses` em formato
# RAW gravado no DB — um bug invisível por 10 dias.
#
# Esta matriz força CADA feat a passar pelos 4 entry-points conhecidos:
#   - :provisioning      — Variant Human L1 via CharacterProvisioningService
#   - :race_edit         — Variant Human L1 via RaceEditService
#   - :level_up_asi      — ASI nível 4 via ProgressionEditService
#   - :legacy_metadata   — pb RAW pré-2026-04-28 (testa fallback do aggregator)
#
# **Como adicionar feat novo:**
#
# ```ruby
# describe 'NomeDoFeat (descrição curta da forma)' do
#   include_examples 'feat propaga proficiencies para a ficha',
#     feat_id: 'slug_do_feat',
#     choices: { 'ability' => 'str', 'skillsAndTools' => [...] },  # payload do front
#     expects: {
#       skills:  ['Atletismo'],     # → proficiencies.skills.feat
#       tools:   ['Xilofone'],      # → proficiencies.tools
#       armor:   ['leve'],          # → proficiencies.armor
#       weapons: ['longsword'],     # → proficiencies.weapons
#       shields: true               # → proficiencies.armor inclui 'escudos'
#     },
#     # Opcional: limitar entry-points quando o feat não faz sentido em algum
#     # (ex.: feat sem proficiency_bonuses pode pular :legacy_metadata).
#     entry_points: %i[provisioning race_edit level_up_asi]
# end
# ```
#
# **Pré-requisitos do feat:** o helper usa atributos ≥13 em todos os scores
# (str=14, dex=14, con=14, int=14, wis=14, cha=14 após bônus racial), Mago L1
# (ou L4 para ASI), classe sem proficiência em armadura média/pesada — então
# feats com prereq `proficiencies: { armors: ['média'] }` (ex.: Proteção
# Pesada) só funcionam em chain (após `protecao_moderada`). Se quiser cobrir
# uma chain, adicione um helper específico no feat_propagation_helpers.rb.
# ----------------------------------------------------------------------------
RSpec.describe 'Feats: matriz de propagação para a ficha (regressão por entry-point)', type: :service do
  describe 'Perito (skills_or_tools)' do
    include_examples 'feat propaga proficiencies para a ficha',
      feat_id: 'perito',
      choices: { 'skillsAndTools' => ['Arcanismo', 'Investigação', 'Utensílios de Cozinheiro'] },
      expects: {
        skills: %w[Arcanismo Investigação],
        tools: ['Utensílios de Cozinheiro']
      }
  end

  describe 'Observador (skills fixos: Percepção)' do
    include_examples 'feat propaga proficiencies para a ficha',
      feat_id: 'observador',
      choices: { 'ability' => 'wis' },
      expects: {
        skills: %w[Percepção]
      },
      # Observador no Variant Human L1 inclui `ability` no choices; no
      # ASI level-up vai por featAbility — não precisamos do legacy_metadata
      # caso ele só tem skills fixos (não há `skills_or_tools` para virar RAW).
      entry_points: %i[provisioning race_edit level_up_asi]
  end

  describe 'Proteção Leve (armors fixo, sem prereq)' do
    # `protecao_leve`: prereq=∅, +1 FOR, armors=['leve']. Cobre o branch
    # `pb['armors']` do aggregator (linha 788 de character_sheet_summary_service).
    include_examples 'feat propaga proficiencies para a ficha',
      feat_id: 'protecao_leve',
      choices: {},
      expects: {
        armor: %w[leve]
      },
      entry_points: %i[provisioning race_edit level_up_asi]
  end

  describe 'Especialista em Briga (weapons fixos)' do
    # `especialista_em_briga` (Tavern Brawler): proficiência com armas
    # improvisadas. Cobre o branch `pb['weapons']` do aggregator.
    include_examples 'feat propaga proficiencies para a ficha',
      feat_id: 'especialista_em_briga',
      choices: { 'ability' => 'str' },
      expects: {
        weapons: ['armas improvisadas']
      },
      entry_points: %i[provisioning race_edit level_up_asi]
  end

  describe 'Especialista em Armas (weapons choose ANINHADO)' do
    # `especialista_em_armas`: prereq str≥13, +1 FOR/DES (choose), e
    # `proficiency_bonuses: { weapons: { choose: { amount: 4, options: ... } } }`.
    # Cobre o `resolve_nested_proficiency_choice` (Fase 5D) — sem ele, o nó
    # `weapons` ficaria como Hash bruto e o summary leria nada.
    include_examples 'feat propaga proficiencies para a ficha',
      feat_id: 'especialista_em_armas',
      choices: { 'ability' => 'str', 'proficiencies' => %w[longsword rapier shortsword scimitar] },
      expects: {
        weapons: %w[longsword rapier shortsword scimitar]
      },
      entry_points: %i[provisioning race_edit level_up_asi]
  end
end
