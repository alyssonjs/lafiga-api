# frozen_string_literal: true

require 'rails_helper'

# Cobre os fixes B7.1, B7.2 e B7.3 do relatorio de auditoria de steps:
#   B7.1: per_level[N] era SUBSTITUIDO; PATCH parcial perdia feat/expertise/etc.
#   B7.2: spell_selections era SUBSTITUIDO; PATCH so com `cantrips` zerava
#         `known`/`prepared`/`spellbook` salvos previamente.
#   B7.3: progressionSubLevel hardcoded=2; usuario nivel 7 abria step e
#         caia na tab do nivel 2.
RSpec.describe CharacterSheetEdits::ProgressionEditService do
  let(:user) { create(:user) }
  let(:character) { create(:character, user: user, status: :active) }
  let(:race) { create(:race) }
  let(:sub_race) { create(:sub_race, race: race) }
  let(:klass) { create(:klass, hit_die: 8) }
  let!(:sheet) do
    create(:sheet, character: character, race: race, sub_race: sub_race,
                   con: 14, hp_max: 16, hp_current: 16, current_level: 4,
                   metadata: {
                     'class_choices' => {
                       'per_level' => {
                         '1' => { 'skills' => %w[Persuasao] },
                         '4' => {
                           'asi' => { 'mode' => 'plus2', 'ability1' => 'wis' },
                           'expertise' => %w[Persuasao],
                           'spells' => %w[bless]
                         }
                       }
                     },
                     'spell_selections' => {
                       'cantrips' => %w[guidance],
                       'known' => %w[bless cure_wounds],
                       'spellbook' => [],
                       'prepared' => %w[bless]
                     }
                   })
  end
  let!(:sheet_klass) { create(:sheet_klass, sheet: sheet, klass: klass, level: 4) }

  describe 'B7.1 — per_level[N] preserva subkeys nao incluidas no PATCH' do
    it 'PATCH so com `hp` mantem feat/expertise/spells/asi anteriores' do
      svc = described_class.new(character: character, level: 4, data: {
        'levelChoice' => { 'hp' => 6 }
      })
      svc.call
      sheet.reload

      row4 = sheet.metadata.dig('class_choices', 'per_level', '4')
      expect(row4['hp']).to eq(6)
      expect(row4['expertise']).to eq(%w[Persuasao])
      expect(row4['spells']).to eq(%w[bless])
      expect(row4['asi']).to include('ability1' => 'wis', 'mode' => 'plus2')
    end

    it 'PATCH com chave nova adiciona sem perder antigas' do
      svc = described_class.new(character: character, level: 4, data: {
        'levelChoice' => { 'feat' => 'observador' }
      })
      svc.call
      sheet.reload

      row4 = sheet.metadata.dig('class_choices', 'per_level', '4')
      expect(row4['feat']).to eq('observador')
      expect(row4['expertise']).to eq(%w[Persuasao])
      expect(row4['asi']).to be_present
    end
  end

  describe 'B7.2 — spell_selections preserva sub-abas nao incluidas no PATCH' do
    it 'PATCH so com `cantrips` mantem known/prepared salvos' do
      svc = described_class.new(character: character, level: 4, data: {
        'spellSelections' => { 'cantrips' => %w[guidance light] }
      })
      svc.call
      sheet.reload

      sel = sheet.metadata['spell_selections']
      expect(sel['cantrips']).to eq(%w[guidance light])
      expect(sel['known']).to eq(%w[bless cure_wounds])
      expect(sel['prepared']).to eq(%w[bless])
    end

    it 'PATCH com [] explicito zera apenas a sub-aba mencionada' do
      svc = described_class.new(character: character, level: 4, data: {
        'spellSelections' => { 'prepared' => [] }
      })
      svc.call
      sheet.reload

      sel = sheet.metadata['spell_selections']
      expect(sel['prepared']).to eq([])
      expect(sel['cantrips']).to eq(%w[guidance])
      expect(sel['known']).to eq(%w[bless cure_wounds])
    end
  end

  describe 'B7.3 — read.progressionSubLevel reflete current_level' do
    it 'devolve current_level (4) ao inves de 2 hardcoded' do
      out = described_class.new(character: character, data: {}).read
      expect(out['progressionSubLevel']).to eq(4)
    end

    it 'minimo 2 (current_level=1 nao faz sentido para progression)' do
      sheet.update!(current_level: 1)
      out = described_class.new(character: character.reload, data: {}).read
      expect(out['progressionSubLevel']).to eq(2)
    end
  end

  describe 'ZE3 — recompute hp_max em qualquer Δ CON (ASI mesmo nivel ou level-up)' do
    let(:asi_klass) { create(:klass, hit_die: 8, name: 'Fighter ASI') }
    let!(:asi_char) { create(:character, user: user, status: :active) }
    let!(:asi_sheet) do
      create(:sheet, character: asi_char, race: race, sub_race: sub_race,
                     str: 14, dex: 12, con: 14, int: 10, wis: 10, cha: 10,
                     hp_max: 22, hp_current: 22, current_level: 4,
                     metadata: {
                       'base_ability_scores' => { 'str' => 14, 'dex' => 12, 'con' => 14, 'int' => 10, 'wis' => 10, 'cha' => 10 },
                       'race_bonuses_applied' => {},
                       'ability_scores_include_all_increments' => true,
                       'class_choices' => { 'per_level' => { '1' => {}, '2' => {}, '3' => {}, '4' => {} } }
                     })
    end
    let!(:asi_sk) { create(:sheet_klass, sheet: asi_sheet, klass: asi_klass, level: 4) }

    it 'recomputa hp_max ao editar ASI no MESMO nivel mudando CON (+2 con)' do
      old_hp_max = asi_sheet.hp_max
      old_con = asi_sheet.con

      svc = described_class.new(character: asi_char.reload, level: 4, data: {
        'levelChoice' => { 'asi' => { 'mode' => 'plus2', 'ability1' => 'con' } }
      })
      svc.call
      asi_sheet.reload

      expect(asi_sheet.con).to eq(old_con + 2) # ASI aplicado
      expect(asi_sheet.hp_max).not_to eq(old_hp_max) # hp_max recomputado
      # CON mod foi 2 -> 3 (+1 por nivel = +4 niveis = +4 hp esperado)
      expect(asi_sheet.hp_max).to be > old_hp_max
    end

    it 'NAO recomputa hp_max quando ASI nao afeta CON (ex: ability1=str)' do
      old_hp_max = asi_sheet.hp_max

      svc = described_class.new(character: asi_char.reload, level: 4, data: {
        'levelChoice' => { 'asi' => { 'mode' => 'plus2', 'ability1' => 'str' } }
      })
      svc.call
      asi_sheet.reload

      expect(asi_sheet.hp_max).to eq(old_hp_max)
      expect(asi_sheet.str).to eq(16)
    end
  end

  describe 'G7.5 — invoca LevelUpGuardService em level-up real' do
    it 'NAO chama guard quando target_level <= pre_apply_level (edita per_level existente)' do
      # Cenario base: char ja esta no nivel 4 (sheet_klass.level = 4). Editar
      # per_level[4] nao precisa re-validar guard.
      expect(LevelUpGuardService).not_to receive(:call)

      svc = described_class.new(character: character, level: 4, data: {
        'levelChoice' => { 'hp' => 8 }
      })
      svc.call
    end

    it 'chama guard quando target_level > pre_apply_level (level-up real)' do
      # Sheet comeca no nivel 3; PATCH leva ao nivel 5 (level-up real).
      sheet_klass.update!(level: 3)
      sheet.update!(current_level: 3)

      expect(LevelUpGuardService).to receive(:call).and_call_original

      svc = described_class.new(character: character.reload, level: 5, data: {
        'levelChoice' => { 'level' => 5, 'hp' => 5 }
      })
      svc.call
    end

    it 'force: true pula o guard mesmo em level-up real' do
      sheet_klass.update!(level: 3)
      sheet.update!(current_level: 3)

      expect(LevelUpGuardService).not_to receive(:call)

      svc = described_class.new(character: character.reload, level: 5, force: true, data: {
        'levelChoice' => { 'level' => 5, 'hp' => 5 }
      })
      svc.call
    end

    it 'rollback completo + requires_confirmation quando guard falha' do
      sheet_klass.update!(level: 3)
      sheet.update!(current_level: 3)

      guard_double = double('GuardResult', success?: false,
                                            errors: double(full_messages: ['Falta escolher Estilo de Luta no nivel 1']))
      allow(LevelUpGuardService).to receive(:call).and_return(guard_double)

      pre_meta = sheet.metadata.deep_dup
      svc = described_class.new(character: character.reload, level: 5, data: {
        'levelChoice' => { 'level' => 5, 'hp' => 5 }
      })
      result = svc.call
      sheet.reload

      # Rollback: per_level[5] NAO foi gravado, level NAO subiu
      expect(sheet.metadata.dig('class_choices', 'per_level', '5')).to be_nil
      expect(sheet.sheet_klasses.maximum(:level)).to eq(3)
      expect(sheet.metadata['class_choices']['per_level']).to eq(pre_meta.dig('class_choices', 'per_level'))

      # Front recebe requires_confirmation com a razao do bloqueio
      expect(result.requires_confirmation).to be_present
      expect(result.requires_confirmation[:reason]).to include('Estilo de Luta')
      expect(result.warnings).to include(/Estilo de Luta/)
    end

    it 'ZE5 — guard interno raise (StandardError) faz rollback e loga error' do
      sheet_klass.update!(level: 3)
      sheet.update!(current_level: 3)
      sheet.reload

      allow(LevelUpGuardService).to receive(:call).and_raise(StandardError, 'catalogo ausente')
      # Outros componentes (ClassSummaryRebuilder etc.) tambem usam Rails.logger.error
      # ao tentar reconstruir summary com classe stub. Permitimos qualquer chamada
      # mas exigimos que ao menos uma seja a do guard rescue.
      allow(Rails.logger).to receive(:error)
      expect(Rails.logger).to receive(:error).with(/LevelUpGuardService raised/).at_least(:once)

      svc = described_class.new(character: character.reload, level: 5, data: {
        'levelChoice' => { 'level' => 5, 'hp' => 5 }
      })
      svc.call
      sheet.reload

      # ZE5: bug interno do guard agora faz rollback — nao deixa o per_level
      # passar sem ter sido validado. Se houver level-up genuino, o controller
      # respondera 500 com trace_id (via ZC4); o usuario nunca vai ver um
      # estado "subiu de nivel mas o guard nao validou".
      expect(sheet.metadata.dig('class_choices', 'per_level', '5')).to be_nil
    end
  end
end
