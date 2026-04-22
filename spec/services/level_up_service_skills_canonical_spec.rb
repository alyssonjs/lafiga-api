# frozen_string_literal: true

require 'rails_helper'

# Garante que LevelUpService.ensure_level_requirements! prefere per_level['1'].skills
# como fonte canónica antes de cair para os campos root, e não sobrescreve o root
# quando per_level já contém escolhas válidas.
RSpec.describe LevelUpService, '.ensure_level_requirements! per_level canonical' do
  it 'não sobrescreve class_choices.skills_selected quando per_level["1"].skills já contém picks suficientes' do
    role = Role.find_or_create_by!(name: 'player')
    user = User.create!(
      email: "lu_ec_#{SecureRandom.hex(4)}@example.com",
      username: "luec#{SecureRandom.hex(4)}",
      password: 'password1',
      password_confirmation: 'password1',
      role_id: role.id
    )

    race = Race.create!(name: 'Spec Race', api_index: "spec_race_#{SecureRandom.hex(4)}")
    klass = Klass.find_or_create_by!(api_index: 'rogue') do |k|
      k.name = 'Ladino'
      k.hit_die = 8
      k.subclass_level = 3
    end

    character = Character.create!(user: user, name: 'Spec PC', background: 'Test')
    sheet = Sheet.create!(
      character: character,
      race_id: race.id,
      str: 10, dex: 16, con: 10, int: 10, wis: 10, cha: 10,
      hp_max: 8,
      hp_current: 8,
      metadata: {
        'class_choices' => {
          'skills_selected' => [], # vazio para garantir que NÃO seja sobrescrito por sample
          'per_level' => {
            '1' => { 'skills' => %w[Furtividade Acrobacia Investigação Percepção] }
          }
        }
      }
    )

    sk = SheetKlass.create!(sheet: sheet, klass: klass, level: 1)

    service = LevelUpService.new(sheet_id: sheet.id, klass_id: klass.id, levels: 0)
    service.send(:ensure_level_requirements!, sk, 1)

    sheet.reload
    cc = sheet.metadata['class_choices'] || {}
    expect(cc['skills_selected']).to eq([])
    expect(cc.dig('per_level', '1', 'skills')).to eq(%w[Furtividade Acrobacia Investigação Percepção])
  end
end
