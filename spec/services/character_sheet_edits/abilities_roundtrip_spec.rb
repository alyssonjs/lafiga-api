# frozen_string_literal: true

require 'rails_helper'

# X4 do relatorio de auditoria de steps: roundtrip de ability scores em edit.
#
# Contexto: o bug do Observador (feat) revelou que o caminho de ability
# scores em edit e fragil — multiplas fontes (colunas, base_ability_scores,
# race_bonuses_applied, per_level[N].asi, per_level[N].feats[*].ability_bonuses,
# meta['feats'][*].ability_bonuses) precisam ficar SINCRONIZADAS.
#
# Este spec cobre cenarios end-to-end de drift:
#   X4.1 — read -> apply (mesmo valor) -> read devolve mesmo input
#   X4.2 — edit abilities -> edit race (bonus racial muda) -> read devolve total novo correto
#   X4.3 — edit abilities -> sync_ability_columns_from_metadata! preserva
#   X4.4 — multiplos edits sequenciais nao acumulam ASI/feat increments duas vezes
RSpec.describe 'AbilitiesEditService — X4 roundtrip cross-step', type: :service do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user, status: :active) }
  let(:race) { create(:race) }
  let(:sub_race) { create(:sub_race, race: race) }
  let!(:sheet) do
    create(:sheet,
      character: character, race: race, sub_race: sub_race,
      str: 13, dex: 14, con: 17, int: 10, wis: 10, cha: 10,
      hp_max: 40, hp_current: 40, current_level: 4,
      metadata: {
        'base_ability_scores' => { 'str' => 13, 'dex' => 14, 'con' => 15, 'int' => 10, 'wis' => 10, 'cha' => 10 },
        'race_bonuses_applied' => { 'con' => 2 },
        'ability_scores_include_all_increments' => true
      }
    )
  end
  let!(:sheet_klass) { create(:sheet_klass, sheet: sheet, level: 4) }

  describe 'X4.1 — read => apply (mesmo input) => read e idempotente' do
    it 'aplicar exatamente o que read devolveu nao muda nada' do
      svc = CharacterSheetEdits::AbilitiesEditService.new(character: character, data: {})
      first_read = svc.read.deep_dup

      CharacterSheetEdits::AbilitiesEditService.new(character: character.reload, data: first_read).call

      second_read = CharacterSheetEdits::AbilitiesEditService.new(character: character.reload, data: {}).read
      expect(second_read).to eq(first_read)
    end
  end

  describe 'X4.2 — edit abilities + ASI no per_level: total nao drifta' do
    it 'reflete corretamente base + racial + ASI no total da coluna' do
      sheet.update!(metadata: sheet.metadata.merge(
        'class_choices' => {
          'per_level' => {
            '4' => { 'asi' => { 'mode' => 'plus2', 'ability1' => 'str' } }
          }
        }
      ))
      CharacterSheetSummaryService.sync_ability_columns_from_metadata!(sheet.reload)

      sheet.reload
      expect(sheet.str).to eq(15) # 13 base + 2 ASI

      # Agora editar STR base de 13 -> 14: total deve virar 14 + 2 ASI = 16
      CharacterSheetEdits::AbilitiesEditService.new(character: character.reload, data: {
        'abilityScores' => { 'str' => 14, 'dex' => 14, 'con' => 15, 'int' => 10, 'wis' => 10, 'cha' => 10 }
      }).call

      sheet.reload
      expect(sheet.str).to eq(16)

      # E read devolve a base 14 (nao o total 16)
      out = CharacterSheetEdits::AbilitiesEditService.new(character: character.reload, data: {}).read
      expect(out['abilityScores']['str']).to eq(14)
    end
  end

  describe 'X4.3 — sync apos edit nao destroi base' do
    it 'multiplos sync_ability_columns_from_metadata! sao idempotentes' do
      CharacterSheetEdits::AbilitiesEditService.new(character: character, data: {
        'abilityScores' => { 'str' => 18, 'dex' => 14, 'con' => 15, 'int' => 10, 'wis' => 10, 'cha' => 10 }
      }).call

      sheet.reload
      first_str = sheet.str

      3.times { CharacterSheetSummaryService.sync_ability_columns_from_metadata!(sheet.reload) }

      sheet.reload
      expect(sheet.str).to eq(first_str) # nao acumulou racial 3 vezes
      expect(sheet.con).to eq(17) # 15 base + 2 racial (NAO 15 + 2 + 2 + 2 + 2)
    end
  end

  describe 'X4.4 — feat com ability_bonuses (Observador-style) NAO duplica' do
    it 'aplica feat e re-edita abilities sem dobrar o bonus do feat' do
      sheet.update!(metadata: sheet.metadata.merge(
        'feats' => [{
          'name' => 'Observador',
          'ability_bonuses' => { 'wis' => 1, 'int' => 1 }
        }]
      ))
      CharacterSheetSummaryService.sync_ability_columns_from_metadata!(sheet.reload)

      sheet.reload
      expect(sheet.wis).to eq(11) # 10 base + 1 feat
      expect(sheet.int).to eq(11) # 10 base + 1 feat

      # Edit abilities mantendo base (deveria ser no-op no total)
      CharacterSheetEdits::AbilitiesEditService.new(character: character.reload, data: {
        'abilityScores' => { 'str' => 13, 'dex' => 14, 'con' => 15, 'int' => 10, 'wis' => 10, 'cha' => 10 }
      }).call

      sheet.reload
      expect(sheet.wis).to eq(11) # ainda 10 base + 1 feat (NAO 12, NAO 13)
      expect(sheet.int).to eq(11)

      # Edit subindo INT base 10 -> 12: total deve ser 13 (12 base + 1 feat)
      CharacterSheetEdits::AbilitiesEditService.new(character: character.reload, data: {
        'abilityScores' => { 'str' => 13, 'dex' => 14, 'con' => 15, 'int' => 12, 'wis' => 10, 'cha' => 10 }
      }).call

      sheet.reload
      expect(sheet.int).to eq(13)
      expect(sheet.wis).to eq(11) # outras nao afetadas
    end
  end
end
