# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::DiaryEntriesController', type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:character) { create(:character, user: user, name: 'Diarista', background: 'Teste') }

  describe 'GET /api/v1/player/characters/:character_id/diary_entries' do
    it 'lista entradas do personagem em ordem updated_at desc' do
      old_entry = create(:diary_entry, character: character, title: 'Antiga', updated_at: 2.days.ago)
      new_entry = create(:diary_entry, character: character, title: 'Recente', updated_at: 1.minute.ago)

      get "/api/v1/player/characters/#{character.id}/diary_entries", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['diary_entries'].pluck('id')).to eq([new_entry.id, old_entry.id])
    end

    it 'rejeita acesso a personagem de outro usuario com 404' do
      foreign_char = create(:character, user: other_user, name: 'Foreign', background: 'X')
      get "/api/v1/player/characters/#{foreign_char.id}/diary_entries", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/player/characters/:character_id/diary_entries' do
    it 'cria uma nova entrada com defaults validos' do
      payload = {
        diary_entry: {
          title: 'Nova entrada',
          content: 'Hoje aconteceu algo importante.',
          font_family: 'Crimson Text',
          font_size: 18,
          text_color: '#1a237e',
          page_color: '#fff8e1'
        }
      }

      expect {
        post "/api/v1/player/characters/#{character.id}/diary_entries",
             params: payload, headers: headers, as: :json
      }.to change { character.diary_entries.count }.by(1)

      expect(response).to have_http_status(:created)
      json = response.parsed_body['diary_entry']
      expect(json['title']).to eq('Nova entrada')
      expect(json['font_family']).to eq('Crimson Text')
      expect(json['character_id']).to eq(character.id)
    end

    it '422 quando font_size esta fora do intervalo' do
      payload = { diary_entry: { title: 'Bad', content: '...', font_size: 999 } }
      post "/api/v1/player/characters/#{character.id}/diary_entries",
           params: payload, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PUT /api/v1/player/characters/:character_id/diary_entries/:id' do
    it 'atualiza uma entrada existente' do
      entry = create(:diary_entry, character: character, title: 'Old')

      put "/api/v1/player/characters/#{character.id}/diary_entries/#{entry.id}",
          params: { diary_entry: { title: 'Renamed', content: 'updated' } },
          headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['diary_entry']['title']).to eq('Renamed')
      expect(entry.reload.content).to eq('updated')
    end

    it '404 quando a entrada pertence a outro personagem' do
      other_entry = create(:diary_entry)
      put "/api/v1/player/characters/#{character.id}/diary_entries/#{other_entry.id}",
          params: { diary_entry: { title: 'Hack' } },
          headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/player/characters/:character_id/diary_entries/:id' do
    it 'remove a entrada' do
      entry = create(:diary_entry, character: character)

      expect {
        delete "/api/v1/player/characters/#{character.id}/diary_entries/#{entry.id}", headers: headers
      }.to change { character.diary_entries.count }.by(-1)

      expect(response).to have_http_status(:no_content)
    end
  end
end
