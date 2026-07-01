# frozen_string_literal: true

require 'rails_helper'

# R5 — Ataques naturais raciais estruturados (grants.natural_weapon nos
# trait_defs): Garras (Aarakocra/Tabaxi), Cascos (Centauro), Chifres (Minotauro).
RSpec.describe 'R5 — natural_weapons', type: :service do
  before { RaceRules.reload! }

  describe 'config/race_rules.yml — grants.natural_weapon' do
    {
      claws_1d4_slashing: %w[Garras 1d4 cortante DEX],
      hooves_1d6_strike: ['Cascos', '1d6', 'contundente', 'STR'],
      minotaur_horns_1d6: ['Chifres', '1d6', 'perfurante', 'STR'],
      cat_claws_1d4_slashing: ['Garras de Gato', '1d4', 'cortante', 'STR'],
    }.each do |key, (name, dice, dtype, ability)|
      it "#{key} define arma natural #{name} #{dice} #{dtype} (#{ability})" do
        nw = RaceRules.trait_definitions.dig(key, :grants, :natural_weapon)
        expect(nw).to include(name: name, dice: dice, damage_type: dtype)
        expect(nw[:ability].to_s).to eq(ability)
      end
    end
  end

  describe 'CharacterSheetSummaryService#build_natural_weapons' do
    let(:user) do
      User.create!(email: "r5_#{SecureRandom.hex(4)}@ex.com", username: "r5#{SecureRandom.hex(4)}",
                   password: 'password1', password_confirmation: 'password1',
                   role_id: Role.find_or_create_by!(name: 'player').id)
    end

    def sheet_for(race_api, sub_api = nil)
      character = Character.create!(user: user, name: "R5 #{SecureRandom.hex(4)}", background: 'Sage')
      race = Race.find_or_create_by!(api_index: race_api) { |r| r.name = race_api.titleize }
      sub = sub_api && SubRace.find_or_create_by!(race_id: race.id, api_index: sub_api) { |s| s.name = sub_api.titleize }
      klass = Klass.find_by(api_index: 'barbarian') || create(:klass, name: 'Bárbaro', api_index: 'barbarian', hit_die: 12)
      sheet = Sheet.create!(character: character, race: race, sub_race: sub,
                            str: 16, dex: 14, con: 14, int: 10, wis: 10, cha: 13,
                            hp_max: 12, hp_current: 12, current_level: 1)
      SheetKlass.create!(sheet: sheet, klass: klass, level: 1) # total_level=1 → prof=2
      sheet.reload
    end

    def weapons(sheet, mods)
      svc = CharacterSheetSummaryService.new(sheet_id: sheet.id, sync: false)
      svc.send(:build_natural_weapons, sheet, abilities: { mods: mods })
    end

    it 'Centauro: Cascos 1d6 contundente, atk = STR mod + prof, dmg = STR mod' do
      out = weapons(sheet_for('centaur'), { str: 3, dex: 2 })
      hoof = out.find { |w| w[:name] == 'Cascos' }
      expect(hoof).to include(dice: '1d6', damage_type: 'contundente', ability: 'STR',
                              attack_bonus: 3 + 2, damage_bonus: 3, proficient: true)
    end

    it 'Aarakocra: Garras 1d4 cortante usam DEX' do
      out = weapons(sheet_for('aarakocra', 'falconicos'), { str: 3, dex: 2 })
      claw = out.find { |w| w[:name] == 'Garras' }
      expect(claw).to include(dice: '1d4', ability: 'DEX', attack_bonus: 2 + 2, damage_bonus: 2)
    end

    it 'raça sem arma natural (Humano) → []' do
      expect(weapons(sheet_for('human', 'standard'), { str: 0 })).to eq([])
    end
  end
end
