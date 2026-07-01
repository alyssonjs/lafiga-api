# frozen_string_literal: true

require 'rails_helper'

# Cobertura das correções da varredura dinâmica de TALENTOS
# (.cursor/dnd-rules/_VARREDURA-talentos.md). Cada exemplo amarra uma raiz
# (Fn/Dn) ao comportamento corrigido, no caminho COMPLETO de runtime
# (FeatAssignmentService → CharacterSheetSummaryService / FeatProducer).
RSpec.describe 'Varredura de talentos — correções de pipeline e dados', type: :service do
  # ── helpers de setup ────────────────────────────────────────────────
  def make_user
    role = Role.find_or_create_by!(name: 'player')
    User.create!(
      email: "fgv_#{SecureRandom.hex(4)}@example.com",
      username: "fgv#{SecureRandom.hex(4)}",
      password: 'password1', password_confirmation: 'password1', role_id: role.id
    )
  end

  # Ficha autoritativa (colunas str..cha como fonte de verdade), espelhando o
  # que provisioning/front gravam: flag + base_ability_scores.
  def build_sheet(klass_api: 'fighter', spellcasting_ability: nil, base: 15,
                  armor: %w[leve média pesada], class_summary_extra: {}, metadata_extra: {})
    user = make_user
    character = Character.create!(user: user, name: 'Spec Varredura', background: 'Test')
    race = Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' }
    sub_race = SubRace.find_or_create_by!(race_id: race.id, api_index: 'standard') { |s| s.name = 'Humano Padrão' }
    klass = Klass.find_or_create_by!(api_index: klass_api) do |k|
      k.name = klass_api.capitalize
      k.hit_die = 10
      k.subclass_level = 3
      k.spellcasting_ability = spellcasting_ability
    end
    klass.update!(spellcasting_ability: spellcasting_ability) if klass.spellcasting_ability != spellcasting_ability

    cs = {
      'armor_proficiencies' => armor,
      'weapon_proficiencies' => ['arma_simples'],
      'skills' => [], 'tools' => []
    }.merge(class_summary_extra)

    sheet = Sheet.create!(
      character: character, race: race, sub_race: sub_race,
      str: base, dex: base, con: base, int: base, wis: base, cha: base,
      hp_max: 80, hp_current: 80,
      metadata: {
        'class_summary' => cs,
        'base_ability_scores' => { 'str' => base, 'dex' => base, 'con' => base,
                                   'int' => base, 'wis' => base, 'cha' => base },
        'ability_scores_include_all_increments' => true
      }.merge(metadata_extra)
    )
    SheetKlass.create!(sheet: sheet, klass: klass, level: 6)
    sheet
  end

  def assign(sheet, feat_id, choices = {}, level: 4)
    FeatAssignmentService.call(sheet: sheet, feat_id: feat_id, level_gained: level, choices: choices)
  end

  def summary(sheet)
    CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false).result
  end

  # ── F1 — build_resources lê recursos de talento ─────────────────────
  describe 'F1 — recursos de talento em build_resources' do
    it 'Sortudo expõe resources.luck_points (3, recarga LR)' do
      sheet = build_sheet
      assign(sheet, 'sortudo')
      lp = summary(sheet)[:resources][:luck_points]
      expect(lp).to include(total: 3, recharge: 'LR')
    end

    it 'Adepto Marcial expõe resources.superiority_dice (1 d6)' do
      sheet = build_sheet
      assign(sheet, 'adepto_marcial', { 'maneuvers' => %w[aparar ameacador] })
      sd = summary(sheet)[:resources][:superiority_dice]
      expect(sd).to be_present
      expect(sd[:total]).to be >= 1
      expect(sd[:die]).to eq('d6')
    end
  end

  # ── F2/F3 — FeatSpecialRulesService total (preserva famílias e params) ─
  describe 'F2/F3 — special_rules não somem' do
    it 'Curandeiro preserva a família healing' do
      sheet = build_sheet
      assign(sheet, 'curandeiro')
      sr = sheet.reload.metadata['feats'].find { |f| f['feat_id'] == 'curandeiro' }['special_rules']
      expect(sr.keys).to include('healing')
    end

    it 'Ator preserva o Array de perícias em skill_advantage (params Array)' do
      sheet = build_sheet
      assign(sheet, 'ator')
      sr = sheet.reload.metadata['feats'].find { |f| f['feat_id'] == 'ator' }['special_rules']
      expect(sr.dig('skills', 'skill_advantage')).to match_array(%w[Atuação Enganação])
    end

    it 'Duelista Defensivo preserva reaction_ac_bonus String (params String)' do
      sheet = build_sheet
      assign(sheet, 'duelista_defensivo')
      sr = sheet.reload.metadata['feats'].find { |f| f['feat_id'] == 'duelista_defensivo' }['special_rules']
      expect(sr.dig('defense', 'reaction_ac_bonus')).to eq('proficiency_bonus')
    end
  end

  # ── F4 — Mestre de Armas Duplas: +1 CA sem predicate redundante ──────
  describe 'F4 — Mestre de Armas Duplas +1 CA é somado' do
    it 'Bag.sum_for("ac") conta o +1 SEM predicate_match' do
      sheet = build_sheet
      assign(sheet, 'mestre_de_armas_duplas')
      eq = { equipped: { main_hand: { category: 'weapon' }, off_hand: { category: 'weapon' } } }
      prod = Modifiers::Producers::FeatProducer.new(sheet.reload, context: { equipment: eq })
      bag = Modifiers::ModifierResolver::Bag.new(prod.produce)
      ac_mod = prod.produce.find { |m| m.target == 'ac' }
      expect(ac_mod.predicate).to be_blank
      expect(bag.sum_for('ac')).to eq(1)
    end
  end

  # ── F5/F6 — half-feat materializa coluna + teto 20 ──────────────────
  describe 'F5/F6 — half-feat em ficha autoritativa' do
    it 'Durável aplica +1 CON e NÃO gera linha "Ajuste manual"' do
      sheet = build_sheet(base: 15)
      assign(sheet, 'duravel')
      ab = summary(sheet)[:abilities]
      expect(ab[:scores][:con]).to eq(16)
      labels = ab[:sources][:con].map { |e| e[:label] }
      expect(labels).not_to include('Ajuste manual')
      expect(labels).to include(a_string_matching(/Talento/))
    end

    it 'teto 20: half-feat em atributo no máximo não passa de 20' do
      sheet = build_sheet(base: 20)
      assign(sheet, 'duravel') # +1 CON
      expect(summary(sheet)[:abilities][:scores][:con]).to eq(20)
    end
  end

  # ── F7/F8 — magias de talento materializam SheetKnownSpell ──────────
  describe 'F7/F8 — magias de talento' do
    let!(:cantrip) { Spell.find_or_create_by!(api_index: 'spec-cantrip') { |s| s.name = 'Truque Spec'; s.level = 0 } }
    let!(:lvl1)    { Spell.find_or_create_by!(api_index: 'spec-l1') { |s| s.name = 'Magia Spec'; s.level = 1 } }

    it 'F8 — Mágico Iniciante cria 2 truques + 1 magia 1/longo (LR)' do
      sheet = build_sheet(klass_api: 'wizard', spellcasting_ability: 'int')
      cantrip2 = Spell.find_or_create_by!(api_index: 'spec-cantrip2') { |s| s.name = 'Truque Spec 2'; s.level = 0 }
      assign(sheet, 'magico_iniciante',
             { 'cantrips' => [cantrip.name, cantrip2.name], 'spells' => [lvl1.name] })
      rows = SheetKnownSpell.joins(:sheet_klass).where(sheet_klasses: { sheet_id: sheet.id }, source: 'feat')
      expect(rows.count).to eq(3)
      l1row = rows.find { |r| r.spell_id == lvl1.id }
      expect(l1row.uses_per_rest).to eq('LR')
      expect(l1row.uses_remaining).to eq(1)
    end

    it 'F7 — Sniper Mágico materializa o truque escolhido (learn_cantrip)' do
      sheet = build_sheet(klass_api: 'wizard', spellcasting_ability: 'int')
      assign(sheet, 'sniper_magico', { 'cantrips' => [cantrip.name] })
      rows = SheetKnownSpell.joins(:sheet_klass).where(sheet_klasses: { sheet_id: sheet.id }, source: 'feat')
      expect(rows.map { |r| r.spell_id }).to include(cantrip.id)
    end

    it 'F7 — Conjurador de Ritual materializa os rituais (ritual_book)' do
      sheet = build_sheet(klass_api: 'wizard', spellcasting_ability: 'int')
      assign(sheet, 'conjurador_de_ritual', { 'spells' => [lvl1.name] })
      rows = SheetKnownSpell.joins(:sheet_klass).where(sheet_klasses: { sheet_id: sheet.id }, source: 'feat')
      expect(rows.map { |r| r.spell_id }).to include(lvl1.id)
    end
  end

  # ── F9 — Resiliente deriva o save de choices['ability'] ─────────────
  describe 'F9 — Resiliente' do
    it 'concede o save mesmo com choices {ability:"wis"} (sem saving_throws)' do
      sheet = build_sheet
      assign(sheet, 'resiliente', { 'ability' => 'wis' })
      expect(summary(sheet)[:saving_throws]).to include('wis')
    end
  end

  # ── F11 — Maestria Pesada expõe a redução de dano ───────────────────
  describe 'F11 — Maestria em Armadura Pesada' do
    it 'expõe modifiers.damage_reduction_nonmagical_bps = 3' do
      sheet = build_sheet(armor: %w[leve média pesada])
      assign(sheet, 'maestria_em_armadura_pesada')
      expect(summary(sheet)[:modifiers][:damage_reduction_nonmagical_bps]).to eq(3)
    end
  end

  # ── D2 — prereq de armadura (armors plural + EN/PT) ─────────────────
  describe 'D2 — prereq de armadura' do
    it 'bloqueia quando a ficha não é proficiente na categoria exigida' do
      sheet = build_sheet(armor: ['leve']) # exige 'pesada'
      expect(FeatRules.check_prerequisites('maestria_em_armadura_pesada', sheet)).to be(false)
    end

    it 'aceita proficiência declarada em inglês (heavy ↔ pesada)' do
      sheet = build_sheet(armor: %w[light medium heavy])
      expect(FeatRules.check_prerequisites('maestria_em_armadura_pesada', sheet)).to be(true)
    end
  end

  # ── D3 — Poliglota materializa idiomas ──────────────────────────────
  describe 'D3 — Poliglota' do
    it 'adiciona os idiomas escolhidos a proficiencies.languages' do
      sheet = build_sheet
      assign(sheet, 'poliglota', { 'languages' => %w[Anão Élfico Orc] })
      langs = summary(sheet)[:proficiencies][:languages]
      expect(langs).to include('Anão', 'Élfico', 'Orc')
    end
  end

  # ── D4 — Especialista em Armas: choices.weapons (flat) ──────────────
  describe 'D4 — Especialista em Armas' do
    it 'resolve weapons a partir de choices.weapons (flat) sem vazar hash bruto' do
      sheet = build_sheet
      assign(sheet, 'especialista_em_armas',
             { 'ability' => 'str', 'weapons' => %w[Rapieira Cimitarra Florete Adaga] })
      entry = sheet.reload.metadata['feats'].find { |f| f['feat_id'] == 'especialista_em_armas' }
      pb_weapons = entry['proficiency_bonuses']['weapons']
      expect(pb_weapons).to match_array(%w[Rapieira Cimitarra Florete Adaga])
      expect(summary(sheet)[:proficiencies][:weapons]).to include('Rapieira', 'Adaga')
    end
  end

  # ── D9 — spellcasting exige classe conjuradora real ─────────────────
  describe 'D9 — sheet_has_spellcasting?' do
    it 'FALSE para não-conjurador com linhas de magia semeadas em per_level' do
      sheet = build_sheet(
        klass_api: 'fighter', spellcasting_ability: nil,
        metadata_extra: { 'class_choices' => { 'per_level' => { '1' => { 'cantrips' => ['x'] } } } }
      )
      # remove qualquer atalho denormalizado de class_summary
      meta = sheet.metadata; meta['class_summary'].delete('spellcasting'); sheet.update!(metadata: meta)
      expect(FeatRules.sheet_has_spellcasting?(sheet.reload)).to be(false)
    end

    it 'TRUE para classe com spellcasting_ability real' do
      sheet = build_sheet(klass_api: 'wizard', spellcasting_ability: 'int')
      meta = sheet.metadata; meta['class_summary'].delete('spellcasting'); sheet.update!(metadata: meta)
      expect(FeatRules.sheet_has_spellcasting?(sheet.reload)).to be(true)
    end
  end
end
