# frozen_string_literal: true

require 'rails_helper'

# BDD Fase 6A — DamageService aplica resistência / imunidade / vulnerabilidade.
# ----------------------------------------------------------------------------
# PHB 5e: ao receber dano, o combatente pode ter:
#   - imunidade   → 0 dano
#   - resistência → metade do dano (round down, mínimo 0)
#   - vulnerabilidade → dobro do dano
#   - reduções fixas (Heavy Armor Master: -3 de dano físico não-mágico)
#
# Antes da Fase 6A: DamageService aplicava o dano cru sem consultar nenhum
# modifier. Agora `damage_type:` pode ser informado e o service resolve
# resistances/immunities/vulnerabilities lidos de:
#   - PC: summary[:modifiers][:resistances/damage_immunities/damage_vulnerabilities]
#   - NPC: combatable.resistances/immunities/vulnerabilities (após Fase 6E)
RSpec.describe Combat::DamageService, type: :service do
  let(:role) { Role.find_or_create_by!(name: 'player') }
  let(:user) do
    User.create!(email: "ds_#{SecureRandom.hex(4)}@example.com",
                 username: "ds#{SecureRandom.hex(4)}",
                 password: 'password1', password_confirmation: 'password1', role_id: role.id)
  end
  let(:race)     { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }
  let(:sub_race) { SubRace.find_or_create_by!(race_id: race.id, api_index: 'standard') { |s| s.name = 'Humano Padrão' } }
  let(:klass) do
    Klass.find_or_create_by!(api_index: 'fighter') { |k| k.name = 'Guerreiro'; k.hit_die = 10; k.subclass_level = 3 }
  end

  # Helpers de setup
  def build_pc(hp: 30, ac: 16, feat_id: nil, choices: {})
    character = Character.create!(user: user, name: "PC #{SecureRandom.hex(2)}", background: 'Test')
    sheet = Sheet.create!(
      character: character, race: race, sub_race: sub_race,
      str: 14, dex: 14, con: 14, int: 10, wis: 10, cha: 10,
      hp_max: hp, hp_current: hp,
      metadata: { 'class_summary' => {}, 'base_ability_scores' =>
                  { 'str' => 14, 'dex' => 14, 'con' => 14, 'int' => 10, 'wis' => 10, 'cha' => 10 } }
    )
    SheetKlass.create!(sheet: sheet, klass: klass, level: 1)
    FeatAssignmentService.call(sheet: sheet, feat_id: feat_id, level_gained: 1, choices: choices) if feat_id
    [character, sheet.reload]
  end

  def build_combatant(character, hp_max: 30, ac: 16, temp_hp: 0, concentrating: false)
    schedule = create(:schedule)
    cs = CombatState.create!(schedule: schedule, active: true, round: 1, current_turn_index: 0)
    CombatCombatant.create!(
      combat_state: cs, combatable: character, position: 1, name: character.name,
      initiative: 10, initiative_bonus: 0, tie_break_dex: 14,
      hp_current: hp_max, hp_max: hp_max, ac: ac, temp_hp: temp_hp,
      is_concentrating: concentrating
    )
  end

  # =====================================================================
  #  Comportamento atual (regressão) — dano cru sem modifiers
  # =====================================================================
  describe 'comportamento atual sem damage_type — backward compatibility' do
    it 'aplica dano cheio quando damage_type não informado' do
      character, _sheet = build_pc(hp: 30)
      combatant = build_combatant(character, hp_max: 30)

      result = described_class.call(combatant: combatant, amount: 10)
      expect(result.success?).to be(true)
      expect(result.result[:damage_applied]).to eq(10)
      expect(combatant.reload.hp_current).to eq(20)
    end
  end

  # =====================================================================
  #  Imunidade — dano = 0
  # =====================================================================
  describe 'imunidade a tipo de dano (PC com resistência via summary)' do
    it 'PC com damage_immunities = ["fogo"] sofre 0 quando damage_type=fogo' do
      character, sheet = build_pc(hp: 30)
      sheet.update!(metadata: sheet.metadata.merge(
        'damage_immunities' => ['fogo']
      ))
      combatant = build_combatant(character, hp_max: 30)

      result = described_class.call(combatant: combatant, amount: 20, damage_type: 'fogo')
      expect(result.success?).to be(true)
      expect(result.result[:damage_applied]).to eq(0)
      expect(result.result[:damage_modifier]).to eq(:immune)
      expect(combatant.reload.hp_current).to eq(30)
    end
  end

  # =====================================================================
  #  Resistência — dano metade (round down)
  # =====================================================================
  describe 'resistência (PC com Tiefling Infernal etc.)' do
    it 'PC com resistance fogo sofre metade quando damage_type=fogo' do
      character, sheet = build_pc(hp: 30)
      sheet.update!(metadata: sheet.metadata.merge('resistances' => ['fogo']))
      combatant = build_combatant(character, hp_max: 30)

      result = described_class.call(combatant: combatant, amount: 11, damage_type: 'fogo')
      expect(result.success?).to be(true)
      expect(result.result[:damage_applied]).to eq(5),  # 11/2 = 5 (round down)
        "PHB: resistência arredonda PRA BAIXO. 11÷2=5.5 → 5. Veio: #{result.result[:damage_applied]}"
      expect(result.result[:damage_modifier]).to eq(:resistant)
      expect(combatant.reload.hp_current).to eq(25)
    end
  end

  # =====================================================================
  #  Vulnerabilidade — dano dobrado
  # =====================================================================
  describe 'vulnerabilidade (raro)' do
    it 'PC com vulnerability sofre 2x dano' do
      character, sheet = build_pc(hp: 30)
      sheet.update!(metadata: sheet.metadata.merge('damage_vulnerabilities' => ['frio']))
      combatant = build_combatant(character, hp_max: 30)

      result = described_class.call(combatant: combatant, amount: 5, damage_type: 'frio')
      expect(result.success?).to be(true)
      expect(result.result[:damage_applied]).to eq(10)
      expect(result.result[:damage_modifier]).to eq(:vulnerable)
      expect(combatant.reload.hp_current).to eq(20)
    end
  end

  # =====================================================================
  #  Heavy Armor Master — redução fixa de 3 em B/P/S não-mágico
  # =====================================================================
  describe 'Heavy Armor Master (redução -3 BPS não-mágico em armadura pesada)' do
    it 'PC com HAM em armadura pesada sofre dano - 3 (mínimo 0)' do
      character, sheet = build_pc(hp: 30, feat_id: 'maestria_em_armadura_pesada')
      # Marca que está usando armadura pesada (predicate do modifier).
      sheet.update!(metadata: sheet.metadata.merge('wearing_heavy_armor' => true))
      combatant = build_combatant(character, hp_max: 30)

      result = described_class.call(combatant: combatant, amount: 10, damage_type: 'cortante', magical: false)
      expect(result.success?).to be(true)
      expect(result.result[:damage_applied]).to eq(7),  # 10 - 3 (HAM)
        "Heavy Armor Master reduz B/P/S não-mágico em 3. Esperado 7, veio #{result.result[:damage_applied]}"
      expect(combatant.reload.hp_current).to eq(23)
    end

    it 'HAM NÃO reduz dano MÁGICO físico' do
      character, sheet = build_pc(hp: 30, feat_id: 'maestria_em_armadura_pesada')
      sheet.update!(metadata: sheet.metadata.merge('wearing_heavy_armor' => true))
      combatant = build_combatant(character, hp_max: 30)

      result = described_class.call(combatant: combatant, amount: 10, damage_type: 'cortante', magical: true)
      expect(result.result[:damage_applied]).to eq(10),
        'HAM só reduz dano de armas NÃO-mágicas. Magical=true deve aplicar dano cheio.'
    end

    it 'HAM NÃO reduz dano NÃO-FÍSICO (ex.: fogo)' do
      character, sheet = build_pc(hp: 30, feat_id: 'maestria_em_armadura_pesada')
      sheet.update!(metadata: sheet.metadata.merge('wearing_heavy_armor' => true))
      combatant = build_combatant(character, hp_max: 30)

      result = described_class.call(combatant: combatant, amount: 10, damage_type: 'fogo', magical: false)
      expect(result.result[:damage_applied]).to eq(10),
        'HAM só reduz B/P/S (contundente/perfurante/cortante). Fogo passa cheio.'
    end
  end

  # =====================================================================
  #  Combinações — resistência + redução fixa
  # =====================================================================
  describe 'combinações (PHB: resistência aplicada DEPOIS de reduções fixas)' do
    it 'aplica HAM (-3) ANTES da resistência (½)' do
      character, sheet = build_pc(hp: 50, feat_id: 'maestria_em_armadura_pesada')
      sheet.update!(metadata: sheet.metadata.merge(
        'wearing_heavy_armor' => true,
        'resistances' => ['cortante']
      ))
      combatant = build_combatant(character, hp_max: 50)

      result = described_class.call(combatant: combatant, amount: 13, damage_type: 'cortante', magical: false)
      # PHB: subtrai HAM (-3) primeiro → 10; depois resistência ½ → 5.
      expect(result.result[:damage_applied]).to eq(5),
        "Esperado 13-3=10; depois ½=5. Veio #{result.result[:damage_applied]}"
    end
  end

  # =====================================================================
  #  Fase 6B — Ataque contra PC a 0 HP = death save failures
  # =====================================================================
  describe 'Fase 6B — alvo PC a 0 HP recebe death save failures' do
    it 'acerto normal contra PC a 0 HP adiciona +1 falha' do
      character, _sheet = build_pc(hp: 30)
      combatant = build_combatant(character, hp_max: 30)
      combatant.update!(hp_current: 0)
      expect(combatant.death_saves['failures']).to eq(0)

      result = described_class.call(combatant: combatant, amount: 5, attack_kind: 'normal')
      expect(result.success?).to be(true)
      expect(result.result[:death_save_failures_added]).to eq(1)
      expect(combatant.reload.death_saves['failures']).to eq(1)
    end

    it 'acerto CRÍTICO contra PC a 0 HP adiciona +2 falhas (PHB p. 197)' do
      character, _sheet = build_pc(hp: 30)
      combatant = build_combatant(character, hp_max: 30)
      combatant.update!(hp_current: 0)

      result = described_class.call(combatant: combatant, amount: 8, attack_kind: 'critical')
      expect(result.result[:death_save_failures_added]).to eq(2)
      expect(combatant.reload.death_saves['failures']).to eq(2)
    end

    it 'PC morre quando 3ª falha é registrada via crítico (auto_resolve dispara is_dead)' do
      character, _sheet = build_pc(hp: 30)
      combatant = build_combatant(character, hp_max: 30)
      combatant.update!(hp_current: 0, death_saves: { 'successes' => 0, 'failures' => 1 })

      described_class.call(combatant: combatant, amount: 6, attack_kind: 'critical')
      combatant.reload
      # `auto_resolve_death_saves` callback do model reseta death_saves para
      # 0/0 e marca is_dead=true ao bater 3 falhas.
      expect(combatant.is_dead).to be(true),
        'PHB: 3 falhas de death save = morte. is_dead deveria estar true.'
    end

    it 'PC com hp > 0 NÃO recebe failures por ser atingido normalmente' do
      character, _sheet = build_pc(hp: 30)
      combatant = build_combatant(character, hp_max: 30)
      result = described_class.call(combatant: combatant, amount: 5, attack_kind: 'normal')
      expect(result.result[:death_save_failures_added]).to eq(0)
    end
  end

  # =====================================================================
  #  Concentração check (já existente — regressão)
  # =====================================================================
  describe 'concentration check (preservado da versão pré-Fase-6A)' do
    it 'sinaliza concentration_check_required quando combatente concentrava' do
      character, _sheet = build_pc(hp: 30)
      combatant = build_combatant(character, hp_max: 30, concentrating: true)

      result = described_class.call(combatant: combatant, amount: 12)
      expect(result.result[:concentration_check_required]).to be(true)
      expect(result.result[:concentration_dc]).to eq([10, 6].max)  # max(10, 12/2) = 10
    end

    it 'concentration_dc usa o dano APLICADO (pós-modifiers), não o cru' do
      character, sheet = build_pc(hp: 30)
      sheet.update!(metadata: sheet.metadata.merge('resistances' => ['fogo']))
      combatant = build_combatant(character, hp_max: 30, concentrating: true)

      result = described_class.call(combatant: combatant, amount: 30, damage_type: 'fogo')
      # 30/2 = 15 (resistência), CD = max(10, 15/2=7) = 10
      expect(result.result[:damage_applied]).to eq(15)
      expect(result.result[:concentration_dc]).to eq(10),
        'CD do concentration save deve usar dano FINAL aplicado (pós-resistência), não bruto.'
    end
  end
end
