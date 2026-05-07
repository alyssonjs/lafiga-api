# frozen_string_literal: true

require 'rails_helper'

# BDD Fase 4 — Aplicação dos talentos NA FICHA DE PERSONAGEM.
# -------------------------------------------------------------
# Para cada feat de `FeatRules::RULES`, valida que o efeito declarado
# (ability_bonuses, proficiency_bonuses) é integrado ao
# `CharacterSheetSummaryService` e portanto aparece na ficha.
#
# Cobre 4 surfaces:
#   1. abilities[:scores]          — half-feats com +1/+2 atributo
#   2. proficiencies[:skills][:feat] — feats que dão perícias
#   3. proficiencies[:weapons]     — feats que dão armas
#   4. proficiencies[:armor]       — feats que dão armaduras
#
# NÃO cobre nesta fase: special_rules de combate (HP/speed/AC/iniciativa) —
# esses ficam para um spec dedicado a FeatProducer / combat modifiers.
RSpec.describe 'FeatRules — integração na ficha (Fase 4 surfaces 1-4)', type: :service do
  # =====================================================================
  #  Tabela de efeitos esperados por feat (única fonte de verdade do spec)
  # =====================================================================
  # Cada entry mapeia feat_id → expected hash com 4 chaves possíveis:
  #   :abilities  → Hash { str: N, dex: N, ... } esperado em scores ACIMA do baseline
  #   :skills     → Array de skill names que devem aparecer em skills[:feat]
  #   :weapons    → Array (ou condição) que devem aparecer em proficiencies[:weapons]
  #   :armor      → Array que devem aparecer em proficiencies[:armor]
  #   :tools      → Array que devem aparecer em proficiencies[:tools]
  #
  # Para feats com `choose:`, especificamos `:choices` com a escolha simulada.
  FEAT_EXPECTATIONS = {
    # half-feats
    'observador' => {
      abilities: { wis: 1, int: 1 },
      skills: ['Percepção']
    },
    'duravel' => {
      abilities: { con: 1 }
    },
    'atleta' => {
      abilities: { str: 1 },          # escolha STR
      choices: { 'ability' => 'str' }
    },
    # NOTA: duelista_defensivo, sorrateiro e lider_inspirador NÃO são half-feats
    # no PHB (sem +1 atributo). Aplicação direta — sem efeito visível em scores.
    # Mantidos no spec "pure_special_feats" abaixo.
    'mente_agucada' => {
      abilities: { int: 1 }
    },
    'ator' => {
      abilities: { cha: 1 }
    },

    # feats com proficiency_bonuses (skills)
    'perito' => {
      skills: %w[Acrobacia Arcanismo Atletismo],
      choices: { 'proficiencies' => %w[Acrobacia Arcanismo Atletismo] }
    },

    # feats com armor proficiency
    'protecao_leve' => {
      abilities: { str: 1 },          # escolha STR
      armor: ['leve'],
      choices: { 'ability' => 'str' }
    },
    'protecao_moderada' => {
      abilities: { str: 1 },
      armor: ['média', 'escudos']
    },
    'protecao_pesada' => {
      abilities: { str: 1 },
      armor: ['pesada']
    },

    # PHB Weapon Master — `choose:` aninhado em `weapons:` resolvido na Fase 5D
    # via `FeatRules.resolve_nested_proficiency_choice`.
    'especialista_em_armas' => {
      weapons: %w[arma_marcial],   # 1 pick para validar (PHB permite 4)
      choices: { 'proficiencies' => %w[arma_marcial] }
    },

    # FASE 2 — feats novos do PHB
    'especialista_em_briga' => {
      abilities: { str: 1 },
      choices: { 'ability' => 'str' },
      weapons: ['armas improvisadas']
    },
    'maestria_em_armadura_pesada' => {
      abilities: { str: 1 }
    }
  }.freeze

  # =====================================================================
  #  Helpers de setup (sheet "uber" reutiliza padrão do all_feats spec)
  # =====================================================================
  def build_uber_sheet
    role = Role.find_or_create_by!(name: 'player')
    user = User.create!(
      email: "fsi_#{SecureRandom.hex(4)}@example.com",
      username: "fsi#{SecureRandom.hex(4)}",
      password: 'password1',
      password_confirmation: 'password1',
      role_id: role.id
    )
    character = Character.create!(user: user, name: 'Spec Sheet Integration', background: 'Test')
    race = Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' }
    sub_race = SubRace.find_or_create_by!(race_id: race.id, api_index: 'standard') { |s| s.name = 'Humano Padrão' }
    sheet = Sheet.create!(
      character: character,
      race: race, sub_race: sub_race,
      str: 14, dex: 14, con: 14, int: 14, wis: 14, cha: 14,
      hp_max: 50, hp_current: 50,
      metadata: {
        'class_summary' => {
          'spellcasting' => { 'ability' => 'INT', 'preparation' => 'prepared' },
          'armor_proficiencies' => ['leve'],
          'weapon_proficiencies' => ['arma_simples'],
          'skills' => [],
          'tools' => []
        },
        'base_ability_scores' => {
          'str' => 14, 'dex' => 14, 'con' => 14, 'int' => 14, 'wis' => 14, 'cha' => 14
        }
        # NÃO setamos `ability_scores_include_all_increments: true`. Quando essa
        # flag está presente, `build_abilities` usa as COLUNAS direto (autoritative
        # mode) e não recalcula somando metadata['feats']. Como aplicamos feat
        # DEPOIS de criar a sheet, as colunas ficam stale e o teste falha
        # falsamente. Sem a flag, o build_abilities cai no caminho de soma
        # explícita (base + race + asi + feat).
      }
    )
    klass = Klass.find_or_create_by!(api_index: 'fighter') do |k|
      k.name = 'Guerreiro'; k.hit_die = 10; k.subclass_level = 3
    end
    SheetKlass.create!(sheet: sheet, klass: klass, level: 1)
    sheet
  end

  def assign_feat_and_summary(sheet, feat_id, choices)
    cmd = FeatAssignmentService.call(sheet: sheet, feat_id: feat_id, level_gained: 1, choices: choices)
    expect(cmd).to be_present, "FeatAssignmentService('#{feat_id}') retornou nil"

    summary_cmd = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
    expect(summary_cmd.success?).to be(true), -> { summary_cmd.errors.full_messages.join('; ') rescue summary_cmd.inspect }
    summary_cmd.result
  end

  # =====================================================================
  #  Specs gerados pela tabela
  # =====================================================================
  FEAT_EXPECTATIONS.each do |feat_id, expected|
    describe "feat \"#{feat_id}\"" do
      # Skip se o feat não existe (Fase 3 removeu alguns)
      let(:feat_in_rules) { FeatRules::RULES.key?(feat_id) }
      let(:choices) { expected[:choices] || {} }
      let(:sheet) { build_uber_sheet }

      it "feat existe em FeatRules::RULES" do
        expect(feat_in_rules).to be(true), "feat '#{feat_id}' não está em RULES"
      end

      if expected[:abilities]
        it "ability_bonuses do feat #{expected[:abilities].inspect} aparecem em summary[:abilities][:scores]" do
          base_scores = { str: sheet.str, dex: sheet.dex, con: sheet.con,
                          int: sheet.int, wis: sheet.wis, cha: sheet.cha }
          summary = assign_feat_and_summary(sheet, feat_id, choices)
          actual = summary[:abilities][:scores]

          expected[:abilities].each do |k, bonus|
            expect(actual[k]).to eq(base_scores[k] + bonus),
              "feat '#{feat_id}' deveria adicionar #{bonus} ao #{k.upcase}.\n" \
              "  base=#{base_scores[k]}, esperado=#{base_scores[k] + bonus}, atual=#{actual[k]}"
          end
        end
      end

      if expected[:skills]
        it "proficiency_bonuses.skills aparecem em summary[:proficiencies][:skills][:feat]" do
          summary = assign_feat_and_summary(sheet, feat_id, choices)
          feat_skills = Array(summary.dig(:proficiencies, :skills, :feat)).map(&:to_s)

          expected[:skills].each do |skill|
            expect(feat_skills).to include(skill),
              "feat '#{feat_id}' deveria adicionar '#{skill}' a skills[:feat]. Atual: #{feat_skills.inspect}"
          end
        end
      end

      if expected[:weapons]
        it "proficiency_bonuses.weapons aparecem em summary[:proficiencies][:weapons]" do
          summary = assign_feat_and_summary(sheet, feat_id, choices)
          weapons = Array(summary.dig(:proficiencies, :weapons)).map(&:to_s)

          expected[:weapons].uniq.each do |weapon|
            expect(weapons).to include(weapon),
              "feat '#{feat_id}' deveria adicionar '#{weapon}' a proficiencies.weapons. Atual: #{weapons.inspect}"
          end
        end
      end

      if expected[:armor]
        it "proficiency_bonuses.armor aparecem em summary[:proficiencies][:armor]" do
          summary = assign_feat_and_summary(sheet, feat_id, choices)
          armor = Array(summary.dig(:proficiencies, :armor)).map(&:to_s)

          expected[:armor].each do |a|
            expect(armor).to include(a),
              "feat '#{feat_id}' deveria adicionar '#{a}' a proficiencies.armor. Atual: #{armor.inspect}"
          end
        end
      end
    end
  end

  # =====================================================================
  #  Sanity: feats sem efeito visível na ficha (só special_rules) também
  #  podem ser aplicados sem quebrar o summary
  # =====================================================================
  describe 'feats com SOMENTE special_rules (não testados acima)' do
    pure_special_feats = %w[
      sentinela mestre_de_armas_duplas mobilidade atirador_eximio
      mestre_de_armas_grandes sortudo robusto conjurador_de_batalha
      especialista_em_besta mestre_do_escudo mestre_arma_de_haste
      duelista_montado atacante_selvagem explorador_de_cavernas curandeiro
      imobilizador conjurador_de_ritual sniper_magico magico_iniciante
      alerta investida_poderosa adepto_elemental matador_de_conjuradores
      adepto_marcial maestria_em_armadura_media
      duelista_defensivo sorrateiro lider_inspirador
    ].freeze

    pure_special_feats.each do |feat_id|
      it "summary não quebra quando '#{feat_id}' é aplicado" do
        next unless FeatRules::RULES.key?(feat_id)

        sheet = build_uber_sheet
        # Choice default: passar 1 manobra/cantrip/etc para feats com escolhas
        cantrips_default = ['cantrip-default']
        spells_default = ['spell-default']
        choices = {}
        feat = FeatRules::RULES[feat_id]
        choices['cantrips'] = cantrips_default if feat.dig(:cantrips, :choose) || feat.dig('cantrips', 'choose')
        choices['spells'] = spells_default if feat.dig(:spells, :choose) || feat.dig('spells', 'choose')
        if (mn = feat.dig(:special_rules, :maneuvers, :choose))
          choices['maneuvers'] = Array.new(mn.to_i) { |i| "maneuver-#{i}" }
        end

        summary = assign_feat_and_summary(sheet, feat_id, choices)
        expect(summary).to be_present
      end
    end
  end
end
