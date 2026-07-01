# frozen_string_literal: true

require 'rails_helper'

# R4 — Recursos RACIAIS de uso limitado (grants.uses/grants.dc nos trait_defs):
# Sopro do Dragão (1×/SR-LR, CD 8+Prof+CON), Perseverança Implacável (1×/LR),
# Carga do Centauro (1×/SR-LR). Antes, build_resources era allowlist por classe.
RSpec.describe 'R4 — recursos raciais (build_resources)', type: :service do
  before { RaceRules.reload! }

  describe 'config/race_rules.yml — grants.uses/dc' do
    it 'breath_weapon tem grants.uses (1×) e grants.dc (CON)' do
      g = RaceRules.trait_definitions.dig(:breath_weapon, :grants)
      expect(g.dig(:uses, :value)).to eq(1)
      expect(g.dig(:dc, :ability).to_s).to eq('CON')
    end

    it 'relentless_endurance e centaur_charge têm grants.uses' do
      expect(RaceRules.trait_definitions.dig(:relentless_endurance, :grants, :uses, :value)).to eq(1)
      expect(RaceRules.trait_definitions.dig(:centaur_charge, :grants, :uses, :value)).to eq(1)
    end
  end

  describe 'CharacterSheetSummaryService#merge_race_resources!' do
    let(:user) do
      User.create!(email: "r4_#{SecureRandom.hex(4)}@ex.com", username: "r4#{SecureRandom.hex(4)}",
                   password: 'password1', password_confirmation: 'password1',
                   role_id: Role.find_or_create_by!(name: 'player').id)
    end

    def sheet_for(race_api, sub_api = nil, con: 16, level: 5)
      character = Character.create!(user: user, name: "R4 #{SecureRandom.hex(4)}", background: 'Sage')
      race = Race.find_or_create_by!(api_index: race_api) { |r| r.name = race_api.titleize }
      sub = sub_api && SubRace.find_or_create_by!(race_id: race.id, api_index: sub_api) { |s| s.name = sub_api.titleize }
      klass = Klass.find_or_create_by!(api_index: 'barbarian') { |k| k.name = 'Bárbaro'; k.hit_die = 12 }
      sheet = Sheet.create!(character: character, race: race, sub_race: sub,
                            str: 16, dex: 12, con: con, int: 10, wis: 10, cha: 13,
                            hp_max: 40, hp_current: 40, current_level: level)
      SheetKlass.create!(sheet: sheet, klass: klass, level: level)
      sheet.reload
    end

    def racial_resources(sheet, con_mod:)
      svc = CharacterSheetSummaryService.new(sheet_id: sheet.id, sync: false)
      out = {}
      svc.send(:merge_race_resources!, out, sheet,
               abilities: { mods: { con: con_mod } }, used_for: ->(_k) { 0 })
      out
    end

    it 'Draconato: Sopro do Dragão com CD = 8 + Prof + CON (L5, CON mod +3 → 14)' do
      sheet = sheet_for('dragonborn', 'green', con: 16, level: 5)
      out = racial_resources(sheet, con_mod: 3)
      expect(out[:breath_weapon]).to include(total: 1, recharge: 'SR/LR', source: 'race')
      expect(out[:breath_weapon][:dc]).to eq(8 + 3 + 3) # base + prof(L5=3) + CON mod(+3)
    end

    it 'Meio-Orc: Perseverança Implacável 1×/LR (sem CD)' do
      out = racial_resources(sheet_for('half_orc', nil, level: 1), con_mod: 2)
      expect(out[:relentless_endurance]).to include(total: 1, recharge: 'LR', source: 'race')
      expect(out[:relentless_endurance]).not_to have_key(:dc)
    end

    it 'Centauro: Carga 1×/SR-LR' do
      out = racial_resources(sheet_for('centaur', nil, level: 1), con_mod: 2)
      expect(out[:centaur_charge]).to include(total: 1, recharge: 'SR/LR', source: 'race')
    end

    it 'raça sem recurso racial (Humano) → nada emitido' do
      out = racial_resources(sheet_for('human', 'standard', level: 1), con_mod: 2)
      expect(out).to be_empty
    end
  end
end
