# frozen_string_literal: true

require 'rails_helper'

# BDD Fase 6C — EndService sincroniza runtime state pós-combate.
# ----------------------------------------------------------------
# Antes da Fase 6C: ao terminar o combate, conditions/concentration/
# death_saves de cada CombatCombatant ficavam órfãos. Próxima sessão
# começava zerada — PC concentrando em Hold Person perdia a magia,
# condições aplicadas (paralisado, atordoado) sumiam.
#
# Agora `EndService` copia esses campos para `SheetRuntimeState` (model
# canônico fora-de-combate), via `runtime!.apply_patch!`.
RSpec.describe Combat::EndService, 'Fase 6C — round-trip runtime state', type: :service do
  let(:role) { Role.find_or_create_by!(name: 'player') }
  let(:user) do
    User.create!(email: "ers_#{SecureRandom.hex(4)}@example.com",
                 username: "ers#{SecureRandom.hex(4)}",
                 password: 'password1', password_confirmation: 'password1', role_id: role.id)
  end
  let(:race)     { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }
  let(:sub_race) { SubRace.find_or_create_by!(race_id: race.id, api_index: 'standard') { |s| s.name = 'Humano Padrão' } }
  let(:klass) do
    Klass.find_or_create_by!(api_index: 'fighter') { |k| k.name = 'Guerreiro'; k.hit_die = 10; k.subclass_level = 3 }
  end

  let(:character) do
    Character.create!(user: user, name: "PC #{SecureRandom.hex(2)}", background: 'Test')
  end
  let!(:sheet) do
    s = Sheet.create!(
      character: character, race: race, sub_race: sub_race,
      str: 14, dex: 14, con: 14, int: 10, wis: 10, cha: 10,
      hp_max: 30, hp_current: 30,
      metadata: {}
    )
    SheetKlass.create!(sheet: s, klass: klass, level: 1)
    s
  end

  let(:schedule) { create(:schedule) }
  let!(:combat_state) do
    CombatState.create!(schedule: schedule, active: true, round: 3, current_turn_index: 0)
  end

  def make_combatant(conditions:, concentrating: false, concentration_spell: nil, death_saves: nil)
    CombatCombatant.create!(
      combat_state: combat_state, combatable: character, position: 1, name: character.name,
      initiative: 12, initiative_bonus: 2, tie_break_dex: 14,
      hp_current: 18, hp_max: 30, ac: 16, temp_hp: 0,
      is_concentrating: concentrating, concentration_spell: concentration_spell,
      conditions: conditions, death_saves: death_saves || { 'successes' => 0, 'failures' => 0 }
    )
  end

  it 'sincroniza CONDITIONS do combatente para SheetRuntimeState' do
    make_combatant(conditions: [
      { 'id' => 'paralyzed', 'turns_left' => 2 },
      { 'id' => 'poisoned',  'turns_left' => 4 }
    ])

    cmd = described_class.call(schedule: schedule)
    expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }

    runtime = sheet.reload.runtime_state
    expect(runtime).to be_present
    ids = runtime.conditions.map { |c| c['id'] }
    expect(ids).to contain_exactly('paralyzed', 'poisoned'),
      "Condições do combate deveriam migrar para runtime_state.conditions. Atual: #{runtime.conditions.inspect}"
  end

  it 'sincroniza CONCENTRATION (spell name) para SheetRuntimeState' do
    make_combatant(conditions: [], concentrating: true, concentration_spell: 'Hold Person')

    described_class.call(schedule: schedule)

    runtime = sheet.reload.runtime_state
    expect(runtime.concentration).to eq('Hold Person'),
      "PC concentrando em magia ao fim do combate deveria preservar em runtime_state.concentration. " \
      "Atual: #{runtime.concentration.inspect}"
  end

  it 'limpa concentration quando combatante NÃO está concentrando' do
    # Setup: runtime state com concentration prévia. Após combate sem
    # concentrating, runtime deveria zerar.
    sheet.create_runtime_state!(concentration: 'Stale Spell')
    make_combatant(conditions: [], concentrating: false)

    described_class.call(schedule: schedule)

    expect(sheet.reload.runtime_state.concentration).to be_nil,
      'concentration deve ser limpo quando o PC já não está concentrando.'
  end

  it 'preserva death_saves (em PCs inconscientes que sobreviveram via 3 sucessos)' do
    make_combatant(
      conditions: [],
      death_saves: { 'successes' => 2, 'failures' => 1 }
    )

    described_class.call(schedule: schedule)

    runtime = sheet.reload.runtime_state
    saves = runtime.death_saves
    expect(saves['successes']).to eq(2)
    expect(saves['failures']).to eq(1)
  end

  it 'HP/temp_hp continuam sincronizados na Sheet (regressão pre-Fase 6C)' do
    make_combatant(conditions: [])
    described_class.call(schedule: schedule)
    expect(sheet.reload.hp_current).to eq(18)  # combatant tinha 18, vai pra sheet
  end
end
