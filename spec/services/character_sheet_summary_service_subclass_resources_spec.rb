# frozen_string_literal: true

require 'rails_helper'

# R1 — Generalização de `build_resources`: agora materializa
#   (1) recursos de feature de SUBCLASSE via bloco `uses` (levels_json),
#   (2) recursos derivados centrais (ClassRules.derive_feature_rules — ex.: Cozinheiro snacks),
#   (3) recursos centrais estruturados (Dado de Superioridade, Arcano Místico, Golpe de Sorte),
# sem quebrar a allowlist hardcoded por classe-base (rage/ki/arcane_recovery/...).
RSpec.describe CharacterSheetSummaryService, type: :service do
  let(:user) do
    User.create!(
      email: "subres_#{SecureRandom.hex(4)}@example.com",
      username: "sr#{SecureRandom.hex(4)}",
      password: 'password1',
      password_confirmation: 'password1',
      role_id: Role.find_or_create_by!(name: 'player').id,
    )
  end

  let(:race) { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }

  def make_sheet(klass:, level:, sub_klass: nil,
                 abilities: { str: 10, dex: 14, con: 12, int: 10, wis: 10, cha: 14 },
                 metadata: {})
    character = Character.create!(user: user, name: "SR #{SecureRandom.hex(2)}", background: 'Sage')
    sheet = Sheet.create!(
      character: character,
      race: race,
      str: abilities[:str], dex: abilities[:dex], con: abilities[:con],
      int: abilities[:int], wis: abilities[:wis], cha: abilities[:cha],
      hp_max: 10, hp_current: 10, current_level: level,
      metadata: metadata,
    )
    SheetKlass.create!(sheet: sheet, klass: klass, level: level, sub_klass: sub_klass)
    sheet
  end

  def call_summary(sheet)
    cmd = described_class.call(sheet_id: sheet.id, sync: false)
    cmd.respond_to?(:result) ? cmd.result : cmd
  end

  def fighter
    Klass.find_or_create_by!(api_index: 'fighter') do |k|
      k.name = 'Guerreiro'; k.hit_die = 10; k.subclass_level = 3
    end
  end

  def ranger
    Klass.find_or_create_by!(api_index: 'ranger') do |k|
      k.name = 'Patrulheiro'; k.hit_die = 10; k.subclass_level = 3
    end
  end

  def warlock
    Klass.find_or_create_by!(api_index: 'warlock') do |k|
      k.name = 'Bruxo'; k.hit_die = 8; k.subclass_level = 1
    end
  end

  def wizard
    Klass.find_or_create_by!(api_index: 'wizard') do |k|
      k.name = 'Mago'; k.hit_die = 6; k.subclass_level = 2
    end
  end

  def cozinheiro
    Klass.find_or_create_by!(api_index: 'cozinheiro') do |k|
      k.name = 'Cozinheiro'; k.hit_die = 8; k.subclass_level = 3
    end
  end

  def barbarian
    Klass.find_or_create_by!(api_index: 'barbarian') do |k|
      k.name = 'Bárbaro'; k.hit_die = 12; k.subclass_level = 3
    end
  end

  # Cria uma SubKlass com levels_json controlado (String JSON, como no DB real).
  # O `api_index` recebe sufixo aleatório para não colidir com seeds reais do
  # banco de teste (a lógica de recurso de subclasse usa name/uses, não o slug).
  def make_subklass(klass:, api_index:, name:, levels:)
    SubKlass.create!(
      klass: klass, api_index: "#{api_index}-spec-#{SecureRandom.hex(3)}", name: name,
      levels_json: levels.to_json,
    )
  end

  # ── (a) Guerreiro / Mestre de Batalha → superiority_dice ──────────────
  describe 'Guerreiro / Mestre de Batalha (L20)' do
    let(:sub) do
      make_subklass(
        klass: fighter, api_index: 'mestre-de-batalha', name: 'Mestre de Batalha',
        levels: [
          { 'level' => 3, 'features' => [{ 'name' => 'Superioridade em Combate' }] },
          { 'level' => 7, 'features' => [{ 'name' => 'Dado Adicional', 'rules' => { 'superiority_dice_bonus' => 1 } }] },
          { 'level' => 10, 'features' => [{ 'name' => 'Superioridade Aprimorada', 'rules' => { 'superiority_die_size' => 'd10' } }] },
          { 'level' => 15, 'features' => [{ 'name' => 'Dado Adicional', 'rules' => { 'superiority_dice_bonus' => 1 } }] },
          { 'level' => 18, 'features' => [{ 'name' => 'Superioridade Aprimorada (d12)', 'rules' => { 'superiority_die_size' => 'd12' } }] },
        ],
      )
    end

    it 'expõe superiority_dice total=6, die=d12 no L20' do
      sheet = make_sheet(klass: fighter, level: 20, sub_klass: sub)
      res = call_summary(sheet)[:resources]
      expect(res[:superiority_dice]).to include(total: 6, die: 'd12', recharge: 'SR/LR', used: 0)
    end

    it 'no L3 são 4 dados d8' do
      sheet = make_sheet(klass: fighter, level: 3, sub_klass: sub)
      res = call_summary(sheet)[:resources]
      expect(res[:superiority_dice]).to include(total: 4, die: 'd8')
    end

    it 'não regride: action_surge/second_wind/indomitable continuam presentes' do
      sheet = make_sheet(klass: fighter, level: 20, sub_klass: sub)
      res = call_summary(sheet)[:resources]
      expect(res[:action_surge]).to be_present
      expect(res[:second_wind]).to be_present
      expect(res[:indomitable]).to be_present
    end
  end

  # ── (b) Ranger → feature de subclasse via bloco `uses` ────────────────
  describe 'Patrulheiro / feature de subclasse com bloco uses' do
    let(:sub) do
      make_subklass(
        klass: ranger, api_index: 'flagelo-dos-inimigos', name: 'Flagelo dos Inimigos',
        levels: [
          { 'level' => 11, 'features' => [{ 'name' => 'Estudar Inimigo',
                                            'uses' => { 'per' => 'descanso curto ou longo', 'value' => 1 } }] },
        ],
      )
    end

    it 'materializa Estudar Inimigo como recurso (1/SR-LR)' do
      sheet = make_sheet(klass: ranger, level: 20, sub_klass: sub)
      res = call_summary(sheet)[:resources]
      expect(res[:estudar_inimigo]).to include(total: 1, recharge: 'SR/LR', used: 0)
    end

    it 'não emite recurso para feature de subclasse SEM bloco uses (ex.: Grito Primitivo) → D5' do
      sub_sem_uses = make_subklass(
        klass: ranger, api_index: 'guardiao_selvagem', name: 'Guardião Selvagem',
        levels: [{ 'level' => 3, 'features' => [{ 'name' => 'Grito Primitivo', 'description' => 'descanso curto ou longo' }] }],
      )
      sheet = make_sheet(klass: ranger, level: 20, sub_klass: sub_sem_uses)
      res = call_summary(sheet)[:resources]
      expect(res).to eq({})
    end
  end

  # ── (c) Bruxo → Arcano Místico ────────────────────────────────────────
  describe 'Bruxo / Arcano Místico (Mystic Arcanum)' do
    it 'expõe mystic_arcanum com 4 magias (6º–9º) no L20' do
      sheet = make_sheet(klass: warlock, level: 20)
      res = call_summary(sheet)[:resources]
      expect(res[:mystic_arcanum]).to include(total: 4, recharge: 'LR', used: 0)
      expect(res[:mystic_arcanum][:spell_levels]).to match_array([6, 7, 8, 9])
    end

    it 'não expõe mystic_arcanum abaixo do L11' do
      sheet = make_sheet(klass: warlock, level: 10)
      res = call_summary(sheet)[:resources]
      expect(res[:mystic_arcanum]).to be_nil
    end
  end

  # ── (d) Cozinheiro → snacks (derived[:resources]) ─────────────────────
  describe 'Cozinheiro / Petiscos (snacks)' do
    it 'expõe snacks derivado de mod.CON com DC e recarga' do
      # CON 16 (mod +3); L20 → PB +6; total no L7+: base(3)+extra(3)=6; DC=8+6+3=17
      sheet = make_sheet(klass: cozinheiro, level: 20,
                         abilities: { str: 10, dex: 10, con: 16, int: 10, wis: 10, cha: 10 })
      res = call_summary(sheet)[:resources]
      expect(res[:snacks]).to be_present
      expect(res[:snacks][:total]).to eq(6)
      expect(res[:snacks][:recharge]).to eq('SR/LR')
      expect(res[:snacks][:dc]).to eq(17)
    end

    it 'snacks tem mínimo de 1 mesmo com CON baixo' do
      sheet = make_sheet(klass: cozinheiro, level: 1,
                         abilities: { str: 10, dex: 10, con: 8, int: 10, wis: 10, cha: 10 })
      res = call_summary(sheet)[:resources]
      expect(res[:snacks][:total]).to eq(1)
    end
  end

  # ── (e) Regressões ────────────────────────────────────────────────────
  describe 'regressão (allowlist intacta)' do
    it 'Bárbaro ainda expõe rage' do
      sheet = make_sheet(klass: barbarian, level: 20)
      res = call_summary(sheet)[:resources]
      expect(res[:rage]).to be_present
      expect(res[:rage][:total]).to eq(999)
    end

    it 'Mago ainda expõe arcane_recovery' do
      sheet = make_sheet(klass: wizard, level: 20)
      res = call_summary(sheet)[:resources]
      expect(res[:arcane_recovery]).to include(total: 1, max_slot_levels: 10)
    end
  end

  # ── Canalizar Divindade de subclasse (Teurgia Mística) ────────────────
  describe 'Canalizar Divindade concedido por subclasse' do
    it 'mapeia feature "Canalizar Divindade: ..." da subclasse para :channel_divinity' do
      sub = make_subklass(
        klass: wizard, api_index: 'teurgia-mistica', name: 'Teurgia Mística',
        levels: [
          { 'level' => 6, 'features' => [{ 'name' => 'Canalizar Divindade: Misticismo Divino',
                                           'rules' => { 'uses' => 1 } }] },
        ],
      )
      sheet = make_sheet(klass: wizard, level: 20, sub_klass: sub)
      res = call_summary(sheet)[:resources]
      expect(res[:channel_divinity]).to include(total: 1, used: 0)
      # arcane_recovery (base mago) continua presente
      expect(res[:arcane_recovery]).to be_present
    end
  end

  # ── Consistência de chave com class_resources_used (front grava o slug) ─
  describe 'consistência da chave com runtime class_resources_used' do
    it 'used reflete o slug gravado em class_resources_used' do
      sub = make_subklass(
        klass: ranger, api_index: 'flagelo-dos-inimigos', name: 'Flagelo dos Inimigos',
        levels: [
          { 'level' => 11, 'features' => [{ 'name' => 'Estudar Inimigo',
                                            'uses' => { 'per' => 'descanso curto ou longo', 'value' => 1 } }] },
        ],
      )
      sheet = make_sheet(klass: ranger, level: 20, sub_klass: sub)
      sheet.runtime!.update!(class_resources_used: { 'estudar_inimigo' => 1 })
      res = call_summary(sheet)[:resources]
      expect(res[:estudar_inimigo][:used]).to eq(1)
    end
  end
end
