# frozen_string_literal: true

require 'rails_helper'

# BDD — Bug "70 vs 57 HP" reportado em PC nv 6 com Robusto.
#
# Cenário Ruric (Bárbaro Meio-Orc nv 6, Robusto):
#   - Backend gravava sheet.hp_max sem somar Robusto (ex.: 57)
#   - Front recalculava com Robusto (= 70)
#   - Resumo do personagem mostrava 70, ficha completa mostrava 57
#
# Causa raiz:
#   - LevelUpService somava RacialHpBonus mas NÃO FeatHpBonus
#   - SheetHpFromProgression.expected_max idem
#   - FeatAssignmentService não aplicava bônus retroativo de Robusto
#
# Fix (3 pontos):
#   1. FeatHpBonus.per_level_for_sheet helper (paralelo a RacialHpBonus)
#   2. expected_max + LevelUpService usam FeatHpBonus
#   3. FeatAssignmentService.apply_retroactive_hp_bonus_if_any soma +N×nível
#      ao hp_max quando Robusto (ou similar) é assignado.
RSpec.describe 'FeatHpBonus + bug 70 vs 57 (Robusto)', type: :service do
  let(:role) { Role.find_or_create_by!(name: 'player') }
  let(:user) do
    User.create!(email: "fhb_#{SecureRandom.hex(4)}@example.com",
                 username: "fhb#{SecureRandom.hex(4)}",
                 password: 'password1', password_confirmation: 'password1', role_id: role.id)
  end
  let(:race)     { Race.find_or_create_by!(api_index: 'half_orc') { |r| r.name = 'Meio-Orc' } }
  let(:sub_race) { SubRace.find_or_create_by!(race_id: race.id, api_index: 'meio_orc_default') { |s| s.name = 'Default' } }
  let(:klass) do
    Klass.find_or_create_by!(api_index: 'barbarian') do |k|
      k.name = 'Bárbaro'; k.hit_die = 12; k.subclass_level = 3
    end
  end

  def build_sheet_lvl(level: 6, hp_max: 57, con: 15)
    character = Character.create!(user: user, name: "Spec #{SecureRandom.hex(2)}", background: 'Test')
    sheet = Sheet.create!(character: character, race: race, sub_race: sub_race,
                          str: 19, dex: 13, con: con, int: 8, wis: 11, cha: 10,
                          hp_max: hp_max, hp_current: hp_max,
                          current_level: level,
                          metadata: {})
    SheetKlass.create!(sheet: sheet, klass: klass, level: level)
    sheet
  end

  describe 'FeatHpBonus.per_level_for_sheet' do
    it 'retorna 0 quando metadata sem feats' do
      sheet = build_sheet_lvl
      expect(FeatHpBonus.per_level_for_sheet(sheet)).to eq(0)
    end

    it 'retorna 2 quando Robusto está em metadata.feats' do
      sheet = build_sheet_lvl
      FeatAssignmentService.call(sheet: sheet, feat_id: 'robusto', level_gained: 1, choices: {})
      expect(FeatHpBonus.per_level_for_sheet(sheet.reload)).to eq(2)
    end

    it 'soma múltiplos feats com hp_per_level (futuramente, e.g. variantes)' do
      sheet = build_sheet_lvl
      sheet.update!(metadata: sheet.metadata.merge('feats' => [
        { 'feat_id' => 'robusto',
          'special_rules' => { 'dice_modifiers' => { 'hit_points_bonus' => { 'parameters' => { 'bonus_per_level' => 2 } } } } },
        { 'feat_id' => 'extra_tough',
          'special_rules' => { 'dice_modifiers' => { 'hit_points_bonus' => { 'parameters' => { 'bonus_per_level' => 1 } } } } }
      ]))
      expect(FeatHpBonus.per_level_for_sheet(sheet)).to eq(3)
    end
  end

  describe 'FeatAssignmentService — Robusto retroativo (caminho legacy)' do
    # `handle_immediate_special_rules` (existente, lê
    # special_rules[:dice][:hit_points_per_level] do FeatSpecialRulesService)
    # é o caminho que aplica +N×nível em sheet.hp_max ao assignment.
    it 'aplica +12 HP retroativos quando Robusto é assignado em PC nv 6' do
      sheet = build_sheet_lvl(level: 6, hp_max: 57, con: 15)
      expect(sheet.hp_max).to eq(57)

      FeatAssignmentService.call(sheet: sheet, feat_id: 'robusto', level_gained: 1, choices: {})
      sheet.reload

      expect(sheet.hp_max).to eq(57 + 12),
        "PHB: Robusto é retroativo (+2 PV × nível). Esperado 69, veio #{sheet.hp_max}"
    end

    it 'nv 1: aplica +2 ao hp_max (Robusto recém adquirido)' do
      sheet = build_sheet_lvl(level: 1, hp_max: 14, con: 14)
      FeatAssignmentService.call(sheet: sheet, feat_id: 'robusto', level_gained: 1, choices: {})
      expect(sheet.reload.hp_max).to eq(14 + 2)
    end

    it 'feat sem hp_per_level NÃO mexe em hp_max (Observador, Sortudo etc.)' do
      sheet = build_sheet_lvl(hp_max: 50, con: 16)
      FeatAssignmentService.call(sheet: sheet, feat_id: 'observador', level_gained: 1, choices: {})
      expect(sheet.reload.hp_max).to eq(50)
    end
  end

  describe 'SheetHpFromProgression.expected_max — inclui FeatHpBonus' do
    it 'expected_max para Bárbaro nv 6 com Robusto soma +12 do feat' do
      sheet = build_sheet_lvl(level: 6, hp_max: 57, con: 15)
      FeatAssignmentService.call(sheet: sheet, feat_id: 'robusto', level_gained: 1, choices: {})
      sheet.reload

      per_level = {
        '1' => { 'hp' => { 'total' => 14 } },  # 12 hd + 2 con
        '2' => { 'hp' => { 'total' =>  9 } },  # 7 + 2
        '3' => { 'hp' => { 'total' =>  9 } },
        '4' => { 'hp' => { 'total' =>  9 } },
        '5' => { 'hp' => { 'total' =>  9 } },
        '6' => { 'hp' => { 'total' =>  9 } }
      }
      expected = SheetHpFromProgression.expected_max(sheet, klass, 6, per_level)
      # per_level: 14 + 9*5 = 59 (sem feat) + 12 (Robusto) = 71
      expect(expected).to eq(14 + 9 * 5 + 12),
        "Esperado 71 (per_level 59 + Robusto +12). Veio #{expected}"
    end

    it 'expected_max sem Robusto soma só per_level (sem +12)' do
      sheet = build_sheet_lvl(level: 6, hp_max: 57, con: 15)
      per_level = { '1' => { 'hp' => { 'total' => 14 } } }
      (2..6).each { |lv| per_level[lv.to_s] = { 'hp' => { 'total' => 9 } } }

      expected = SheetHpFromProgression.expected_max(sheet, klass, 6, per_level)
      expect(expected).to eq(14 + 9 * 5),
        "Sem Robusto, expected_max = só per_level (59). Veio #{expected}"
    end
  end
end
