# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::GroupsController', type: :request do
  # Nome unico — evita colidir com seeds/roles legados onde `find_by(name:
  # 'Player')` poderia nao ser o papel esperado em alguns ambientes.
  let(:player_role) { Role.find_or_create_by!(name: 'LafigaRSpecPlayerOnly') { |r| r.permissions = [] } }
  let(:dm_role)     { Role.find_by(name: 'Admin') || create(:role, name: 'Admin') }
  let(:user)        { create(:user, role: player_role) }
  let(:other_user)  { create(:user, role: player_role) }
  let(:dm_user)     { create(:user, role: dm_role) }
  let(:headers)     { bearer_headers_for(user) }
  let(:dm_headers)  { bearer_headers_for(dm_user) }

  describe 'POST /api/v1/player/groups' do
    it 'bloqueia jogador comum (403)' do
      payload = {
        group: {
          name: 'Campanha Nova',
          description: 'Primeira aventura',
          season: 'verao',
          day: 1,
          year: 1
        }
      }

      expect {
        post '/api/v1/player/groups', params: payload, headers: headers, as: :json
      }.not_to change(Group, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it 'permite ao mestre (DM/Admin) criar e seta dm_user_id = current_user.id' do
      payload = {
        group: {
          name: 'Campanha Nova',
          description: 'Primeira aventura',
          season: 'verao',
          day: 1,
          year: 1
        }
      }

      expect {
        post '/api/v1/player/groups', params: payload, headers: dm_headers, as: :json
      }.to change(Group, :count).by(1)

      expect(response).to have_http_status(:created)
      json = response.parsed_body['group']
      expect(json['name']).to eq('Campanha Nova')
      expect(json['dm_user_id']).to eq(dm_user.id)

      group = Group.last
      expect(group.dm_user_id).to eq(dm_user.id)
    end

    it 'ignora dm_user_id vindo do payload (server-set) para o mestre' do
      payload = {
        group: {
          name: 'Campanha hostil',
          day: 1,
          dm_user_id: other_user.id
        }
      }

      post '/api/v1/player/groups', params: payload, headers: dm_headers, as: :json
      expect(response).to have_http_status(:created)
      expect(Group.last.dm_user_id).to eq(dm_user.id)
    end
  end

  describe 'GET /api/v1/player/groups' do
    it 'jogador ve grupos em que tem personagem ou é mestre da mesa (dm_user_id)' do
      via_chr = create(:group, name: 'ViaChr')
      create(:character, user: user, group: via_chr)
      owned_no_char = create(:group, name: 'OwnedNoChar', dm_user_id: user.id)
      foreign = create(:group, name: 'Foreign', dm_user_id: other_user.id)

      get '/api/v1/player/groups', headers: headers

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['groups'].map { |g| g['id'] }
      expect(ids).to include(via_chr.id, owned_no_char.id)
      expect(ids).not_to include(foreign.id)
    end

    it 'mestre site-wide ve todos os grupos (dono, via personagem e de terceiros)' do
      owned   = create(:group, name: 'Owned', dm_user_id: dm_user.id)
      via_chr = create(:group, name: 'ViaChr')
      create(:character, user: dm_user, group: via_chr)
      foreign = create(:group, name: 'Foreign', dm_user_id: other_user.id)

      get '/api/v1/player/groups', headers: dm_headers

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['groups'].map { |g| g['id'] }
      expect(ids).to include(owned.id, via_chr.id, foreign.id)
    end

    it 'nao duplica quando o mestre e dono e tambem tem character no mesmo grupo' do
      g = create(:group, name: 'Both', dm_user_id: dm_user.id)
      create(:character, user: dm_user, group: g)

      get '/api/v1/player/groups', headers: dm_headers

      ids = response.parsed_body['groups'].map { |g| g['id'] }
      expect(ids.count(g.id)).to eq(1)
    end

    it 'inclui nivel, raca, classe e subclasse em members para roster da campanha' do
      grp = create(:group, name: 'RosterCamp')
      k = create(:klass, name: 'Patrulheiro', api_index: 'ranger_spec_roster')
      sk = create(:sub_klass, klass: k, name: 'Rastreador Urbano', api_index: 'urban_tracker_roster')
      elf = create(:race, name: 'Elfo da Spec')
      char = create(:character, user: user, group: grp, name: 'Adimael')
      sheet = create(:sheet, character: char, race: elf, avatar_customization: { 'hairStyle' => 'long', 'outfit' => 'ranger-leathers' })
      create(:sheet_klass, sheet: sheet, klass: k, sub_klass: sk, level: 9)

      get '/api/v1/player/groups', headers: headers

      expect(response).to have_http_status(:ok)
      g = response.parsed_body['groups'].find { |x| x['id'] == grp.id }
      expect(g).to be_present
      m = g['members'].find { |x| x['id'] == char.id }
      expect(m['name']).to eq('Adimael')
      expect(m['display_name']).to eq('Adimael')
      expect(m['avatar_customization']).to include('hairStyle' => 'long', 'outfit' => 'ranger-leathers')
      expect(m['level']).to eq(9)
      expect(m['race_name']).to eq('Elfo da Spec')
      expect(m['class_name']).to eq('Patrulheiro')
      expect(m['subclass_name']).to eq('Rastreador Urbano')
      expect(m['klass_api_index']).to eq('ranger_spec_roster')
    end

    it 'expoe display_name sem prefixo [Pn] mantendo name bruto' do
      grp = create(:group, name: 'TagCamp')
      hum = create(:race, name: 'Humano Spec')
      char = create(:character, user: user, group: grp, name: '[P81] Zorro')
      create(:sheet, character: char, race: hum)

      get '/api/v1/player/groups', headers: headers

      g = response.parsed_body['groups'].find { |x| x['id'] == grp.id }
      m = g['members'].find { |x| x['id'] == char.id }
      expect(m['name']).to eq('[P81] Zorro')
      expect(m['display_name']).to eq('Zorro')
    end
  end

  describe 'GET /api/v1/player/groups/:id' do
    it 'autoriza o mestre site-wide mesmo sem personagem no grupo' do
      group = create(:group, name: 'Solo DM', dm_user_id: dm_user.id)

      get "/api/v1/player/groups/#{group.id}", headers: dm_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['group']['id']).to eq(group.id)
    end

    it 'autoriza usuario que tem character no grupo' do
      group = create(:group, name: 'Via Char')
      create(:character, user: user, group: group)

      get "/api/v1/player/groups/#{group.id}", headers: headers

      expect(response).to have_http_status(:ok)
    end

    it 'nao autoriza dono legado sem personagem se nao for site-DM' do
      group = create(:group, name: 'OwnedLegacy', dm_user_id: user.id)

      get "/api/v1/player/groups/#{group.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'retorna 404 para grupo de outro usuario sem character vinculado' do
      foreign = create(:group, name: 'Foreign', dm_user_id: other_user.id)

      get "/api/v1/player/groups/#{foreign.id}", headers: headers

      expect(response).to have_http_status(:not_found)
    end

    it 'retorna 404 para grupo inexistente' do
      get '/api/v1/player/groups/999999', headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH /api/v1/player/groups/:id' do
    it 'bloqueia jogador comum mesmo com personagem no grupo (403)' do
      group = create(:group, name: 'Antigo')
      create(:character, user: user, group: group)

      patch "/api/v1/player/groups/#{group.id}",
            params: { group: { name: 'Hackeado' } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:forbidden)
      expect(group.reload.name).to eq('Antigo')
    end

    it 'permite ao mestre atualizar campos basicos' do
      group = create(:group, name: 'Antigo', dm_user_id: dm_user.id)

      patch "/api/v1/player/groups/#{group.id}",
            params: { group: { name: 'Renomeado' } },
            headers: dm_headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(group.reload.name).to eq('Renomeado')
    end

    it 'bloqueia update por jogador em grupo alheio (404 — set_group antes do check de mestre)' do
      foreign = create(:group, name: 'Foreign', dm_user_id: other_user.id)

      patch "/api/v1/player/groups/#{foreign.id}",
            params: { group: { name: 'Hackeado' } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.name).to eq('Foreign')
    end
  end

  describe 'DELETE /api/v1/player/groups/:id' do
    it 'bloqueia jogador comum (403)' do
      group = create(:group, name: 'Meu')
      create(:character, user: user, group: group)

      expect {
        delete "/api/v1/player/groups/#{group.id}", headers: headers
      }.not_to change(Group, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it 'permite ao mestre site-wide remover grupo de outro dono' do
      foreign = create(:group, name: 'Foreign', dm_user_id: other_user.id)

      expect {
        delete "/api/v1/player/groups/#{foreign.id}", headers: dm_headers
      }.to change(Group, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end

    it 'permite ao mestre deletar' do
      group = create(:group, name: 'Solo DM', dm_user_id: dm_user.id)

      expect {
        delete "/api/v1/player/groups/#{group.id}", headers: dm_headers
      }.to change(Group, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end

    it 'permite ao mestre apagar grupo com personagens (desvincula no DB)' do
      group     = create(:group, name: 'Mesa com heroi', dm_user_id: dm_user.id)
      character = create(:character, user: user, group: group)

      expect {
        delete "/api/v1/player/groups/#{group.id}", headers: dm_headers
      }.to change(Group, :count).by(-1)

      expect(response).to have_http_status(:ok)
      expect(character.reload.group_id).to be_nil
    end
  end

  describe 'POST /api/v1/player/groups com upload de cover_image' do
    let(:upload) do
      Rack::Test::UploadedFile.new(
        StringIO.new('fake-png-bytes'),
        'image/png',
        original_filename: 'capa.png',
      )
    end

    it 'anexa cover_image e responde com URL apontando para rails_blob' do
      post '/api/v1/player/groups',
           params: {
             group: {
               name: 'Com capa',
               day: 1,
               cover_image: upload,
             },
           },
           headers: dm_headers.except('CONTENT_TYPE')

      expect(response).to have_http_status(:created)
      group = Group.last
      expect(group.cover_image).to be_attached
      url = response.parsed_body['group']['cover_image_url']
      expect(url).to be_present
      expect(url).to include('rails/active_storage/blobs')
    end
  end
end
