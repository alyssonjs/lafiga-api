# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Player::SchedulesController', type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }

  let(:group) { create(:group) }
  let!(:char_a) { create(:character, user: user, name: 'Char A', group: group) }
  let!(:char_b) { create(:character, user: user, name: 'Char B', group: group) }
  let!(:char_c) { create(:character, user: user, name: 'Char C', group: group) }

  describe 'POST /api/v1/player/schedules' do
    it 'cria a sessao anexando todos os personagens do grupo quando character_ids esta ausente' do
      payload = {
        schedule: {
          group_id: group.id,
          title: 'Sessao 1',
          date: Date.tomorrow.iso8601,
          scheduled_time: '19:00'
        }
      }

      expect {
        post '/api/v1/player/schedules', params: payload, headers: headers, as: :json
      }.to change(Schedule, :count).by(1)

      expect(response).to have_http_status(:created)
      schedule = Schedule.last
      expect(schedule.character_ids.sort).to eq([char_a.id, char_b.id, char_c.id].sort)
      json = response.parsed_body['schedule']
      expect(json['character_ids'].sort).to eq([char_a.id, char_b.id, char_c.id].sort)
    end

    it 'restringe a vinculacao ao subset informado em character_ids' do
      payload = {
        schedule: {
          group_id: group.id,
          title: 'Sessao subset',
          date: Date.tomorrow.iso8601,
          character_ids: [char_a.id, char_c.id]
        }
      }

      post '/api/v1/player/schedules', params: payload, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      schedule = Schedule.last
      expect(schedule.character_ids.sort).to eq([char_a.id, char_c.id])
    end

    it 'rejeita character_ids fora do grupo com 422' do
      foreign_char = create(:character, user: user, name: 'Foreign')
      payload = {
        schedule: {
          group_id: group.id,
          title: 'Sessao invalida',
          date: Date.tomorrow.iso8601,
          character_ids: [char_a.id, foreign_char.id]
        }
      }

      expect {
        post '/api/v1/player/schedules', params: payload, headers: headers, as: :json
      }.not_to change { Schedule.where(title: 'Sessao invalida').count }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejeita criacao em grupo de outro usuario com 403' do
      foreign_group = create(:group)
      payload = {
        schedule: {
          group_id: foreign_group.id,
          title: 'Sessao alheia',
          date: Date.tomorrow.iso8601
        }
      }

      post '/api/v1/player/schedules', params: payload, headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH /api/v1/player/schedules/:id' do
    let(:date_dim) { DateDimension.find_or_create_by!(date: Date.tomorrow) { |d| d.year = Date.tomorrow.year; d.month = Date.tomorrow.month; d.day = Date.tomorrow.day; d.day_of_week = Date.tomorrow.wday; d.day_name = Date.tomorrow.strftime('%A'); d.is_weekend = false; d.available = true } }
    let(:schedule) { create(:schedule, group: group, date_dimension: date_dim, status: :waiting) }

    before do
      [char_a, char_b].each { |c| ScheduleCharacter.create!(schedule: schedule, character: c) }
    end

    it 'reconcilia character_ids: adiciona novos e remove ausentes preservando os mantidos' do
      original_link = ScheduleCharacter.find_by!(schedule: schedule, character: char_a)

      payload = {
        schedule: {
          character_ids: [char_a.id, char_c.id]
        }
      }

      patch "/api/v1/player/schedules/#{schedule.id}",
            params: payload, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(schedule.reload.character_ids.sort).to eq([char_a.id, char_c.id])
      # Link de char_a preservado (nao re-criado)
      expect(ScheduleCharacter.find_by(schedule: schedule, character: char_a).id).to eq(original_link.id)
      # Link de char_b removido
      expect(ScheduleCharacter.find_by(schedule: schedule, character: char_b)).to be_nil
    end

    it 'rejeita reconciliar com personagem fora do grupo' do
      foreign_char = create(:character, user: user, name: 'Outsider')
      payload = { schedule: { character_ids: [char_a.id, foreign_char.id] } }

      patch "/api/v1/player/schedules/#{schedule.id}",
            params: payload, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      # Estado original preservado
      expect(schedule.reload.character_ids.sort).to eq([char_a.id, char_b.id])
    end

    it 'permite atualizar group_id quando o novo grupo pertence ao usuario' do
      new_group = create(:group)
      create(:character, user: user, name: 'Other Group Char', group: new_group)

      patch "/api/v1/player/schedules/#{schedule.id}",
            params: { schedule: { group_id: new_group.id } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(schedule.reload.group_id).to eq(new_group.id)
    end

    it 'permite atualizar xp_awarded' do
      patch "/api/v1/player/schedules/#{schedule.id}",
            params: { schedule: { xp_awarded: 450 } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(schedule.reload.xp_awarded).to eq(450)
      expect(response.parsed_body['schedule']['xp_awarded']).to eq(450)
    end

    it 'permite vincular battle_map_id' do
      battle_map = create(:battle_map, user: user, group: group)

      patch "/api/v1/player/schedules/#{schedule.id}",
            params: { schedule: { battle_map_id: battle_map.id } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(schedule.reload.battle_map_id).to eq(battle_map.id)
      expect(response.parsed_body['schedule']['battle_map_id']).to eq(battle_map.id)
    end

    it 'permite atualizar dm_notes' do
      patch "/api/v1/player/schedules/#{schedule.id}",
            params: { schedule: { dm_notes: "Rumo ao covil — lembrete de loot.\n" } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(schedule.reload.dm_notes).to eq("Rumo ao covil — lembrete de loot.\n")
      expect(response.parsed_body['schedule']['dm_notes']).to eq("Rumo ao covil — lembrete de loot.\n")
    end

    it 'rejeita group_id de grupo alheio com 403' do
      foreign_group = create(:group)

      patch "/api/v1/player/schedules/#{schedule.id}",
            params: { schedule: { group_id: foreign_group.id } }, headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'GET /api/v1/player/schedules/:id' do
    let(:date_dim) { DateDimension.find_or_create_by!(date: Date.tomorrow) { |d| d.assign_attributes(year: Date.tomorrow.year, month: Date.tomorrow.month, day: Date.tomorrow.day, day_of_week: Date.tomorrow.wday, day_name: Date.tomorrow.strftime('%A'), is_weekend: false, available: true) } }
    let(:schedule) { create(:schedule, group: group, date_dimension: date_dim, status: :waiting) }

    before do
      ScheduleCharacter.create!(schedule: schedule, character: char_a)
    end

    it 'devolve schedule com group_id e battle_map_id no JSON' do
      battle_map = create(:battle_map, user: user, group: group)
      schedule.update!(battle_map_id: battle_map.id)

      get "/api/v1/player/schedules/#{schedule.id}", headers: headers

      expect(response).to have_http_status(:ok)
      json = response.parsed_body['schedule']
      expect(json['id']).to eq(schedule.id)
      expect(json['group_id']).to eq(group.id)
      expect(json['battle_map_id']).to eq(battle_map.id)
    end
  end

  describe 'GET /api/v1/player/schedules com character_id (campanha do grupo)' do
    let(:date_dim) do
      DateDimension.find_or_create_by!(date: Date.tomorrow) do |d|
        d.assign_attributes(
          year: Date.tomorrow.year, month: Date.tomorrow.month, day: Date.tomorrow.day,
          day_of_week: Date.tomorrow.wday, day_name: Date.tomorrow.strftime('%A'),
          is_weekend: false, available: true,
        )
      end
    end
    let!(:ally_char) { create(:character, user: other_user, name: 'Aliado', group: group) }
    let!(:schedule_other_participant_only) do
      create(:schedule, group: group, date_dimension: date_dim, status: :waiting, title: 'Mesa aberta')
    end

    before do
      ScheduleCharacter.create!(schedule: schedule_other_participant_only, character: ally_char)
    end

    it 'inclui sessões do grupo mesmo quando o personagem filtrado não está em schedule_characters' do
      get '/api/v1/player/schedules', params: { character_id: char_a.id }, headers: headers

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['schedules'].map { |s| s['id'] }
      expect(ids).to include(schedule_other_participant_only.id)
    end
  end

  describe 'GET /api/v1/player/schedules — jogador fora do grupo (calendário hub)' do
    let(:date_dim) do
      DateDimension.find_or_create_by!(date: Date.tomorrow) do |d|
        d.assign_attributes(
          year: Date.tomorrow.year, month: Date.tomorrow.month, day: Date.tomorrow.day,
          day_of_week: Date.tomorrow.wday, day_name: Date.tomorrow.strftime('%A'),
          is_weekend: false, available: true,
        )
      end
    end
    let(:foreign_group) { create(:group) }
    let!(:foreign_char) { create(:character, user: other_user, group: foreign_group) }
    let!(:foreign_schedule) do
      create(
        :schedule,
        group: foreign_group,
        date_dimension: date_dim,
        status: :waiting,
        title: 'Mesa outro grupo',
        dm_notes: 'Segredo do mestre',
      )
    end

    before do
      ScheduleCharacter.create!(schedule: foreign_schedule, character: foreign_char)
    end

    it 'lista a sessão mesmo sem pertencer ao grupo' do
      get '/api/v1/player/schedules', headers: headers

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['schedules'].map { |s| s['id'] }
      expect(ids).to include(foreign_schedule.id)
    end

    it 'redige dm_notes na listagem para quem não tem vínculo com a mesa' do
      get '/api/v1/player/schedules', headers: headers

      row = response.parsed_body['schedules'].find { |s| s['id'] == foreign_schedule.id }
      expect(row['dm_notes']).to eq('')
    end

    it 'permite GET show e redige dm_notes para jogador alheio' do
      get "/api/v1/player/schedules/#{foreign_schedule.id}", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['schedule']['id']).to eq(foreign_schedule.id)
      expect(response.parsed_body['schedule']['dm_notes']).to eq('')
    end

    it 'exibe dm_notes no show para jogador com personagem na sessão' do
      get "/api/v1/player/schedules/#{foreign_schedule.id}", headers: bearer_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['schedule']['dm_notes']).to eq('Segredo do mestre')
    end

    it 'rejeita PATCH de jogador alheio (404 — fora do for_hub_player)' do
      patch "/api/v1/player/schedules/#{foreign_schedule.id}",
            params: { schedule: { title: 'Hack' } }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET /api/v1/player/schedules como DM site-wide' do
    let(:dm_role) { Role.find_or_create_by!(name: 'DM') }
    let(:dm_user) { create(:user, role: dm_role) }
    let(:dm_headers) { bearer_headers_for(dm_user) }
    let(:date_dim) { DateDimension.find_or_create_by!(date: Date.tomorrow) { |d| d.assign_attributes(year: Date.tomorrow.year, month: Date.tomorrow.month, day: Date.tomorrow.day, day_of_week: Date.tomorrow.wday, day_name: Date.tomorrow.strftime('%A'), is_weekend: false, available: true) } }
    let!(:visible_schedule) { create(:schedule, group: group, date_dimension: date_dim, status: :waiting) }

    it 'lista sessões de grupos em que o DM não possui personagem' do
      get '/api/v1/player/schedules', headers: dm_headers

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['schedules'].map { |s| s['id'] }
      expect(ids).to include(visible_schedule.id)
    end
  end

  describe 'GET /api/v1/player/schedules — mestre da mesa sem personagem no grupo' do
    let(:date_dim) do
      DateDimension.find_or_create_by!(date: Date.tomorrow) do |d|
        d.assign_attributes(
          year: Date.tomorrow.year, month: Date.tomorrow.month, day: Date.tomorrow.day,
          day_of_week: Date.tomorrow.wday, day_name: Date.tomorrow.strftime('%A'),
          is_weekend: false, available: true,
        )
      end
    end
    let(:table_owner) { create(:user) }
    let!(:owned_campaign) { create(:group, dm_user: table_owner) }
    let!(:session_on_table) { create(:schedule, group: owned_campaign, date_dimension: date_dim, status: :waiting) }

    it 'inclui sessões do grupo em que o usuário é dm_user_id mesmo sem PC no grupo' do
      get '/api/v1/player/schedules', headers: bearer_headers_for(table_owner)

      expect(response).to have_http_status(:ok)
      ids = response.parsed_body['schedules'].map { |s| s['id'] }
      expect(ids).to include(session_on_table.id)
    end
  end

  describe 'POST /api/v1/player/schedules — validação de data e veto' do
    let(:dm_role) { Role.find_or_create_by!(name: 'DM') }
    let(:dm_user) { create(:user, role: dm_role) }
    let(:dm_headers) { bearer_headers_for(dm_user) }

    it 'rejeita criação em data passada (422)' do
      payload = {
        schedule: {
          group_id: group.id,
          title: 'No passado',
          date: Date.yesterday.iso8601,
        },
      }

      post '/api/v1/player/schedules', params: payload, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Schedule.where(title: 'No passado')).not_to exist
    end

    it 'rejeita criação quando o dia está vetado (available false)' do
      d = Date.tomorrow
      dd = DateDimension.find_or_create_by!(date: d) do |dim|
        dim.assign_attributes(
          year: d.year, month: d.month, day: d.day,
          day_of_week: d.wday, day_name: d.strftime('%A'),
          is_weekend: false, available: true,
        )
      end
      dd.update!(available: false)

      payload = {
        schedule: {
          group_id: group.id,
          title: 'Dia bloqueado',
          date: d.iso8601,
        },
      }

      post '/api/v1/player/schedules', params: payload, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error'].to_s).to include('indisponível')
    end

    it 'DM pode criar sessão em grupo em que não participa com personagem' do
      foreign_group = create(:group)
      create(:character, user: other_user, group: foreign_group)

      payload = {
        schedule: {
          group_id: foreign_group.id,
          title: 'Mesa alheia',
          date: Date.tomorrow.iso8601,
        },
      }

      post '/api/v1/player/schedules', params: payload, headers: dm_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(Schedule.last.group_id).to eq(foreign_group.id)
    end
  end
end
