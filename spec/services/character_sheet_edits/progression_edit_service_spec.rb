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

    it 'para Mago, spellbook substitui known stale vindo do edit' do
      wizard = Klass.find_by(api_index: 'wizard') || create(:klass, api_index: 'wizard')
      sheet_klass.update!(klass: wizard)

      svc = described_class.new(character: character, level: 4, data: {
        'spellSelections' => {
          'known' => %w[spell_antiga outra_antiga],
          'spellbook' => %w[nova_1 nova_2],
          'prepared' => %w[nova_1]
        }
      })
      svc.call
      sheet.reload

      sel = sheet.metadata['spell_selections']
      expect(sel['spellbook']).to eq(%w[nova_1 nova_2])
      expect(sel['known']).to eq(%w[nova_1 nova_2])
      expect(sel['prepared']).to eq(%w[nova_1])
    end

    it 'para Mago, spellbook vazio tambem limpa known stale' do
      wizard = Klass.find_by(api_index: 'wizard') || create(:klass, api_index: 'wizard')
      sheet_klass.update!(klass: wizard)

      svc = described_class.new(character: character, level: 4, data: {
        'spellSelections' => {
          'known' => %w[spell_antiga],
          'spellbook' => [],
          'prepared' => []
        }
      })
      svc.call
      sheet.reload

      sel = sheet.metadata['spell_selections']
      expect(sel['spellbook']).to eq([])
      expect(sel['known']).to eq([])
      expect(sel['prepared']).to eq([])
    end

    it 'read respeita spell_selections explicitamente vazio em vez de reconstruir do banco' do
      stale_spell = create(:spell, level: 1)
      create(:sheet_known_spell, sheet_klass: sheet_klass, spell: stale_spell, source: 'class')
      sheet.update!(metadata: sheet.metadata.deep_merge(
        'spell_selections' => {
          'cantrips' => [],
          'known' => [],
          'spellbook' => [],
          'prepared' => []
        }
      ))

      out = described_class.new(character: character.reload, data: {}).read

      expect(out['spellSelections']).to eq(
        'cantrips' => [],
        'known' => [],
        'spellbook' => [],
        'prepared' => []
      )
    end

    it 'B7.4 — PATCH spellSelections regrava SheetKnownSpell (fonte do summary/catalog_by_id)' do
      caster = create(:klass, api_index: "b74_caster_#{SecureRandom.hex(4)}")
      cl = ClassLevel.create!(klass: caster, level: 4, prof_bonus: 2, ability_score_bonuses: 0)
      Spellcasting.create!(
        class_level: cl,
        level: 1,
        cantrips_known: 0,
        spells_known: 6,
        spell_slots: { '1' => 3 }.to_json
      )
      bless = create(:spell, name: 'Bless', level: 1, api_index: "b74_bless_#{SecureRandom.hex(3)}")
      stale = create(:spell, name: 'Stale B74', level: 1, api_index: "b74_stale_#{SecureRandom.hex(3)}")

      sheet_klass.update!(klass: caster)
      SheetKnownSpell.where(sheet_klass_id: sheet_klass.id).delete_all
      create(:sheet_known_spell, sheet_klass: sheet_klass, spell: stale, source: 'class')

      described_class.new(character: character, level: 4, data: {
        'spellSelections' => { 'known' => ['Bless'], 'cantrips' => [] }
      }).call

      ids = SheetKnownSpell.where(sheet_klass_id: sheet_klass.id).where(source: [nil, 'class', 'subclass']).pluck(:spell_id)
      expect(ids.uniq.sort).to eq([bless.id])
    end

    it 'B7.5 — sem level no construtor: progressionSubLevel no data aplica spellSelections' do
      # CharacterCreation persistStepToBackend historically omitía `level` no query;
      # o wizard envia progressionSubLevel + spellSelections + levelChoices.
      expect(
        described_class.new(character: character, data: {
          'progressionSubLevel' => 4,
          'spellSelections' => {
            'cantrips' => [],
            'known' => [],
            'spellbook' => [],
            'prepared' => []
          }
        }).call.warnings
      ).not_to include(/nivel ausente/)

      sheet.reload
      sel = sheet.metadata['spell_selections']
      expect(sel['known']).to eq([])
      expect(sel['prepared']).to eq([])
      expect(sel['cantrips']).to eq([])
    end

    it 'B7.5b — remocao na aba "Nivel 1" (target_level < 2) persiste e deleta row source=nil' do
      # Regressao do bug do Bardo (Ainor): o jogador removia um truque/magia
      # INICIAL (editando a aba "Nivel 1"), o front mandava `level: 1`, e o
      # apply! caia no early-return `warn!('nivel ausente')` ANTES de aplicar
      # spell_selections. A remocao era descartada com HTTP 200 e as magias
      # `source=nil` (deixadas pelo seed/auto-fill do LevelUpService) nunca eram
      # deletadas — reaparecendo na ficha via KnownSpellsAggregator.
      caster = create(:klass, api_index: "b75b_bard_#{SecureRandom.hex(4)}")
      ClassLevel.create!(klass: caster, level: 4, prof_bonus: 2, ability_score_bonuses: 0)
      allow(ClassRules).to receive(:find).and_call_original
      allow(ClassRules).to receive(:find).with(caster.api_index).and_return({
        feature_rules: { spellcasting: { mode: 'known' } },
        spellcasting: { preparation: 'known' }
      })

      keep    = create(:spell, name: 'Keep B75b',  level: 0, api_index: "b75b_keep_#{SecureRandom.hex(3)}")
      ghost   = create(:spell, name: 'Ghost B75b', level: 0, api_index: "b75b_ghost_#{SecureRandom.hex(3)}")

      sheet_klass.update!(klass: caster)
      SheetKnownSpell.where(sheet_klass_id: sheet_klass.id).delete_all
      create(:sheet_known_spell, sheet_klass: sheet_klass, spell: keep,  source: 'class')
      # A magia removida ficou com source=nil (assinatura do seed/auto-fill).
      create(:sheet_known_spell, sheet_klass: sheet_klass, spell: ghost, source: nil)
      sheet.update!(metadata: sheet.metadata.merge(
        'spell_selections' => { 'cantrips' => [keep.id.to_s, ghost.id.to_s], 'known' => [], 'spellbook' => [], 'prepared' => [] }
      ))

      warnings = described_class.new(character: character, level: 1, data: {
        'progressionSubLevel' => 1,
        'spellSelections' => { 'cantrips' => [keep.id.to_s], 'known' => [], 'spellbook' => [], 'prepared' => [] }
      }).call.warnings

      expect(warnings).not_to include(a_string_matching(/nivel ausente/))
      sheet.reload
      expect(sheet.metadata['spell_selections']['cantrips']).to eq([keep.id.to_s])
      ids = SheetKnownSpell.where(sheet_klass_id: sheet_klass.id).pluck(:spell_id)
      expect(ids).to include(keep.id)
      expect(ids).not_to include(ghost.id)
    end

    it 'B7.6 — sync SheetKnownSpell mesmo quando SpellRules.sc_for retorna nil' do
      caster = create(:klass, api_index: "b76_caster_#{SecureRandom.hex(4)}")
      ClassLevel.create!(klass: caster, level: 4, prof_bonus: 2, ability_score_bonuses: 0)
      expect(SpellRules.sc_for(caster, 4)).to be_nil

      sp = create(:spell, name: 'B76 Mark', level: 1, api_index: "b76_spell_#{SecureRandom.hex(3)}")
      sheet_klass.update!(klass: caster)
      SheetKnownSpell.where(sheet_klass_id: sheet_klass.id).delete_all

      allow(ClassRules).to receive(:find).and_call_original
      allow(ClassRules).to receive(:find).with(caster.api_index).and_return({
        feature_rules: { spellcasting: { mode: 'known' } },
        spellcasting: { preparation: 'known' }
      })

      described_class.new(character: character, level: 4, data: {
        'spellSelections' => { 'known' => [sp.id.to_s], 'cantrips' => [] }
      }).call

      expect(SheetKnownSpell.where(sheet_klass_id: sheet_klass.id).pluck(:spell_id)).to eq([sp.id])
    end

    it 'B7.4b — PATCH com known: [] zera SheetKnownSpell de classe' do
      caster = create(:klass, api_index: "b74b_caster_#{SecureRandom.hex(4)}")
      cl = ClassLevel.create!(klass: caster, level: 4, prof_bonus: 2, ability_score_bonuses: 0)
      Spellcasting.create!(
        class_level: cl,
        level: 1,
        cantrips_known: 0,
        spells_known: 6,
        spell_slots: { '1' => 3 }.to_json
      )
      bless = create(:spell, name: 'Bless B74b', level: 1, api_index: "b74b_bless_#{SecureRandom.hex(3)}")

      sheet_klass.update!(klass: caster)
      SheetKnownSpell.where(sheet_klass_id: sheet_klass.id).delete_all
      create(:sheet_known_spell, sheet_klass: sheet_klass, spell: bless, source: 'class')

      described_class.new(character: character, level: 4, data: {
        'spellSelections' => {
          'cantrips' => [],
          'known' => [],
          'spellbook' => [],
          'prepared' => []
        }
      }).call

      expect(SheetKnownSpell.where(sheet_klass_id: sheet_klass.id, source: [nil, 'class', 'subclass']).count).to eq(0)
    end

    it 'B7.8 — Mago tambem limpa SheetKnownSpell fantasmas no PATCH (regressao Valac/2026-05)' do
      # Bug em prod: LevelUpService.ensure_level_requirements! sorteia magias
      # da lista da classe quando o limite de cantrips/known nao foi atingido,
      # gravando SheetKnownSpell SEM source. Para classes 'known' o sync ja
      # limpava esses registros (B7.4); para Mago (que e 'prepared' mas com
      # spellbook persistido em meta.spell_selections) o early-return em
      # `sync_sheet_known_spells_from_spell_selections!` ignorava — fantasmas
      # ficavam para sempre na ficha.
      wizard = Klass.find_by(api_index: 'wizard') || create(:klass, api_index: 'wizard')
      cl = ClassLevel.where(klass: wizard, level: 4).first ||
        ClassLevel.create!(klass: wizard, level: 4, prof_bonus: 2, ability_score_bonuses: 0)
      Spellcasting.where(class_level: cl).first || Spellcasting.create!(
        class_level: cl, level: 1, cantrips_known: 4, spells_known: 0,
        spell_slots: { '1' => 4, '2' => 3 }.to_json,
      )
      chosen_cantrip = create(:spell, name: 'B78 Truque Real', level: 0, api_index: "b78_c_#{SecureRandom.hex(3)}")
      ghost_cantrip = create(:spell, name: 'B78 Truque Fantasma', level: 0, api_index: "b78_cg_#{SecureRandom.hex(3)}")
      chosen_spell = create(:spell, name: 'B78 Magia Real', level: 1, api_index: "b78_s_#{SecureRandom.hex(3)}")
      ghost_spell = create(:spell, name: 'B78 Magia Fantasma', level: 1, api_index: "b78_sg_#{SecureRandom.hex(3)}")

      sheet_klass.update!(klass: wizard)
      SheetKnownSpell.where(sheet_klass_id: sheet_klass.id).delete_all
      # Auto-fill ja gravou as 4 (2 reais + 2 fantasmas) sem source
      [chosen_cantrip, ghost_cantrip, chosen_spell, ghost_spell].each do |sp|
        create(:sheet_known_spell, sheet_klass: sheet_klass, spell: sp, source: nil)
      end

      described_class.new(character: character, level: 4, data: {
        'spellSelections' => {
          'cantrips' => [chosen_cantrip.id.to_s],
          'known' => [chosen_spell.id.to_s],
          'spellbook' => [chosen_spell.id.to_s],
        },
      }).call

      remaining = SheetKnownSpell.where(sheet_klass_id: sheet_klass.id).pluck(:spell_id).sort
      expect(remaining).to eq([chosen_cantrip.id, chosen_spell.id].sort)
    end

    it 'B7.7 — sync não falha quando spell_selections inclui magia já em SheetKnownSpell (race)' do
      caster = create(:klass, api_index: "b77_warlock_#{SecureRandom.hex(4)}")
      cl = ClassLevel.create!(klass: caster, level: 4, prof_bonus: 2, ability_score_bonuses: 0)
      Spellcasting.create!(
        class_level: cl,
        level: 1,
        cantrips_known: 4,
        spells_known: 5,
        spell_slots: { '1' => 2 }.to_json
      )
      racial_cantrip = create(:spell, name: 'B77 Thaum', level: 0, api_index: "b77_thaum_#{SecureRandom.hex(3)}")
      sheet_klass.update!(klass: caster)
      SheetKnownSpell.where(sheet_klass_id: sheet_klass.id).delete_all
      create(:sheet_known_spell, sheet_klass: sheet_klass, spell: racial_cantrip, source: 'race')

      expect do
        described_class.new(character: character, level: 4, data: {
          'spellSelections' => {
            'cantrips' => [racial_cantrip.id.to_s],
            'known' => [],
            'spellbook' => [],
            'prepared' => []
          }
        }).call
      end.not_to raise_error

      rows = SheetKnownSpell.where(sheet_klass_id: sheet_klass.id, spell_id: racial_cantrip.id)
      expect(rows.count).to eq(1)
      expect(rows.first.source).to eq('race')
    end
  end

  describe 'B7.3 — read.progressionSubLevel reflete current_level' do
    it 'devolve current_level (4) ao inves de 2 hardcoded' do
      out = described_class.new(character: character, data: {}).read
      expect(out['progressionSubLevel']).to eq(4)
    end

    it 'com current_level=1 devolve 1 (aba PV do 1º nível)' do
      sheet.update!(current_level: 1)
      out = described_class.new(character: character.reload, data: {}).read
      expect(out['progressionSubLevel']).to eq(1)
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
