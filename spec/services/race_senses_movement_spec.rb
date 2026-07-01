# frozen_string_literal: true

require 'rails_helper'

# R1 — Sentidos (darkvision) e deslocamentos especiais (voo/escalada) raciais.
# Antes: `CharacterSheetSummaryService` fazia `.slice(:speed_ft,:speed_m)` e
# descartava a darkvision já calculada; voo/escalada nem eram modelados.
RSpec.describe 'R1 — senses & special movement (raças)', type: :service do
  before { RaceRules.reload! }

  describe 'RaceRules.apply — darkvision' do
    it 'Anão: 60 ft' do
      expect(RaceRules.apply(race_id: 'dwarf', subrace_id: 'hill', choices: {})[:darkvision]).to eq(60)
    end

    it 'Drow: 120 ft (Visão no Escuro Superior sobrescreve os 60 do elfo)' do
      expect(RaceRules.apply(race_id: 'elf', subrace_id: 'drow', choices: {})[:darkvision]).to eq(120)
    end

    it 'Aarakocra Nocturnos: 60 ft derivado do TRAIT de sub-raça (sem chave top-level)' do
      expect(RaceRules.apply(race_id: 'aarakocra', subrace_id: 'nocturnos', choices: {})[:darkvision]).to eq(60)
    end

    it 'Aarakocra Falcônicos: sem darkvision (nil)' do
      expect(RaceRules.apply(race_id: 'aarakocra', subrace_id: 'falconicos', choices: {})[:darkvision]).to be_nil
    end

    it 'Draconato: sem darkvision (nil)' do
      expect(RaceRules.apply(race_id: 'dragonborn', subrace_id: 'green', choices: {})[:darkvision]).to be_nil
    end
  end

  describe 'RaceRules.apply — movement (voo/escalada)' do
    it 'Aarakocra: voo 50 ft (15 m), todas as sub-raças' do
      %w[falconicos nocturnos cypselanos].each do |s|
        mv = RaceRules.apply(race_id: 'aarakocra', subrace_id: s, choices: {})[:movement]
        expect(mv[:fly_ft]).to eq(50)
      end
    end

    it 'Tabaxi: escalada 20 ft (6 m)' do
      mv = RaceRules.apply(race_id: 'tabaxi', subrace_id: nil, choices: {})[:movement]
      expect(mv[:climb_ft]).to eq(20)
    end

    it 'raças sem deslocamento especial → movement vazio' do
      expect(RaceRules.apply(race_id: 'human', subrace_id: 'standard', choices: {})[:movement]).to eq({})
      expect(RaceRules.apply(race_id: 'dwarf', subrace_id: 'hill', choices: {})[:movement]).to eq({})
    end
  end

  describe 'CharacterSheetSummaryService — senses & movement' do
    let(:user) do
      User.create!(
        email: "r1_#{SecureRandom.hex(4)}@ex.com", username: "r1#{SecureRandom.hex(4)}",
        password: 'password1', password_confirmation: 'password1',
        role_id: Role.find_or_create_by!(name: 'player').id,
      )
    end
    def sheet_for(race_api, sub_api = nil)
      character = Character.create!(user: user, name: "R1 #{SecureRandom.hex(4)}", background: 'Sage')
      race = Race.find_or_create_by!(api_index: race_api) { |r| r.name = race_api.titleize }
      sub = sub_api && SubRace.find_or_create_by!(race_id: race.id, api_index: sub_api) { |s| s.name = sub_api.titleize }
      Sheet.create!(character: character, race: race, sub_race: sub,
                    str: 10, dex: 12, con: 12, int: 10, wis: 10, cha: 10,
                    hp_max: 8, hp_current: 8, current_level: 1)
    end

    it 'expõe senses.darkvision (Drow 120) e dobra voo (Aarakocra)' do
      svc = CharacterSheetSummaryService.new(sheet_id: sheet_for('elf', 'drow').id, sync: false)
      profile = RaceProfileService.new(svc.instance_variable_get(:@sheet)).call
      expect(svc.send(:build_race_senses, profile)).to eq(darkvision_ft: 120, darkvision_m: 36.6)

      aara = sheet_for('aarakocra', 'falconicos')
      mv = svc.send(:apply_race_special_speeds!, { speed_ft: 25, speed_m: 7.6 }, aara)
      expect(mv[:fly_ft]).to eq(50)
      expect(mv[:fly_m]).to eq(15.2)
    end

    it 'darkvision ausente → senses vazio (Humano)' do
      svc = CharacterSheetSummaryService.new(sheet_id: sheet_for('human', 'standard').id, sync: false)
      profile = RaceProfileService.new(svc.instance_variable_get(:@sheet)).call
      expect(svc.send(:build_race_senses, profile)).to eq({})
    end
  end
end
