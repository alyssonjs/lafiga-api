# frozen_string_literal: true

require 'rails_helper'

# R6 — Sopro do Dragão: a descrição passou a ter placeholders `<dano>`/`<area>`
# (a metadata {damage,breath} por sub-raça já existia e agora interpola).
RSpec.describe 'R6 — Arma de Sopro (placeholders por ancestralidade)', type: :service do
  before { RaceRules.reload! }

  describe 'config/race_rules.yml (trait_defs)' do
    it 'breath_weapon.description tem placeholders <dano> e <area>' do
      desc = RaceRules.trait_definitions.dig(:breath_weapon, :description).to_s
      expect(desc).to include('<dano>')
      expect(desc).to include('<area>')
    end

    it 'damage_resistance_from_ancestry.description tem placeholder <dano>' do
      desc = RaceRules.trait_definitions.dig(:damage_resistance_from_ancestry, :description).to_s
      expect(desc).to include('<dano>')
    end
  end

  describe 'CharacterSheetSummaryService#interpolate_trait_description' do
    let(:user) do
      User.create!(email: "r6_#{SecureRandom.hex(4)}@ex.com", username: "r6#{SecureRandom.hex(4)}",
                   password: 'password1', password_confirmation: 'password1',
                   role_id: Role.find_or_create_by!(name: 'player').id)
    end
    let(:character) { Character.create!(user: user, name: "R6 #{SecureRandom.hex(4)}", background: 'Sage') }
    let(:race) { Race.find_or_create_by!(api_index: 'dragonborn') { |r| r.name = 'Draconato' } }
    let(:sheet) do
      Sheet.create!(character: character, race: race, str: 14, dex: 10, con: 14, int: 10, wis: 10, cha: 14,
                    hp_max: 10, hp_current: 10, current_level: 1)
    end
    let(:svc) { CharacterSheetSummaryService.new(sheet_id: sheet.id, sync: false) }

    it 'interpola <dano>/<area> a partir da metadata {damage,breath} da sub-raça' do
      out = svc.send(
        :interpolate_trait_description,
        'Ação: sopro de <dano> em <area>; CD = 8 + Prof + CON.',
        { 'damage' => 'Veneno', 'breath' => 'Cone 4,5 m' }
      )
      expect(out).to eq('Ação: sopro de Veneno em Cone 4,5 m; CD = 8 + Prof + CON.')
    end

    it 'cores diferentes → textos diferentes (não mais genérico)' do
      tpl = 'sopro de <dano> em <area>'
      fogo = svc.send(:interpolate_trait_description, tpl, { 'damage' => 'Fogo', 'breath' => 'Cone 4,5 m' })
      acido = svc.send(:interpolate_trait_description, tpl, { 'damage' => 'Ácido', 'breath' => 'Linha 1,5 m x 9 m' })
      expect(fogo).to eq('sopro de Fogo em Cone 4,5 m')
      expect(acido).to eq('sopro de Ácido em Linha 1,5 m x 9 m')
      expect(fogo).not_to eq(acido)
    end
  end
end
