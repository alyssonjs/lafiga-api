# frozen_string_literal: true

require 'rails_helper'

# BDD Fase 6D — CastSpellService consome spell slot da Sheet em combate.
RSpec.describe Combat::CastSpellService, type: :service do
  let(:role) { Role.find_or_create_by!(name: 'player') }
  let(:user) do
    User.create!(email: "css_#{SecureRandom.hex(4)}@example.com",
                 username: "css#{SecureRandom.hex(4)}",
                 password: 'password1', password_confirmation: 'password1', role_id: role.id)
  end
  let(:race)     { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }
  let(:sub_race) { SubRace.find_or_create_by!(race_id: race.id, api_index: 'standard') { |s| s.name = 'Humano Padrão' } }
  let(:character) { Character.create!(user: user, name: 'Wiz', background: 'Test') }
  let!(:sheet) do
    Sheet.create!(character: character, race: race, sub_race: sub_race,
                  str: 10, dex: 12, con: 14, int: 16, wis: 12, cha: 10,
                  hp_max: 8, hp_current: 8, metadata: {})
  end

  it 'incrementa spell_slots_used[level] em SheetRuntimeState' do
    cmd = described_class.call(sheet: sheet, slot_level: 1)
    expect(cmd.success?).to be(true)
    expect(sheet.runtime!.spell_slots_used).to eq({ '1' => 1 })
  end

  it 'soma quando casta múltiplas vezes no mesmo nível' do
    described_class.call(sheet: sheet, slot_level: 1)
    described_class.call(sheet: sheet, slot_level: 1)
    described_class.call(sheet: sheet, slot_level: 2)
    expect(sheet.reload.runtime_state.spell_slots_used).to eq({ '1' => 2, '2' => 1 })
  end

  it 'rejeita slot_level=0 (cantrip não consome slot)' do
    cmd = described_class.call(sheet: sheet, slot_level: 0)
    expect(cmd.success?).to be(false)
    expect(cmd.errors.full_messages.join).to match(/slot_level/i)
  end

  it 'rejeita slot_level acima de 9' do
    cmd = described_class.call(sheet: sheet, slot_level: 10)
    expect(cmd.success?).to be(false)
  end

  it 'aceita spell_name como metadado opcional' do
    cmd = described_class.call(sheet: sheet, slot_level: 3, spell_name: 'Fireball')
    expect(cmd.success?).to be(true)
    expect(cmd.result[:spell_name]).to eq('Fireball')
  end

  it 'rejeita sheet nil' do
    cmd = described_class.call(sheet: nil, slot_level: 1)
    expect(cmd.success?).to be(false)
  end
end
