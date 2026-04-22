# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/support/imported_sheets_spell_seeder')

# Phase 6 — Caster spell roundtrip
#
# O fluxo de spells em re-provision tem múltiplos caminhos críticos:
#
#   payload[wizard][klass][classPicksByLevel][N][cantrips/spells]
#       ↓
#   metadata[class_choices][per_level][N][cantrips/spells]
#       ↓
#   KnownSpellsAggregator → resolve nome→Spell record
#       ↓
#   SheetKnownSpell (find_or_create_by → idempotente, mas...)
#       ↓
#   GET /summary → spells.known_by_level (front renderiza)
#
# Pontos de risco que esta spec valida:
#   1. Cantrips L1 sobrevivem ao level-up para L2
#   2. Spells L1 sobrevivem ao level-up para L2
#   3. SheetKnownSpell NÃO duplica em re-provision idêntico
#   4. Novos spells L2 são adicionados sem perder os L1
#   5. Summary GET reflete TODOS os spells (L0 + L1 + L2) após o roundtrip
#
# Decisão de design: usamos Wizard porque ele é o caster mais complexo
# (spellbook_progression + escolas). Bugs aqui pegam quase qualquer caster.
RSpec.describe 'Player::Characters caster spell roundtrip — Phase 6', type: :request do
  include AuthHelpers

  before(:all) { ImportedSheetsSpellSeeder.seed_all! }

  let(:user)  { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:race)  { human_race }
  let(:sub)   { human_standard_subrace(race) }
  let(:bg)    { acolyte_background }
  let(:align) { lawful_good_alignment }
  let(:wiz)   { wizard_klass }

  # 2 cantrips + 2 spells L1 estáveis do pool seedado
  let(:cantrip_ids) do
    Spell.where(api_index: %w[rspec-cantrip-1 rspec-cantrip-2]).pluck(:id, :name)
  end
  let(:l1_spell_ids) do
    rows = Spell.where(api_index: %w[rspec-spell-l1-1 rspec-spell-l1-2]).pluck(:id, :name)
    raise "L1 spell pool not seeded; got #{rows.inspect}" if rows.empty?
    rows
  end
  let(:l2_spell_ids) do
    rows = Spell.where(api_index: %w[rspec-spell-l2-1 rspec-spell-l2-2]).pluck(:id, :name)
    raise "L2 spell pool not seeded; got #{rows.inspect}" if rows.empty?
    rows
  end

  def per_level_rows(target_lv:, picks_by_level: {})
    hd = wiz.hit_die
    avg = (hd / 2) + 1
    rows = (1..target_lv).each_with_object({}) do |lv, h|
      die = lv == 1 ? hd : avg
      h[lv.to_s] = { 'hp' => { 'dieResult' => die, 'total' => die + 2, 'method' => 'fixed' } }
    end
    rows['1']['skills'] = %w[Arcanismo História]
    picks_by_level.each do |lv, picks|
      row = rows[lv.to_s] ||= {}
      row['cantrips'] = picks[:cantrips] if picks.key?(:cantrips)
      row['spells']   = picks[:spells]   if picks.key?(:spells)
    end
    rows
  end

  def build_payload(level:, picks_by_level:, character_id: nil, sub_id: 'escola-de-evocacao')
    wizard_evocation_subklass(wiz)
    rows = per_level_rows(target_lv: level, picks_by_level: picks_by_level)
    # Wizard threshold = 2; aplica subclass via per_level[2].subclass quando atingido
    if level >= 2
      rows['2'] ||= {}
      rows['2']['subclass'] = sub_id
    end
    char_block = { name: 'Caster RT', background: bg.name }
    char_block[:id] = character_id if character_id
    {
      character: char_block,
      wizard: {
        meta: { name: 'Caster RT', alignmentKey: align.api_index },
        race: {
          raceId: race.id, subRaceId: sub.id,
          ruleId: race.api_index, subRuleId: sub.api_index,
          attributes: { str: 8, dex: 14, con: 14, int: 16, wis: 12, cha: 10 },
          raceChoices: { chosenLanguages: [] }
        },
        klass: {
          klassId: wiz.id, klassRuleSlug: 'wizard', level: level,
          classSubclassId: sub_id,
          classSkillPicks: %w[Arcanismo História],
          classPicksByLevel: rows
        },
        background: { backgroundName: bg.name, backgroundKey: bg.api_index },
        equipment: {},
        avatar: { customization: {} }
      }
    }
  end

  def provision!(payload)
    post '/api/v1/player/characters/provision', params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:created), -> { response.body }
    JSON.parse(response.body, symbolize_names: true)
  end

  def known_spell_ids_for(sheet)
    SheetKnownSpell
      .joins(:sheet_klass)
      .where(sheet_klasses: { sheet_id: sheet.id })
      .pluck(:spell_id)
      .sort
  end

  describe 'Wizard L1 com cantrips e spells L1 → re-provision L2 com novos spells L2' do
    it 'preserva todos os spells L1 e adiciona os novos L2 sem duplicar' do
      cantrips_l1 = cantrip_ids.map { |id, name| { 'id' => id, 'name' => name, 'level' => 0 } }
      spells_l1   = l1_spell_ids.map { |id, name| { 'id' => id, 'name' => name, 'level' => 1 } }
      spells_l2   = l2_spell_ids.map { |id, name| { 'id' => id, 'name' => name, 'level' => 2 } }

      # Etapa 1 — Wizard L1 com cantrips + spells L1
      payload_l1 = build_payload(
        level: 1,
        picks_by_level: { 1 => { cantrips: cantrips_l1, spells: spells_l1 } }
      )
      r1 = provision!(payload_l1)
      char_id  = r1.dig(:character, :id)
      sheet_id = r1.dig(:character, :sheet, :id)
      sheet1   = Sheet.find(sheet_id)

      ksp_l1 = known_spell_ids_for(sheet1)
      expected_l1 = (cantrip_ids + l1_spell_ids).map(&:first).sort
      expect(ksp_l1).to include(*expected_l1),
        "Após L1 provision, SheetKnownSpell perdeu spells. Esperado >=#{expected_l1}, got #{ksp_l1}"

      l1_baseline_count = ksp_l1.size

      # Etapa 2 — Re-provision L2 mantendo L1 + adicionando L2 novos
      payload_l2 = build_payload(
        level: 2,
        character_id: char_id,
        picks_by_level: {
          1 => { cantrips: cantrips_l1, spells: spells_l1 },
          2 => { spells: spells_l2 }
        }
      )
      r2 = provision!(payload_l2)
      sheet2 = Sheet.find(r2.dig(:character, :sheet, :id))

      expect(sheet2.id).to eq(sheet1.id), "character.id mudou no level-up (perdeu identidade)"
      expect(sheet2.current_level).to eq(2)
      sk2 = sheet2.sheet_klasses.find_by(klass_id: wiz.id)
      expect(sk2.level).to eq(2)
      expect(sk2.sub_klass&.api_index).to eq('escola-de-evocacao')

      ksp_l2 = known_spell_ids_for(sheet2)
      # Spells L1 não podem ter sumido
      expect(ksp_l2).to include(*expected_l1),
        "REGRESSÃO: spells L1 sumiram após level-up. L1=#{expected_l1}, L2 atual=#{ksp_l2}"
      # Novos L2 entraram
      expect(ksp_l2).to include(*l2_spell_ids.map(&:first)),
        "Novos spells L2 não foram persistidos. Esperado #{l2_spell_ids.map(&:first)}, got #{ksp_l2}"
      # Não duplicou
      expect(ksp_l2.size).to eq(ksp_l2.uniq.size),
        "SheetKnownSpell duplicado: #{ksp_l2.tally.select { |_, c| c > 1 }}"
      # Pelo menos cresceu pelo número de novos L2
      expect(ksp_l2.size).to be >= l1_baseline_count + l2_spell_ids.size
    end
  end

  describe 'Idempotência: re-provisionar L2 com payload IDÊNTICO' do
    it 'não duplica SheetKnownSpell nem some spells' do
      cantrips = cantrip_ids.map { |id, name| { 'id' => id, 'name' => name, 'level' => 0 } }
      spells_l1 = l1_spell_ids.map { |id, name| { 'id' => id, 'name' => name, 'level' => 1 } }
      spells_l2 = l2_spell_ids.map { |id, name| { 'id' => id, 'name' => name, 'level' => 2 } }

      payload_l2 = build_payload(
        level: 2,
        picks_by_level: {
          1 => { cantrips: cantrips, spells: spells_l1 },
          2 => { spells: spells_l2 }
        }
      )
      r1 = provision!(payload_l2)
      char_id   = r1.dig(:character, :id)
      sheet1    = Sheet.find(r1.dig(:character, :sheet, :id))
      ksp_first = known_spell_ids_for(sheet1)

      # 3 re-provisions idênticas — não pode mudar nada
      3.times do
        payload2 = payload_l2.deep_dup
        payload2[:character][:id] = char_id
        provision!(payload2)
      end

      sheet_n = Sheet.find(sheet1.id)
      ksp_n = known_spell_ids_for(sheet_n)
      expect(ksp_n).to eq(ksp_first),
        "Re-provisão idêntica mudou SheetKnownSpell.\nantes: #{ksp_first}\ndepois: #{ksp_n}"
      expect(ksp_n.tally.values.max).to eq(1), "duplicação detectada: #{ksp_n.tally}"
    end
  end

  describe 'GET /summary reflete spells de TODOS os níveis após roundtrip' do
    it 'devolve cantrips, L1 e L2 em spells.known_by_level' do
      cantrips = cantrip_ids.map { |id, name| { 'id' => id, 'name' => name, 'level' => 0 } }
      spells_l1 = l1_spell_ids.map { |id, name| { 'id' => id, 'name' => name, 'level' => 1 } }
      spells_l2 = l2_spell_ids.map { |id, name| { 'id' => id, 'name' => name, 'level' => 2 } }

      r1 = provision!(build_payload(
        level: 1,
        picks_by_level: { 1 => { cantrips: cantrips, spells: spells_l1 } }
      ))
      char_id  = r1.dig(:character, :id)
      sheet_id = r1.dig(:character, :sheet, :id)

      provision!(build_payload(
        level: 2, character_id: char_id,
        picks_by_level: {
          1 => { cantrips: cantrips, spells: spells_l1 },
          2 => { spells: spells_l2 }
        }
      ))

      get "/api/v1/player/sheets/#{sheet_id}/summary?sync=true", headers: headers
      expect(response).to have_http_status(:ok)
      sj = JSON.parse(response.body, symbolize_names: true)[:summary]

      known = sj.dig(:spells, :known_by_level) || {}
      l0_names = Array(known[:'0']).map { |e| e[:name] }
      l1_names = Array(known[:'1']).map { |e| e[:name] }
      l2_names = Array(known[:'2']).map { |e| e[:name] }

      cantrip_names_expected = cantrip_ids.map(&:last)
      l1_names_expected      = l1_spell_ids.map(&:last)
      l2_names_expected      = l2_spell_ids.map(&:last)

      expect(l0_names).to include(*cantrip_names_expected),
        "Summary não trouxe cantrips. got L0=#{l0_names}, esperado >=#{cantrip_names_expected}"
      expect(l1_names).to include(*l1_names_expected),
        "Summary não trouxe spells L1. got L1=#{l1_names}, esperado >=#{l1_names_expected}"
      expect(l2_names).to include(*l2_names_expected),
        "Summary não trouxe spells L2. got L2=#{l2_names}, esperado >=#{l2_names_expected}"
    end
  end
end
