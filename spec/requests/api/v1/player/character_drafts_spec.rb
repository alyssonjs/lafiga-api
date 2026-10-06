# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::CharacterDraftsController', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let!(:character) { create(:character, user: user, status: :draft, draft_data: { 'name' => 'Aria' }) }

  describe 'GET /api/v1/player/character_drafts/:id?step=general' do
    it 'returns the step fragment + meta envelope' do
      get "/api/v1/player/character_drafts/#{character.id}", params: { step: 'general' }, headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['step']).to eq('general')
      expect(json['mode']).to eq('creation')
      expect(json['data']['name']).to eq('Aria')
      expect(json['version']).to eq(CharacterDraftSchema::DRAFT_SCHEMA_VERSION)
    end

    it 'rejects unknown step keys' do
      get "/api/v1/player/character_drafts/#{character.id}", params: { step: 'bogus' }, headers: headers
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe 'PATCH /api/v1/player/character_drafts/:id' do
    it 'persists step fragment into draft_data and bumps current_step' do
      patch "/api/v1/player/character_drafts/#{character.id}", params: {
        step: 'general',
        data: { name: 'Nova Aria', level: 2 }
      }.to_json, headers: headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:ok)
      character.reload
      expect(character.draft_data['name']).to eq('Nova Aria')
      expect(character.draft_data['level']).to eq(2)
      expect(character.draft_data['_version']).to eq(CharacterDraftSchema::DRAFT_SCHEMA_VERSION)
    end

    it 'returns 409 conflict when expected_updated_at is stale' do
      patch "/api/v1/player/character_drafts/#{character.id}", params: {
        step: 'general',
        data: { name: 'X' },
        expected_updated_at: (character.updated_at - 1.hour).iso8601(3)
      }.to_json, headers: headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to eq('conflict')
    end

    it 'returns 409 destructive_change when changing race without force' do
      character.update!(draft_data: {
        '_raceId' => '7', 'selectedRace' => { 'id' => '7' }, '_featId' => 'feat-tough'
      })
      patch "/api/v1/player/character_drafts/#{character.id}", params: {
        step: 'race',
        data: { raceId: '8' }
      }.to_json, headers: headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body['error']).to eq('destructive_change')
      expect(response.parsed_body.dig('requires_confirmation', 'cleared')).to include('selectedFeat')
    end

    it 'allows the destructive change when force: true' do
      character.update!(draft_data: {
        '_raceId' => '7', 'selectedRace' => { 'id' => '7' }, '_featId' => 'feat-tough'
      })
      patch "/api/v1/player/character_drafts/#{character.id}", params: {
        step: 'race',
        data: { raceId: '8' },
        force: true
      }.to_json, headers: headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:ok)
      character.reload
      expect(character.draft_data['_featId']).to be_nil
    end
  end

  # Phase 10 — Bug 13: regressao para o erro 500 que aparecia ao abrir/PATCH a
  # ficha de edicao (status='active' com Sheet associada). O bug original era
  # `NoMethodError: undefined method 'updated_at' for #<Sheet ...>` lancado
  # de `effective_updated_at` quando o cache de schema do Puma estava stale.
  # O fix usa `try(:updated_at)` defensivo + fallback para Time.current — esses
  # specs garantem que ambos os caminhos (com timestamp presente e ausente)
  # respondam com sucesso.
  describe 'edit mode (status: active) — Phase 10 Bug 13 regression' do
    let!(:active_character) { create(:character, user: user, status: :active) }
    let!(:active_sheet)     { create(:sheet, character: active_character) }

    it 'GET /character_drafts/:id?step=general retorna 200 em ficha ativa' do
      get "/api/v1/player/character_drafts/#{active_character.id}",
          params: { step: 'general' }, headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['mode']).to eq('edit')
      expect(json['updated_at']).to be_present
    end

    it 'PATCH /character_drafts/:id step=general retorna 200 em ficha ativa' do
      patch "/api/v1/player/character_drafts/#{active_character.id}", params: {
        step: 'general',
        data: { name: '[Edit] Aria Renomeada', playerName: 'Bob' }
      }.to_json, headers: headers.merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['mode']).to eq('edit')
      expect(json['updated_at']).to be_present
    end

    it 'effective_updated_at sobrevive a Sheet sem updated_at (cache stale simulado)' do
      # Simula a condicao do bug: sheet em memoria respondendo nil para
      # updated_at (como acontecia com cache de schema stale do Puma).
      allow_any_instance_of(Sheet).to receive(:try).with(:updated_at).and_return(nil)

      get "/api/v1/player/character_drafts/#{active_character.id}",
          params: { step: 'general' }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['updated_at']).to be_present
    end
  end

  describe 'PATCH avatar step (from ChibiEditor standalone)' do
    # A aparência em LPC (04/10, a migração chibi → LPC, fase 4): mora em `avatarCustomization.lpc` — objetos e listas
    # aninhados, gravados pelo editor do LPC. O backend não conhece os campos: guarda o que vier.
    let(:lpc_salvo) do
      {
        'v' => 1,
        'corpo' => 'female', 'pele' => 'bronze', 'olhos' => 'green', 'altura' => 0.9,
        'cabelo' => { 'peca' => 'lpc:hair_braid', 'cor' => 'ginger' },
        'barba' => nil,
        'expressao' => 'lpc:face_angry',
        'acessorios' => ['lpc:facial_eyepatch_left']
      }
    end

    context 'creation mode (status: draft)' do
      it 'keeps the LPC appearance (lpc) intact — nested objects, lists and nulls' do
        patch "/api/v1/player/character_drafts/#{character.id}", params: {
          step: 'avatar',
          data: { avatarCustomization: { 'gender' => 'feminine', 'lpc' => lpc_salvo }, avatarUserEdited: true }
        }.to_json, headers: headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:ok)
        expect(character.reload.draft_data.dig('avatarCustomization', 'lpc')).to eq(lpc_salvo)
      end

      it 'lpc: the merge is DEEP — the editor must send the whole lpc, with null for "none"' do
        character.update!(draft_data: { 'avatarCustomization' => { 'lpc' => lpc_salvo } })
        patch "/api/v1/player/character_drafts/#{character.id}", params: {
          step: 'avatar',
          data: {
            avatarCustomization: {
              'lpc' => { 'cabelo' => { 'peca' => 'lpc:hair_long' }, 'expressao' => nil, 'acessorios' => [] }
            }
          }
        }.to_json, headers: headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:ok)
        lpc = character.reload.draft_data.dig('avatarCustomization', 'lpc')
        expect(lpc['cabelo']).to eq('peca' => 'lpc:hair_long', 'cor' => 'ginger') # a chave omitida FICA
        expect(lpc['expressao']).to be_nil                                         # null apaga
        expect(lpc['acessorios']).to eq([])                                        # a lista é trocada inteira
        expect(lpc['corpo']).to eq('female')
      end

      it 'persists avatarCustomization into draft_data via AvatarStepService' do
        patch "/api/v1/player/character_drafts/#{character.id}", params: {
          step: 'avatar',
          data: {
            avatarCustomization: {
              outfit: 'wizard-robe',
              outfitColors: { primary: 'blue', secondary: 'gold' }
            }
          }
        }.to_json, headers: headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:ok)
        character.reload
        expect(character.draft_data['avatarCustomization']).to include(
          'outfit' => 'wizard-robe',
          'outfitColors' => { 'primary' => 'blue', 'secondary' => 'gold' }
        )
      end

      it 'persists avatarUserEdited flag at root of draft_data' do
        patch "/api/v1/player/character_drafts/#{character.id}", params: {
          step: 'avatar',
          data: {
            avatarCustomization: { outfit: 'barbarian-fur' },
            avatarUserEdited: true
          }
        }.to_json, headers: headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:ok)
        character.reload
        expect(character.draft_data['avatarUserEdited']).to be(true)
        expect(character.draft_data['avatarCustomization']).to include('outfit' => 'barbarian-fur')
      end

      it 'deep merges nested customization (preserves keys not sent)' do
        character.update!(draft_data: {
          'avatarCustomization' => {
            'outfit' => 'wizard-robe',
            'outfitColors' => { 'primary' => 'red', 'secondary' => 'blue', 'accent' => 'gold' }
          }
        })
        patch "/api/v1/player/character_drafts/#{character.id}", params: {
          step: 'avatar',
          data: {
            avatarCustomization: { 'outfitColors' => { 'primary' => 'green' } }
          }
        }.to_json, headers: headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:ok)
        character.reload
        expect(character.draft_data['avatarCustomization']).to include(
          'outfit' => 'wizard-robe',
          'outfitColors' => { 'primary' => 'green', 'secondary' => 'blue', 'accent' => 'gold' }
        )
      end

      it 'returns avatar step data in response' do
        patch "/api/v1/player/character_drafts/#{character.id}", params: {
          step: 'avatar',
          data: {
            avatarCustomization: { outfit: 'cleric-robes' },
            avatarUserEdited: true
          }
        }.to_json, headers: headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['step']).to eq('avatar')
        expect(json['mode']).to eq('creation')
        expect(json['data']['avatarUserEdited']).to be(true)
        expect(json['data']['avatarCustomization']).to include('outfit' => 'cleric-robes')
      end
    end

    context 'edit mode (status: active with Sheet)' do
      let!(:active_character) { create(:character, user: user, status: :active) }
      let!(:active_sheet) do
        create(:sheet, character: active_character, avatar_customization: {
          'outfit' => 'paladin-plate',
          'outfitColors' => { 'primary' => 'white', 'secondary' => 'gold' }
        })
      end

      it 'persists avatarCustomization into Sheet.avatar_customization via AvatarEditService' do
        patch "/api/v1/player/character_drafts/#{active_character.id}", params: {
          step: 'avatar',
          data: {
            avatarCustomization: { 'outfit' => 'ranger-leathers' }
          }
        }.to_json, headers: headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:ok)
        active_sheet.reload
        expect(active_sheet.avatar_customization).to include('outfit' => 'ranger-leathers')
      end

      it 'persists the LPC appearance (lpc) into Sheet.avatar_customization' do
        patch "/api/v1/player/character_drafts/#{active_character.id}", params: {
          step: 'avatar',
          data: { avatarCustomization: { 'lpc' => lpc_salvo }, avatarUserEdited: true }
        }.to_json, headers: headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:ok)
        active_sheet.reload
        expect(active_sheet.avatar_customization['lpc']).to eq(lpc_salvo)
        expect(active_sheet.avatar_customization['outfit']).to eq('paladin-plate')
      end

      it 'deep merges Sheet avatar_customization (preserves keys not sent)' do
        patch "/api/v1/player/character_drafts/#{active_character.id}", params: {
          step: 'avatar',
          data: {
            avatarCustomization: { 'outfitColors' => { 'primary' => 'red' } }
          }
        }.to_json, headers: headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:ok)
        active_sheet.reload
        expect(active_sheet.avatar_customization).to include(
          'outfit' => 'paladin-plate',
          'outfitColors' => { 'primary' => 'red', 'secondary' => 'gold' }
        )
      end

      it 'persists _userEdited flag inside Sheet.avatar_customization' do
        patch "/api/v1/player/character_drafts/#{active_character.id}", params: {
          step: 'avatar',
          data: {
            avatarCustomization: { 'outfit' => 'fighter-plate' },
            avatarUserEdited: true
          }
        }.to_json, headers: headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:ok)
        active_sheet.reload
        expect(active_sheet.avatar_customization['_userEdited']).to be(true)
        expect(active_sheet.avatar_customization['outfit']).to eq('fighter-plate')
      end

      it 'returns avatar step data with userEdited flag in response' do
        patch "/api/v1/player/character_drafts/#{active_character.id}", params: {
          step: 'avatar',
          data: {
            avatarCustomization: { 'outfit' => 'bard-silks' },
            avatarUserEdited: true
          }
        }.to_json, headers: headers.merge('Content-Type' => 'application/json')

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['step']).to eq('avatar')
        expect(json['mode']).to eq('edit')
        expect(json['data']['avatarUserEdited']).to be(true)
        expect(json['data']['avatarCustomization']).to include('outfit' => 'bard-silks')
      end
    end
  end

  # Regressao: Mestre nao conseguia editar fichas importadas (`/character/:id/edit`
  # de PCs alheios) — todo PATCH/GET retornava 404 porque `load_character` filtrava
  # por `current_user.characters`. DM/Admin (criterio canonico
  # `Group.user_is_dm?`) deve poder editar qualquer ficha; player comum continua
  # restrito as proprias.
  describe 'DM/Admin scope on load_character' do
    let(:dm_role) { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
    let(:admin_role) { Role.find_by(name: 'Admin') || create(:role, name: 'Admin') }
    let(:other_player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }

    let(:dm_user) { create(:user, role: dm_role) }
    let(:admin_user) { create(:user, role: admin_role) }
    let(:other_player) { create(:user, role: other_player_role) }
    let!(:foreign_character) do
      create(:character, user: other_player, status: :draft, draft_data: { 'name' => 'Rorinar Mock' })
    end

    it 'allows DM to GET another player draft' do
      get "/api/v1/player/character_drafts/#{foreign_character.id}",
          params: { step: 'general' },
          headers: bearer_headers_for(dm_user)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['data']['name']).to eq('Rorinar Mock')
    end

    it 'allows Admin to PATCH another player draft' do
      patch "/api/v1/player/character_drafts/#{foreign_character.id}",
            params: { step: 'general', data: { name: 'Editado pelo Mestre', level: 4 } }.to_json,
            headers: bearer_headers_for(admin_user).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:ok)
      expect(foreign_character.reload.draft_data['name']).to eq('Editado pelo Mestre')
    end

    # 06/10: o botao "Editar avatar" do hub passou a aparecer para o Mestre tambem — ele grava pelo MESMO endpoint do
    # jogador (`updateCharacterAvatar`, step `avatar`), entao o escopo do DM tem de valer tambem para esse passo.
    it 'allows DM to PATCH the AVATAR of another player character' do
      patch "/api/v1/player/character_drafts/#{foreign_character.id}",
            params: { step: 'avatar', data: { avatarCustomization: { 'skinColor' => '#C49A6C', 'lpc' => { 'v' => 1 } } } }.to_json,
            headers: bearer_headers_for(dm_user).merge('Content-Type' => 'application/json')

      expect(response).to have_http_status(:ok)
      gravado = foreign_character.reload.draft_data['avatarCustomization']
      expect(gravado['skinColor']).to eq('#C49A6C')
      expect(gravado['lpc']).to eq({ 'v' => 1 })
    end

    it 'still returns 404 to a non-DM player accessing someone else\'s draft' do
      get "/api/v1/player/character_drafts/#{foreign_character.id}",
          params: { step: 'general' },
          headers: bearer_headers_for(create(:user, role: other_player_role))

      expect(response).to have_http_status(:not_found)
    end
  end
end
