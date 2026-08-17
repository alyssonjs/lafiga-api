# frozen_string_literal: true

require 'rails_helper'

# TypedDamageService — ataque MULTI-PARCELA (perfurante+fogo+elétrico) mitigado
# POR TIPO no SERVIDOR (resolve o bug de multiplayer: o atacante não tem a ficha
# do alvo, mas o servidor tem via summary). Mitiga cada parcela pelo seu tipo,
# soma, e aplica UMA vez (PV temp/morte 1×).
RSpec.describe Combat::TypedDamageService, type: :service do
  let(:role) { Role.find_or_create_by!(name: 'player') }
  let(:user) do
    User.create!(email: "tds_#{SecureRandom.hex(4)}@example.com",
                 username: "tds#{SecureRandom.hex(4)}",
                 password: 'password1', password_confirmation: 'password1', role_id: role.id)
  end
  let(:race)     { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }
  let(:sub_race) { SubRace.find_or_create_by!(race_id: race.id, api_index: 'standard') { |s| s.name = 'Humano Padrão' } }
  let(:klass) do
    Klass.find_or_create_by!(api_index: 'fighter') { |k| k.name = 'Guerreiro'; k.hit_die = 10; k.subclass_level = 3 }
  end

  def build_pc(hp: 40)
    character = Character.create!(user: user, name: "PC #{SecureRandom.hex(2)}", background: 'Test')
    sheet = Sheet.create!(
      character: character, race: race, sub_race: sub_race,
      str: 14, dex: 14, con: 14, int: 10, wis: 10, cha: 10,
      hp_max: hp, hp_current: hp,
      metadata: { 'class_summary' => {}, 'base_ability_scores' =>
                  { 'str' => 14, 'dex' => 14, 'con' => 14, 'int' => 10, 'wis' => 10, 'cha' => 10 } }
    )
    SheetKlass.create!(sheet: sheet, klass: klass, level: 1)
    [character, sheet.reload]
  end

  def build_combatant(character, hp_max: 40, temp_hp: 0, concentrating: false)
    schedule = create(:schedule)
    cs = CombatState.create!(schedule: schedule, active: true, round: 1, current_turn_index: 0)
    CombatCombatant.create!(
      combat_state: cs, combatable: character, position: 1, name: character.name,
      initiative: 10, initiative_bonus: 0, tie_break_dex: 14,
      hp_current: hp_max, hp_max: hp_max, temp_hp: temp_hp, ac: 16,
      is_concentrating: concentrating
    )
  end

  describe 'multi-parcela sem defesas' do
    it 'soma todas as parcelas e aplica o total' do
      character, _sheet = build_pc(hp: 40)
      combatant = build_combatant(character, hp_max: 40)

      result = described_class.call(combatant: combatant, parcels: [
        { amount: 5, damage_type: 'perfurante' },
        { amount: 6, damage_type: 'fogo' },
        { amount: 7, damage_type: 'relâmpago' },
      ])
      expect(result.success?).to be(true)
      expect(result.result[:damage_applied]).to eq(18)
      expect(combatant.reload.hp_current).to eq(22)
    end
  end

  describe 'imunidade e resistência POR TIPO (cenário Aberama)' do
    it 'zera SÓ o tipo imune e reduz SÓ o tipo resistido' do
      character, sheet = build_pc(hp: 40)
      sheet.update!(metadata: sheet.metadata.merge(
        'damage_immunities' => ['fogo'],
        'resistances' => ['relâmpago']
      ))
      combatant = build_combatant(character, hp_max: 40)

      # perfurante 5 (cheio) + fogo 6 (imune→0) + elétrico 7 (resist→3)
      result = described_class.call(combatant: combatant, parcels: [
        { amount: 5, damage_type: 'perfurante' },
        { amount: 6, damage_type: 'fogo' },
        { amount: 7, damage_type: 'eletrico' }, # front manda 'eletrico' → normaliza p/ 'relâmpago'
      ])
      expect(result.success?).to be(true)
      expect(result.result[:damage_applied]).to eq(8) # 5 + 0 + 3
      breakdown = result.result[:breakdown]
      expect(breakdown.find { |b| b[:damage_type] == 'fogo' }[:modifier]).to eq(:immune)
      expect(breakdown.find { |b| b[:damage_type] == 'fogo' }[:final]).to eq(0)
      expect(breakdown.find { |b| b[:damage_type] == 'relâmpago' }[:modifier]).to eq(:resistant)
      expect(breakdown.find { |b| b[:damage_type] == 'relâmpago' }[:final]).to eq(3)
      expect(combatant.reload.hp_current).to eq(32)
    end
  end

  describe 'vulnerabilidade por tipo' do
    it 'dobra só o tipo vulnerável' do
      character, sheet = build_pc(hp: 40)
      sheet.update!(metadata: sheet.metadata.merge('damage_vulnerabilities' => ['frio']))
      combatant = build_combatant(character, hp_max: 40)

      result = described_class.call(combatant: combatant, parcels: [
        { amount: 5, damage_type: 'frio' },   # ×2 = 10
        { amount: 5, damage_type: 'fogo' },   # cheio
      ])
      expect(result.result[:damage_applied]).to eq(15)
    end
  end

  describe 'PV temporário absorve o TOTAL uma vez (não por parcela)' do
    it 'absorve o total do ataque, não cada parcela' do
      character, _sheet = build_pc(hp: 40)
      combatant = build_combatant(character, hp_max: 40, temp_hp: 10)

      # total 15 → temp 10 absorve, 5 vão pro HP.
      result = described_class.call(combatant: combatant, parcels: [
        { amount: 8, damage_type: 'perfurante' },
        { amount: 7, damage_type: 'fogo' },
      ])
      expect(result.result[:damage_applied]).to eq(15)
      combatant.reload
      expect(combatant.temp_hp).to eq(0)
      expect(combatant.hp_current).to eq(35) # 40 - 5
    end
  end

  describe 'extra_resistances/immunities (condicionais do front — Fúria/Elemental)' do
    it 'aplica resistência extra passada pelo front' do
      character, _sheet = build_pc(hp: 40)
      combatant = build_combatant(character, hp_max: 40)

      result = described_class.call(
        combatant: combatant,
        parcels: [{ amount: 10, damage_type: 'fogo' }],
        extra_resistances: ['fogo']
      )
      expect(result.result[:damage_applied]).to eq(5)
      expect(result.result[:breakdown].first[:modifier]).to eq(:resistant)
    end

    it 'imunidade extra zera o tipo' do
      character, _sheet = build_pc(hp: 40)
      combatant = build_combatant(character, hp_max: 40)

      result = described_class.call(
        combatant: combatant,
        parcels: [{ amount: 10, damage_type: 'necrotico' }],
        extra_immunities: ['necrotico']
      )
      expect(result.result[:damage_applied]).to eq(0)
    end
  end

  describe 'parcelas com chaves STRING (params do controller)' do
    it 'normaliza chaves string e casta magical' do
      character, _sheet = build_pc(hp: 40)
      combatant = build_combatant(character, hp_max: 40)

      result = described_class.call(combatant: combatant, parcels: [
        { 'amount' => '9', 'damage_type' => 'cortante', 'magical' => 'true' },
      ])
      expect(result.success?).to be(true)
      expect(result.result[:damage_applied]).to eq(9)
      expect(result.result[:breakdown].first[:damage_type]).to eq('cortante')
    end
  end

  describe 'concentração sobre o total final' do
    it 'sinaliza concentração e usa o dano final (pós-mitigação)' do
      character, sheet = build_pc(hp: 40)
      sheet.update!(metadata: sheet.metadata.merge('resistances' => ['fogo']))
      combatant = build_combatant(character, hp_max: 40, concentrating: true)

      # fogo 20 (resist→10) + perfurante 4 = 14 total → CD = max(10, 7) = 10
      result = described_class.call(combatant: combatant, parcels: [
        { amount: 20, damage_type: 'fogo' },
        { amount: 4, damage_type: 'perfurante' },
      ])
      expect(result.result[:damage_applied]).to eq(14)
      expect(result.result[:concentration_check_required]).to be(true)
      expect(result.result[:concentration_dc]).to eq(10)
    end
  end

  describe 'death saves (PC a 0 HP)' do
    it 'acerto normal contra PC a 0 HP adiciona +1 falha' do
      character, _sheet = build_pc(hp: 40)
      combatant = build_combatant(character, hp_max: 40)
      combatant.update!(hp_current: 0)

      result = described_class.call(combatant: combatant, parcels: [{ amount: 5, damage_type: 'fogo' }], attack_kind: 'normal')
      expect(result.result[:death_save_failures_added]).to eq(1)
      expect(combatant.reload.death_saves['failures']).to eq(1)
    end
  end

  describe 'validações' do
    it 'falha com parcels vazio' do
      character, _sheet = build_pc(hp: 40)
      combatant = build_combatant(character, hp_max: 40)
      result = described_class.call(combatant: combatant, parcels: [])
      expect(result.success?).to be(false)
    end
  end
  # ⚠️ Bug de campo (16/08): dois danos no MESMO combatente, disparados quase no
  # mesmo instante (dano base da cancao + parcela do dado de Inspiracao), liam o
  # mesmo `hp_current` e a ULTIMA escrita vencia — o outro dano SUMIA. Alvo com
  # 22 PV levou 32+5 e ficou com 17 (= 22-5): os 32 se perderam.
  describe 'aplicacoes em sequencia nao se perdem' do
    it 'dois danos seguidos DESCONTAM os dois (nao sobrescrevem)' do
      character, _sheet = build_pc(hp: 40)
      combatant = build_combatant(character, hp_max: 40)
      combatant.update!(hp_current: 22)

      described_class.call(combatant: combatant, parcels: [{ amount: 32, damage_type: 'fogo' }])
      described_class.call(combatant: combatant, parcels: [{ amount: 5, damage_type: 'fogo' }])

      # 22-32 = 0 (piso), depois 0-5 = 0. O que NAO pode acontecer e sobrar 17
      # (= 22-5, com os 32 ignorados).
      expect(combatant.reload.hp_current).to eq(0)
    end

    it 'somam na ordem quando nao chegam ao piso' do
      character, _sheet = build_pc(hp: 40)
      combatant = build_combatant(character, hp_max: 40)

      described_class.call(combatant: combatant, parcels: [{ amount: 11, damage_type: 'fogo' }])
      described_class.call(combatant: combatant, parcels: [{ amount: 10, damage_type: 'fogo' }])

      expect(combatant.reload.hp_current).to eq(19)
    end

    it 'a aplicacao acontece SOB LOCK (serializa danos concorrentes)' do
      src = File.read(Rails.root.join('app/services/combat/typed_damage_service.rb'))
      expect(src).to match(/@combatant\.with_lock do/)
    end
  end

end
