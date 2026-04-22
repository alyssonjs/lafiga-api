# frozen_string_literal: true

require 'rails_helper'

# Cobre os fixes B5.1/B5.2/B5.3 do relatorio de auditoria de steps:
#   B5.1: gravar `sheet.send(k=)` direto sumia em qualquer
#         `sync_ability_columns_from_metadata!` posterior.
#   B5.2: nao atualizava `meta['base_ability_scores']` -> drift permanente.
#   B5.3: `read` devolvia coluna (TOTAL) como se fosse base.
#
# Tambem mantem o invariante historico: HP_current preserva ratio quando CON
# total muda. Documentado em .cursor/skills/debug-character-sheet-gap.
RSpec.describe CharacterSheetEdits::AbilitiesEditService do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user, status: :active) }
  let(:race) { create(:race) }
  let(:sub_race) { create(:sub_race, race: race) }
  let!(:sheet) do
    create(:sheet,
      character: character, race: race, sub_race: sub_race,
      str: 12, dex: 14, con: 16, int: 10, wis: 10, cha: 10,
      hp_max: 30, hp_current: 15, current_level: 5,
      metadata: {
        'base_ability_scores' => { 'str' => 12, 'dex' => 14, 'con' => 14, 'int' => 10, 'wis' => 10, 'cha' => 10 },
        'race_bonuses_applied' => { 'con' => 2 },
        'ability_scores_include_all_increments' => true
      }
    )
  end
  let!(:sheet_klass) { create(:sheet_klass, sheet: sheet, level: 5) }

  describe '#apply! grava base + ressincroniza colunas (B5.1, B5.2)' do
    it 'persiste base_ability_scores e re-soma com race_bonuses_applied' do
      svc = described_class.new(character: character, data: {
        'abilityScores' => { 'str' => 13, 'dex' => 15, 'con' => 15, 'int' => 10, 'wis' => 10, 'cha' => 10 }
      })
      svc.call
      sheet.reload

      base = sheet.metadata['base_ability_scores']
      expect(base).to include('str' => 13, 'dex' => 15, 'con' => 15)

      # Colunas = base + race_bonuses (con+2). Race nao da DEX/STR aqui.
      expect(sheet.str).to eq(13)
      expect(sheet.dex).to eq(15)
      expect(sheet.con).to eq(17) # 15 + 2 racial
    end

    it 'preserva ratio HP_current quando CON TOTAL muda' do
      # base con vai de 14 -> 16 (com racial +2 = total 18, era 16)
      svc = described_class.new(character: character, data: {
        'abilityScores' => { 'str' => 12, 'dex' => 14, 'con' => 16, 'int' => 10, 'wis' => 10, 'cha' => 10 }
      })
      svc.call
      sheet.reload

      expect(sheet.con).to eq(18) # 16 + 2 racial
      expect(sheet.hp_current).to be > 0
      ratio = sheet.hp_current.to_f / sheet.hp_max
      expect(ratio).to be_within(0.1).of(0.5)
    end

    it 'nao mexe em HP quando CON total nao muda' do
      svc = described_class.new(character: character, data: {
        'abilityScores' => { 'str' => 13, 'dex' => 14, 'con' => 14, 'int' => 10, 'wis' => 10, 'cha' => 10 }
      })
      svc.call
      sheet.reload
      expect(sheet.hp_max).to eq(30)
      expect(sheet.hp_current).to eq(15)
      expect(sheet.con).to eq(16) # 14 + 2 racial = mesmo de antes
    end

    it 'roundtrip: edicao 1 nao e descartada por sync subsequente' do
      svc = described_class.new(character: character, data: {
        'abilityScores' => { 'str' => 18, 'dex' => 14, 'con' => 14, 'int' => 10, 'wis' => 10, 'cha' => 10 }
      })
      svc.call
      sheet.reload
      expect(sheet.str).to eq(18)

      # Simulate posterior re-sync (ex.: ProgressionEdit, FeatAssignment)
      CharacterSheetSummaryService.sync_ability_columns_from_metadata!(sheet)
      sheet.reload
      expect(sheet.str).to eq(18) # base persiste, sync nao destroi
    end
  end

  describe '#read devolve BASE (B5.3)' do
    it 'le base_ability_scores do meta (caminho authoritative)' do
      out = described_class.new(character: character, data: {}).read
      expect(out['abilityScores']).to eq(
        'str' => 12, 'dex' => 14, 'con' => 14, 'int' => 10, 'wis' => 10, 'cha' => 10
      )
    end

    it 'fallback legado: subtrai race_bonuses_applied das colunas quando meta nao tem base' do
      sheet.update!(metadata: {
        'race_bonuses_applied' => { 'con' => 2 },
        'ability_scores_include_all_increments' => true
      })
      out = described_class.new(character: character.reload, data: {}).read
      # Coluna con=16, racial=+2 -> base reconstruido = 14
      expect(out['abilityScores']['con']).to eq(14)
      expect(out['abilityScores']['str']).to eq(12) # sem racial em STR
    end
  end
end
