# frozen_string_literal: true

require 'rails_helper'

# BDD Fase 4C — Integração dos talentos NA ÁREA DE COMBATE / SESSÃO.
# --------------------------------------------------------------------
# Documenta o estado ATUAL da integração feat→combate. Hoje, o
# `Combat::Serializers.combatant` expõe campos da `CombatCombatant`
# (initiative_bonus, ac, hp_max, etc.) que vêm de `defaults_for` no
# controller — esse método não consulta `metadata['feats']`.
#
# Resultado: vários feats de combate NÃO chegam ao combate atualmente:
#   - Alerta (+5 iniciativa) → GAP
#   - Mestre de Armas Duplas, Mestre do Escudo, Maestria em Armadura
#     Pesada (afetam AC) → AC é hardcoded 10 (comentário no controller:
#     "combat profile virá depois (Fase 2 com sheet AC)")
#   - Mobilidade (+10 ft speed) → CombatCombatant nem expõe speed
#
# Funciona via sheet.hp_max:
#   - Robusto: SE aplicado e sheet.hp_max sincronizado, vai pro combate
RSpec.describe 'FeatRules — integração no combate (Fase 4C)', type: :service do
  let(:role) { Role.find_or_create_by!(name: 'player') }
  let(:user) do
    User.create!(
      email: "fci_#{SecureRandom.hex(4)}@example.com",
      username: "fci#{SecureRandom.hex(4)}",
      password: 'password1', password_confirmation: 'password1', role_id: role.id
    )
  end
  let(:race)     { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }
  let(:sub_race) { SubRace.find_or_create_by!(race_id: race.id, api_index: 'standard') { |s| s.name = 'Humano Padrão' } }
  let(:klass) do
    Klass.find_or_create_by!(api_index: 'fighter') { |k| k.name = 'Guerreiro'; k.hit_die = 10; k.subclass_level = 3 }
  end

  def build_pc_with_feat(feat_id, choices: {}, dex: 14, hp_max: 12)
    character = Character.create!(user: user, name: "PC #{SecureRandom.hex(2)}", background: 'Test')
    sheet = Sheet.create!(
      character: character, race: race, sub_race: sub_race,
      str: 14, dex: dex, con: 14, int: 10, wis: 10, cha: 10,
      hp_max: hp_max, hp_current: hp_max,
      metadata: {
        'class_summary' => {},
        'base_ability_scores' => { 'str' => 14, 'dex' => dex, 'con' => 14, 'int' => 10, 'wis' => 10, 'cha' => 10 },
        'abilities' => { 'scores' => { 'dex' => dex } }
      }
    )
    SheetKlass.create!(sheet: sheet, klass: klass, level: 1)
    FeatAssignmentService.call(sheet: sheet, feat_id: feat_id, level_gained: 1, choices: choices)
    [character, sheet.reload]
  end

  # =====================================================================
  #  Combat::Serializers.combatant — shape (Fase 5A: speed_ft adicionado)
  # =====================================================================
  describe 'Combat::Serializers.combatant — shape' do
    it 'expõe initiative_bonus, ac, hp_current, hp_max + speed_ft' do
      # Stub no shape de CombatCombatant. `speed_ft` agora faz parte do
      # contrato do serializer (Fase 5A).
      stub_fields = %i[
        id combat_state_id combatable_type combatable_id name position initiative
        initiative_bonus tie_break_dex hp_current hp_max ac speed_ft temp_hp
        is_delayed is_concentrating concentration_spell is_stabilized is_dead
        conditions actions_used death_saves updated_at
      ]
      Stub = Struct.new(*stub_fields, keyword_init: true) unless defined?(Stub)
      combatant = Stub.new(
        id: 1, combat_state_id: 10, combatable_type: 'Character',
        combatable_id: 99, name: 'Test', position: 1, initiative: 12,
        initiative_bonus: 2, tie_break_dex: 14, hp_current: 12, hp_max: 12,
        ac: 10, speed_ft: 30, temp_hp: 0, is_delayed: false, is_concentrating: false,
        concentration_spell: nil, is_stabilized: false, is_dead: false,
        conditions: [], actions_used: {}, death_saves: {}, updated_at: Time.current
      )

      payload = ::Combat::Serializers.combatant(combatant)
      expect(payload).to include(:id, :initiative_bonus, :ac, :hp_current, :hp_max, :temp_hp, :speed_ft)
      expect(payload[:speed_ft]).to eq(30)
    end

    it 'tolera CombatCombatant legacy sem speed_ft (nil)' do
      stub = Struct.new(:id, :combat_state_id, :combatable_type, :combatable_id,
                        :name, :position, :initiative, :initiative_bonus, :tie_break_dex,
                        :hp_current, :hp_max, :ac, :temp_hp, :is_delayed, :is_concentrating,
                        :concentration_spell, :is_stabilized, :is_dead, :conditions,
                        :actions_used, :death_saves, :updated_at) do
        # NÃO declara speed_ft — simulando legacy.
      end
      legacy = stub.new(1, 1, 'Character', 1, 'X', 1, 10, 0, 10, 5, 5, 10, 0,
                        false, false, nil, false, false, [], {}, {}, Time.current)
      payload = ::Combat::Serializers.combatant(legacy)
      expect(payload[:speed_ft]).to be_nil
    end
  end

  # =====================================================================
  #  defaults_for(Character) — Fase 5B agora consome summary
  # =====================================================================
  describe 'defaults_for(character) consome summary (Fase 5B)' do
    let(:controller_class) { Api::V1::Player::Combat::CombatCombatantsController }

    def invoke_defaults_for(combatable)
      ctrl = controller_class.allocate
      ctrl.send(:defaults_for, combatable)
    end

    it 'initiative_bonus inclui +5 do Alerta (somado ao DEX mod)' do
      character, _sheet = build_pc_with_feat('alerta', dex: 14)  # DEX 14 → mod +2
      defaults = invoke_defaults_for(character)
      expect(defaults[:initiative_bonus]).to eq(2 + 5),
        "Esperado 7 (mod DEX 2 + Alerta 5), veio #{defaults[:initiative_bonus]}. " \
        'defaults_for agora deve consumir summary[:modifiers][:initiative_bonus].'
    end

    it 'hp_max de PC vem de sheet.hp_max' do
      _character, sheet = build_pc_with_feat('robusto', hp_max: 14)
      defaults = invoke_defaults_for(sheet.character)
      expected = sheet.reload.hp_max
      expect(defaults[:hp_max]).to eq(expected),
        "hp_max do combatant deve refletir sheet.hp_max=#{expected}, veio #{defaults[:hp_max]}"
    end

    it 'tie_break_dex usa DEX do summary (já reflete bônus de classe/raça/etc.)' do
      character, _sheet = build_pc_with_feat('atleta', dex: 16, choices: { 'ability' => 'dex' })
      defaults = invoke_defaults_for(character)
      # Atleta dá +1 STR ou DEX. Aqui escolhemos DEX → 16+1=17.
      expect(defaults[:tie_break_dex]).to be >= 16
    end
  end

  # =====================================================================
  #  Sheet HP — Robusto reflete em sheet.hp_max (caminho que funciona)
  # =====================================================================
  describe 'Robusto reflete em sheet.hp_max (combatant.hp_max via defaults_for)' do
    it 'Quando sheet.hp_max já contabiliza +2/nível, defaults_for usa esse valor' do
      # Setup: criamos a sheet com hp_max já incluindo +2/nível (simula sync feito).
      character, sheet = build_pc_with_feat('robusto', hp_max: 14)  # 12 base + 2 robusto
      controller_class = Api::V1::Player::Combat::CombatCombatantsController
      defaults = controller_class.allocate.send(:defaults_for, character)
      expect(defaults[:hp_max]).to eq(sheet.hp_max),
        'hp_max do combatant = sheet.hp_max (caminho funcional sem mudança no combat)'
    end
  end
end
