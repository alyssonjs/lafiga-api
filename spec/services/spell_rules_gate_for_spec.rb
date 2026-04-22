# frozen_string_literal: true

require 'rails_helper'

# Phase 2.2.D — Regressão: `gate_for` alimenta o auto-pick de `persist_known_spells!`.
# Sem fallbacks, DB de teste sem `spell_slots` / `pact_slot_level` fazia o gate = 0
# (ranger) ou = 1 para todo bruxo (pool só de 1º nível, 6 magias → trava no 7º).
RSpec.describe SpellRules, '.gate_for' do
  let(:role) { Role.find_or_create_by!(name: 'player') }
  let(:user) do
    User.create!(
      email: "sr_gate_#{SecureRandom.hex(4)}@example.com",
      username: "srgate#{SecureRandom.hex(4)}",
      password: 'password1', password_confirmation: 'password1',
      role_id: role.id
    )
  end
  let(:race) { Race.find_by(api_index: 'human') || Race.create!(name: 'Humano', api_index: 'human') }

  def sheet_with(klass_api:, klass_level:)
    klass = Klass.find_by!(api_index: klass_api)
    character = Character.create!(user: user, name: "Gate #{SecureRandom.hex(2)}", background: 'Test')
    sheet = Sheet.create!(
      character: character,
      race_id: race.id,
      str: 10, dex: 10, con: 10, int: 10, wis: 10, cha: 14,
      hp_max: 8, hp_current: 8
    )
    SheetKlass.create!(sheet: sheet, klass: klass, level: klass_level)
    sheet.reload
  end

  it 'bruxo L6 usa nível de slot de pacto PHB (3) quando pact_slot_level está nil no DB' do
    sheet = sheet_with(klass_api: 'warlock', klass_level: 6)
    klass = Klass.find_by!(api_index: 'warlock')
    expect(described_class.gate_for(sheet, klass)).to eq(3)
  end

  it 'ranger L2 usa floor(nível/2) quando spell_slots está vazio no DB' do
    sheet = sheet_with(klass_api: 'ranger', klass_level: 2)
    klass = Klass.find_by!(api_index: 'ranger')
    expect(described_class.gate_for(sheet, klass)).to eq(1)
  end

  it 'mago L5 usa teto integral (3) quando spell_slots está vazio no DB' do
    sheet = sheet_with(klass_api: 'wizard', klass_level: 5)
    klass = Klass.find_by!(api_index: 'wizard')
    expect(described_class.gate_for(sheet, klass)).to eq(3)
  end
end
