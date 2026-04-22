# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::CharactersController provision', type: :request do
  describe 'POST /api/v1/player/characters/provision' do
    let(:user) { create(:user) }
    let(:headers) { bearer_headers_for(user) }

    context 'when klass_id is invalid' do
      it 'returns 422' do
        payload = {
          character: { name: 'X', background: 'Y' },
          wizard: {
            meta: { name: 'X', alignmentKey: 'lg' },
            race: {
              raceId: human_race.id,
              subRaceId: human_standard_subrace.id,
              ruleId: 'human',
              subRuleId: 'standard',
              attributes: { str: 16, dex: 14, con: 14, int: 8, wis: 10, cha: 10 },
              raceChoices: { chosenLanguages: ['Anão'] }
            },
            klass: {
              klassId: 9_999_999,
              level: 1,
              classSkillPicks: %w[Atletismo Intimidação],
              classPicksByLevel: { '1' => { 'hp' => { 'dieResult' => 8, 'total' => 10 } } }
            },
            background: { backgroundName: 'Acólito', backgroundKey: 'acolyte' },
            equipment: {},
            avatar: { customization: {} }
          }
        }

        post '/api/v1/player/characters/provision', params: payload, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when payload is a valid L1 barbarian (human standard)' do
      it 'returns 201 with character.main_class.name and sheet_id' do
        race = human_race
        sub = human_standard_subrace(race)
        klass = barbarian_klass
        bg = acolyte_background
        align = lawful_good_alignment

        payload = minimal_l1_barbarian_provision_payload(
          race: race,
          sub_race: sub,
          klass: klass,
          background: bg,
          alignment: align
        )

        post '/api/v1/player/characters/provision', params: payload, headers: headers, as: :json

        expect(response).to have_http_status(:created), -> { response.body }
        json = response.parsed_body
        expect(json.dig('character', 'main_class', 'name')).to eq('Bárbaro')
        expect(json.dig('character', 'sheet_id')).to be_present
        expect(json.dig('character', 'id')).to be_present
      end
    end

    # Regressao: Mestre reprovisionando ficha alheia (wizard de edicao do PC
    # importado) recebia 422 porque o service fazia `owner.characters.find(cid)`
    # com `owner = current_user (DM)` — o char nao pertence ao DM, ActiveRecord
    # levantava RecordNotFound, transaction era rollbackada.
    context 'when DM reprovisions a character owned by another player' do
      let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
      let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
      let(:dm_user) { create(:user, role: dm_role) }
      let(:other_player) { create(:user, role: player_role) }
      let!(:foreign_character) do
        create(:character, user: other_player, status: :active, name: 'Rorinar Original')
      end

      it 'reprovisions preserving the original owner (does not transfer to DM)' do
        race  = human_race
        sub   = human_standard_subrace(race)
        klass = barbarian_klass
        bg    = acolyte_background
        align = lawful_good_alignment

        payload = minimal_l1_barbarian_provision_payload(
          race: race, sub_race: sub, klass: klass, background: bg, alignment: align
        )
        payload[:character][:id] = foreign_character.id
        payload[:character][:name] = 'Rorinar Editado pelo Mestre'

        post '/api/v1/player/characters/provision',
             params: payload, headers: bearer_headers_for(dm_user), as: :json

        expect(response).to have_http_status(:created), -> { response.body }
        foreign_character.reload
        expect(foreign_character.user_id).to eq(other_player.id) # owner intacto
        expect(foreign_character.name).to eq('Rorinar Editado pelo Mestre')
      end
    end
  end
end
