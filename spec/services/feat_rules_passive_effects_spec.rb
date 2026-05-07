# frozen_string_literal: true

require 'rails_helper'

# BDD Fase 4B — Efeitos passivos dos talentos na ficha (HP, speed, AC).
# -----------------------------------------------------------------------
# Após a Fase 4A (ability_bonuses + proficiency_bonuses), este spec cobre
# os efeitos PASSIVOS que feats com `special_rules` declaram e que devem
# refletir em campos derivados do summary:
#
#   - Robusto              → hp_max +2/nível
#   - Mobilidade           → speed +10 ft (PHB Mobile = +10)
#   - Mestre de Armas Duplas → CA +1 (quando dual-wielding)
#
# Discrepâncias conhecidas que estes specs DETECTAM (capturando como pending):
#   1. `apply_feat_movement_bonuses` lê `special_rules['movement']` — mas YAML
#      do `mobilidade` declara como `special_rules['movement_modifiers']`.
#      O caminho atualmente funcional é via `Modifiers::Producers::FeatProducer`
#      que tem `mobilidade_speed_bonus` hardcoded com +10.
#   2. Feats novos da Fase 2/3 (alerta, maestria_em_armadura_pesada, etc.)
#      têm special_rules mas FeatProducer ainda não converte em modifiers.
RSpec.describe 'FeatRules — efeitos passivos na ficha (Fase 4B)', type: :service do
  let(:role) { Role.find_or_create_by!(name: 'player') }
  let(:user) do
    User.create!(
      email: "fpp_#{SecureRandom.hex(4)}@example.com",
      username: "fpp#{SecureRandom.hex(4)}",
      password: 'password1', password_confirmation: 'password1', role_id: role.id
    )
  end
  let(:race) { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }
  let(:sub_race) do
    SubRace.find_or_create_by!(race_id: race.id, api_index: 'standard') { |s| s.name = 'Humano Padrão' }
  end
  let(:klass) do
    Klass.find_or_create_by!(api_index: 'fighter') do |k|
      k.name = 'Guerreiro'; k.hit_die = 10; k.subclass_level = 3
    end
  end

  def build_sheet(level: 1, hp_max: nil, con: 14)
    character = Character.create!(user: user, name: "Spec Passive #{SecureRandom.hex(2)}", background: 'Test')
    sheet = Sheet.create!(
      character: character, race: race, sub_race: sub_race,
      str: 14, dex: 14, con: con, int: 12, wis: 12, cha: 12,
      hp_max: hp_max || (10 + ((con - 10) / 2)),
      hp_current: hp_max || (10 + ((con - 10) / 2)),
      current_level: level,
      metadata: {
        'class_summary' => {
          'armor_proficiencies' => ['leve', 'média', 'pesada'],
          'weapon_proficiencies' => ['arma_simples', 'arma_marcial'],
          'skills' => [], 'tools' => []
        },
        'base_ability_scores' => {
          'str' => 14, 'dex' => 14, 'con' => con,
          'int' => 12, 'wis' => 12, 'cha' => 12
        },
        'class_choices' => { 'per_level' => { '1' => { 'hp' => { 'dieResult' => 10, 'total' => 12 } } } }
      }
    )
    SheetKlass.create!(sheet: sheet, klass: klass, level: level)
    sheet
  end

  # =====================================================================
  #  Robusto (Tough) — hp_max +2/nível
  # =====================================================================
  describe 'Robusto — +2 PV por nível (retroativo)' do
    it 'metadata["feats"] contém entry com special_rules.dice.hit_points_per_level' do
      sheet = build_sheet
      FeatAssignmentService.call(sheet: sheet, feat_id: 'robusto', level_gained: 1, choices: {})
      sheet.reload

      entry = Array(sheet.metadata['feats']).find { |f| f['feat_id'] == 'robusto' }
      expect(entry).to be_present
      sr = entry['special_rules'] || {}
      hp_rule = sr.dig('dice_modifiers', 'hit_points_bonus') || sr.dig('dice', 'hit_points_per_level')
      expect(hp_rule).to be_present, "esperado entry de hp por nível em special_rules; veio #{sr.inspect}"
    end

    it 'FeatProducer gera modifier hp.max_per_level +2 (robusto)' do
      sheet = build_sheet(level: 5)
      FeatAssignmentService.call(sheet: sheet, feat_id: 'robusto', level_gained: 1, choices: {})
      sheet.reload

      producer = Modifiers::Producers::FeatProducer.new(sheet, context: {})
      mods = producer.produce
      hp_mod = mods.find { |m| m.target == 'hp.max_per_level' && m.source == 'feat:robusto' }
      expect(hp_mod).to be_present, "FeatProducer não gerou hp.max_per_level. Mods: #{mods.map(&:source).inspect}"
      expect(hp_mod.value).to eq(2)
    end

    it 'summary expõe hp_per_level_bonus = 2 quando robusto está aplicado' do
      sheet = build_sheet(level: 5)
      FeatAssignmentService.call(sheet: sheet, feat_id: 'robusto', level_gained: 1, choices: {})

      summary = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result
      # `summary[:modifiers][:hp_per_level_bonus]` consolida total via modifier_bag.sum_for('hp.max_per_level').
      total_bonus = summary.dig(:modifiers, :hp_per_level_bonus)
      expect(total_bonus.to_i).to eq(2),
        "summary[:modifiers][:hp_per_level_bonus] deveria ser 2 quando robusto aplicado. Atual: #{total_bonus.inspect}"
    end
  end

  # =====================================================================
  #  Mobilidade (Mobile) — speed +10 ft
  # =====================================================================
  describe 'Mobilidade — +10 ft de deslocamento (PHB Mobile)' do
    it 'FeatProducer.mobilidade_speed_bonus gera modifier speed +10' do
      sheet = build_sheet
      FeatAssignmentService.call(sheet: sheet, feat_id: 'mobilidade', level_gained: 1, choices: {})
      sheet.reload

      producer = Modifiers::Producers::FeatProducer.new(sheet, context: {})
      mods = producer.produce
      speed_mod = mods.find { |m| m.target == 'speed' && m.source == 'feat:mobilidade' }
      expect(speed_mod).to be_present
      expect(speed_mod.value).to eq(10)
    end

    it 'summary integra +10 ft de Mobile no movement.speed_ft' do
      sheet = build_sheet
      base_speed = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result[:movement][:speed_ft].to_i

      FeatAssignmentService.call(sheet: sheet, feat_id: 'mobilidade', level_gained: 1, choices: {})

      summary_with_feat = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result
      expect(summary_with_feat[:movement][:speed_ft].to_i).to eq(base_speed + 10),
        "Mobilidade deve adicionar +10 ft à velocidade. Base=#{base_speed}, atual=#{summary_with_feat[:movement][:speed_ft]}"
    end
  end

  # =====================================================================
  #  Resiliente — save proficiency grant
  # =====================================================================
  describe 'Resiliente — proficiência em save da ability escolhida' do
    it 'FeatProducer gera grant em save.{ability} para ability escolhida' do
      sheet = build_sheet
      FeatAssignmentService.call(
        sheet: sheet, feat_id: 'resiliente', level_gained: 1,
        choices: { 'saving_throws' => 'wis', 'ability' => 'wis' }
      )
      sheet.reload

      producer = Modifiers::Producers::FeatProducer.new(sheet, context: {})
      mods = producer.produce
      save_mod = mods.find { |m| m.target == 'save.wis' && m.source == 'feat:resiliente' }
      expect(save_mod).to be_present, "esperado grant em save.wis. Mods: #{mods.map(&:target).inspect}"
      expect(save_mod.op).to eq(:grant)
    end
  end

  # =====================================================================
  #  Atleta — proficiência em Atletismo
  # =====================================================================
  describe 'Atleta — proficiência em Atletismo (skill grant)' do
    it 'FeatProducer gera skill.atletismo.grant' do
      sheet = build_sheet
      FeatAssignmentService.call(
        sheet: sheet, feat_id: 'atleta', level_gained: 1, choices: { 'ability' => 'str' }
      )
      sheet.reload

      producer = Modifiers::Producers::FeatProducer.new(sheet, context: {})
      mods = producer.produce
      atl = mods.find { |m| m.target == 'skill.atletismo' && m.source == 'feat:atleta' }
      expect(atl).to be_present, "Atleta deveria gerar grant em skill.atletismo. Mods: #{mods.map(&:target).inspect}"
    end
  end

  # =====================================================================
  #  Mestre de Armas Duplas — +1 CA quando dual-wielding
  # =====================================================================
  describe 'Mestre de Armas Duplas — +1 CA condicional (dual-wielding)' do
    it 'FeatProducer NÃO gera modifier quando NÃO há equipamento' do
      sheet = build_sheet
      FeatAssignmentService.call(sheet: sheet, feat_id: 'mestre_de_armas_duplas', level_gained: 1, choices: {})
      sheet.reload

      producer = Modifiers::Producers::FeatProducer.new(sheet, context: {})
      mods = producer.produce
      ac_mod = mods.find { |m| m.target == 'ac' && m.source == 'feat:mestre_de_armas_duplas' }
      expect(ac_mod).to be_nil, 'sem dual_wielding ativo, não deve gerar modifier'
    end

    it 'FeatProducer gera +1 CA quando context indica dual_wielding' do
      sheet = build_sheet
      FeatAssignmentService.call(sheet: sheet, feat_id: 'mestre_de_armas_duplas', level_gained: 1, choices: {})
      sheet.reload

      context = {
        equipment: {
          equipped: {
            main_hand: { 'category' => 'weapons' },
            off_hand: { 'category' => 'weapons' }
          }
        }
      }
      producer = Modifiers::Producers::FeatProducer.new(sheet, context: context)
      mods = producer.produce
      ac_mod = mods.find { |m| m.target == 'ac' && m.source == 'feat:mestre_de_armas_duplas' }
      expect(ac_mod).to be_present, 'com dual-wielding, deveria gerar +1 CA. Mods: ' \
                                    "#{mods.map { |m| [m.target, m.source] }.inspect}"
      expect(ac_mod.value).to eq(1)
    end
  end

  # =====================================================================
  #  Fase 5 — FeatProducer estendido (Alerta, HAM, Shield Master)
  # =====================================================================
  describe 'FeatProducer Fase 5 — feats combat-aware' do
    it 'Alerta — converte em modifier initiative +5' do
      sheet = build_sheet
      FeatAssignmentService.call(sheet: sheet, feat_id: 'alerta', level_gained: 1, choices: {})
      producer = Modifiers::Producers::FeatProducer.new(sheet.reload, context: {})
      mods = producer.produce
      ini_mod = mods.find { |m| m.target == 'initiative' && m.source == 'feat:alerta' }
      expect(ini_mod).to be_present
      expect(ini_mod.value).to eq(5)
    end

    it 'Maestria em Armadura Pesada — converte em damage_resistance.bps_nonmagical -3 (predicate wearing_heavy_armor)' do
      sheet = build_sheet
      FeatAssignmentService.call(
        sheet: sheet, feat_id: 'maestria_em_armadura_pesada', level_gained: 1, choices: {}
      )
      producer = Modifiers::Producers::FeatProducer.new(sheet.reload, context: {})
      mods = producer.produce
      dr_mod = mods.find { |m| m.target == 'damage_resistance.bps_nonmagical' && m.source == 'feat:maestria_em_armadura_pesada' }
      expect(dr_mod).to be_present
      expect(dr_mod.value).to eq(3)
      expect(dr_mod.predicate).to include('condition' => 'wearing_heavy_armor')
    end

    it 'Mestre do Escudo — gera save.dex modifier APENAS quando escudo equipado' do
      sheet = build_sheet
      FeatAssignmentService.call(sheet: sheet, feat_id: 'mestre_do_escudo', level_gained: 1, choices: {})

      # Sem escudo equipado → não gera modifier
      no_shield = Modifiers::Producers::FeatProducer.new(sheet.reload, context: {})
      mods_no_shield = no_shield.produce
      expect(mods_no_shield.find { |m| m.source == 'feat:mestre_do_escudo' }).to be_nil

      # Com escudo equipado → gera save.dex
      ctx_with_shield = { equipment: { equipped: { off_hand: { 'category' => 'shield' } } } }
      with_shield = Modifiers::Producers::FeatProducer.new(sheet.reload, context: ctx_with_shield)
      mods_with_shield = with_shield.produce
      save_mod = mods_with_shield.find { |m| m.target == 'save.dex' && m.source == 'feat:mestre_do_escudo' }
      expect(save_mod).to be_present
      expect(save_mod.predicate).to include('condition' => 'wearing_shield')
    end
  end
end
