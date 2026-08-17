# frozen_string_literal: true

require 'rails_helper'

# Colegio da Bravura (Bardo) L3 — "Proficiencia Adicional".
#
# Diretriz: front-lafiga/src/docs/class-feature-directives/bard/subclasses/
#           colegio-da-bravura.md  (ancoras F3.1, F3.2, F3.5)
#
# O grant vive ANINHADO na feature dentro de `levels_json`
# (`row['features'][i]['grants']['proficiencies']`), nao em `row['grants']` —
# o caminho que `build_proficiencies` precisa percorrer. Estas specs travam o
# fluxo YAML -> SubKlass#levels_json -> summary da ficha, incluindo o gate de
# NIVEL (a feature so vale do 3o em diante).
RSpec.describe CharacterSheetSummaryService, 'Colegio da Bravura — proficiencias de subclasse' do
  let!(:role) { Role.find_or_create_by!(name: 'player') }
  let(:user) do
    User.create!(
      email: "valor_#{SecureRandom.hex(4)}@example.com",
      username: "valor#{SecureRandom.hex(4)}",
      password: 'password1',
      password_confirmation: 'password1',
      role_id: role.id
    )
  end

  let!(:human) { Race.find_or_create_by!(api_index: 'human') { |r| r.name = 'Humano' } }

  let!(:bard) do
    Klass.find_or_create_by!(api_index: 'bard') do |k|
      k.name = 'Bardo'
      k.hit_die = 8
      k.subclass_level = 3
    end
  end

  # Fixture explicito com o MESMO shape do import real (grants aninhado na
  # feature) — o spec nao depende do estado do banco de dev.
  let!(:valor) do
    sk = SubKlass.find_or_initialize_by(api_index: 'valor')
    sk.klass = bard
    sk.name = 'Colegio da Bravura'
    sk.levels_json = JSON.generate([
      {
        'level' => 3,
        'features' => [
          {
            'name' => 'Proficiencia Adicional',
            'grants' => {
              'proficiencies' => {
                'armor' => ['armaduras médias', 'escudos'],
                'weapons' => ['armas marciais']
              }
            }
          },
          { 'name' => 'Inspiracao em Combate' }
        ]
      },
      { 'level' => 6,  'features' => [{ 'name' => 'Ataque Extra' }] },
      { 'level' => 14, 'features' => [{ 'name' => 'Magia de Batalha' }] }
    ])
    sk.save!
    sk
  end

  def build_bard_sheet(level:, with_subclass: true)
    character = Character.create!(user: user, name: 'Bardo da Bravura', background: 'Artista')
    sheet = Sheet.create!(
      character: character,
      race_id: human.id,
      str: 10, dex: 14, con: 12, int: 10, wis: 10, cha: 16,
      hp_max: 20, hp_current: 20,
      race_summary: { 'name' => 'Humano' },
      class_summary: {
        'armor_proficiencies' => ['armaduras leves'],
        'weapon_proficiencies' => ['armas simples']
      },
      background_summary: { 'name' => 'Artista' },
      metadata: { 'class_choices' => {} }
    )
    SheetKlass.create!(
      sheet: sheet, klass: bard, level: level,
      sub_klass: with_subclass ? valor : nil
    )
    sheet
  end

  def proficiencies_for(sheet)
    cmd = CharacterSheetSummaryService.call(sheet_id: sheet.id, sync: false)
    expect(cmd.success?).to be(true), -> { cmd.errors.full_messages.join('; ') rescue cmd.inspect }
    prof = cmd.result[:proficiencies] || {}
    {
      armor: Array(prof[:armor] || prof['armor']).map(&:to_s),
      weapons: Array(prof[:weapons] || prof['weapons']).map(&:to_s)
    }
  end

  it 'F3.1 — nivel 3 concede proficiencia com armaduras medias e escudos' do
    prof = proficiencies_for(build_bard_sheet(level: 3))
    expect(prof[:armor]).to include('armaduras médias', 'escudos')
  end

  it 'F3.2 — nivel 3 concede proficiencia com armas marciais' do
    prof = proficiencies_for(build_bard_sheet(level: 3))
    expect(prof[:weapons]).to include('armas marciais')
  end

  it 'F3.2b — NAO concede armadura pesada' do
    prof = proficiencies_for(build_bard_sheet(level: 10))
    expect(prof[:armor]).not_to include('armaduras pesadas')
  end

  it 'F3.5 — as proficiencias da CLASSE continuam presentes (grant soma, nao substitui)' do
    prof = proficiencies_for(build_bard_sheet(level: 3))
    expect(prof[:armor]).to include('armaduras leves')
    expect(prof[:weapons]).to include('armas simples')
  end

  it 'F3.4 — o MODELO impede subclasse antes do nivel 3 (gate mais forte que o summary)' do
    # Nao ha como um Bardo L2 ter a Bravura: `SheetKlass` valida o nivel de
    # subclasse. O gate de nivel da feature, portanto, e garantido na origem —
    # o summary nunca chega a ver esse caso.
    expect { build_bard_sheet(level: 2) }
      .to raise_error(ActiveRecord::RecordInvalid, /nivel 3|nível 3/i)
  end

  it 'F3.4b — Bardo SEM subclasse nao recebe as proficiencias' do
    prof = proficiencies_for(build_bard_sheet(level: 10, with_subclass: false))
    expect(prof[:armor]).not_to include('armaduras médias')
    expect(prof[:weapons]).not_to include('armas marciais')
  end
end
