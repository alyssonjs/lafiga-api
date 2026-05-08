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

    it 'copia mapa, NPCs de combate, estado de combate e linked_npc_character_ids da sessao anterior do grupo' do
      day_prev = Date.current + 45
      day_next = day_prev + 1
      dim_prev = DateDimension.find_or_create_by!(date: day_prev) do |d|
        d.assign_attributes(
          year: day_prev.year,
          month: day_prev.month,
          day: day_prev.day,
          day_of_week: day_prev.wday,
          day_name: day_prev.strftime('%A'),
          is_weekend: day_prev.saturday? || day_prev.sunday?,
          available: true,
        )
      end
      dim_next = DateDimension.find_or_create_by!(date: day_next) do |d|
        d.assign_attributes(
          year: day_next.year,
          month: day_next.month,
          day: day_next.day,
          day_of_week: day_next.wday,
          day_name: day_next.strftime('%A'),
          is_weekend: day_next.saturday? || day_next.sunday?,
          available: true,
        )
      end

      prior_map = create(:battle_map, :with_tokens, user: user, group: group)
      prior = create(
        :schedule,
        group: group,
        date_dimension: dim_prev,
        status: :completed,
        battle_map_id: prior_map.id,
        scheduled_time: '19:00',
        linked_npc_character_ids: [char_a.id],
      )
      [char_a, char_b, char_c].each { |c| ScheduleCharacter.create!(schedule: prior, character: c) }

      npc = create(:combat_npc, schedule: prior, name: 'Orc Guerreiro')
      cs = create(:combat_state, schedule: prior, active: true, round: 2, current_turn_index: 1)
      create(
        :combat_combatant,
        combat_state: cs,
        combatable: npc,
        name: 'Orc Guerreiro',
        position: 0,
        initiative: 15,
        hp_current: 3,
        hp_max: 15,
      )
      create(
        :combat_combatant,
        combat_state: cs,
        combatable: char_b,
        name: char_b.name,
        position: 1,
        initiative: 12,
        hp_current: 5,
        hp_max: 22,
      )

      if Schedule.supports_dm_temp_npc_character_ids?
        prior.update!(dm_temp_npc_character_ids: [char_b.id])
      end

      payload = {
        schedule: {
          group_id: group.id,
          title: 'Sessao continua',
          date: day_next.iso8601,
          scheduled_time: '19:00',
          character_ids: [char_a.id],
        },
      }

      expect do
        post '/api/v1/player/schedules', params: payload, headers: headers, as: :json
      end.to change(Schedule, :count).by(1)
        .and change(BattleMap, :count).by(1)
        .and change(CombatNpc, :count).by(1)
        .and change(CombatState, :count).by(1)
        .and change(CombatCombatant, :count).by(2)

      expect(response).to have_http_status(:created)
      body = response.parsed_body['schedule']
      new_sched = Schedule.find(body['id'])
      expect(new_sched.battle_map_id).not_to eq(prior_map.id)
      expect(new_sched.battle_map.tokens.size).to eq(prior_map.tokens.size)
      expect(new_sched.linked_npc_character_ids).to eq([char_a.id])
      expect(body['linked_npc_character_ids']).to eq([char_a.id])
      if Schedule.supports_dm_temp_npc_character_ids?
        expect(new_sched.reload.dm_temp_npc_character_ids_normalized).to eq([])
      end

      expect(new_sched.combat_npcs.count).to eq(1)
      expect(new_sched.combat_npcs.first.name).to eq('Orc Guerreiro')
      expect(new_sched.combat_state).to be_present
      expect(new_sched.combat_state.active).to eq(true)
      expect(new_sched.combat_state.round).to eq(2)
      expect(new_sched.combat_state.current_turn_index).to eq(1)

      ccs = new_sched.combat_state.combat_combatants.order(:position).to_a
      expect(ccs.size).to eq(2)
      orc_row = ccs.find { |c| c.combatable_type == 'CombatNpc' }
      pc_row = ccs.find { |c| c.combatable_type == 'Character' }
      expect(orc_row.hp_current).to eq(3)
      expect(pc_row.combatable_id).to eq(char_b.id)
      expect(pc_row.hp_current).to eq(5)
    end
  end

  describe 'PATCH /api/v1/player/schedules/:id' do
    let(:date_dim) { DateDimension.find_or_create_by!(date: Date.tomorrow) { |d| d.year = Date.tomorrow.year; d.month = Date.tomorrow.month; d.day = Date.tomorrow.day; d.day_of_week = Date.tomorrow.wday; d.day_name = Date.tomorrow.strftime('%A'); d.is_weekend = false; d.available = true } }
    let(:schedule) { create(:schedule, group: group, date_dimension: date_dim, status: :waiting) }

    before do
      group.update!(dm_user: user)
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

    it 'permite atualizar linked_npc_character_ids' do
      patch "/api/v1/player/schedules/#{schedule.id}",
            params: { schedule: { linked_npc_character_ids: [char_a.id, char_c.id] } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(schedule.reload.linked_npc_character_ids).to eq([char_a.id, char_c.id])
      expect(response.parsed_body['schedule']['linked_npc_character_ids']).to eq([char_a.id, char_c.id])
    end

    it 'permite ao mestre da mesa atualizar dm_temp_npc_character_ids' do
      skip unless Schedule.supports_dm_temp_npc_character_ids?

      patch "/api/v1/player/schedules/#{schedule.id}",
            params: { schedule: { dm_temp_npc_character_ids: [char_a.id] } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(schedule.reload.dm_temp_npc_character_ids_normalized).to eq([char_a.id])
      expect(response.parsed_body['schedule']['dm_temp_npc_character_ids']).to eq([char_a.id])
    end

    it 'ignora dm_temp_npc_character_ids no PATCH quando o usuario nao e mestre da mesa' do
      skip unless Schedule.supports_dm_temp_npc_character_ids?

      group.update!(dm_user: other_user)

      patch "/api/v1/player/schedules/#{schedule.id}",
            params: { schedule: { dm_temp_npc_character_ids: [char_a.id] } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(schedule.reload.dm_temp_npc_character_ids_normalized).to eq([])
      expect(response.parsed_body['schedule']['dm_temp_npc_character_ids']).to eq([])
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

    it 'ignora dm_notes no PATCH quando o usuario nao e mestre da campanha' do
      group.update!(dm_user: other_user)
      schedule.update!(dm_notes: 'Original')

      patch "/api/v1/player/schedules/#{schedule.id}",
            params: { schedule: { dm_notes: 'Tentativa' } },
            headers: headers,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(schedule.reload.dm_notes).to eq('Original')
      expect(response.parsed_body['schedule']['dm_notes']).to eq('')
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

    # Modo observador: jogador autenticado SEM personagem na sessao (e sem
    # personagem no grupo) chega via link direto `/sessions/:id/play`. O
    # `index` filtra (for_player_index), entao a sessao nao aparece na lista,
    # mas o `show` deve devolver 200 para que o frontend hidrate via
    # `ensureSessionLoaded` e renderize a tela em read-only.
    it 'permite que um observador (sem personagem no grupo) acesse o show' do
      observer = create(:user)
      observer_headers = bearer_headers_for(observer)

      # observer NAO tem personagem em `group` (campanha alvo) — somente em outro grupo.
      other_group = create(:group)
      create(:character, user: observer, group: other_group)

      get "/api/v1/player/schedules/#{schedule.id}", headers: observer_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['schedule']['id']).to eq(schedule.id)
    end

    it 'permite que um observador SEM nenhum personagem acesse o show' do
      observer = create(:user) # zero personagens
      observer_headers = bearer_headers_for(observer)

      get "/api/v1/player/schedules/#{schedule.id}", headers: observer_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['schedule']['id']).to eq(schedule.id)
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

    it 'redige dm_notes no show mesmo para jogador com personagem na sessão' do
      get "/api/v1/player/schedules/#{foreign_schedule.id}", headers: bearer_headers_for(other_user)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['schedule']['dm_notes']).to eq('')
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

  describe 'POST /api/v1/player/schedules/:id/cancel' do
    let(:date_dim) do
      DateDimension.find_or_create_by!(date: Date.tomorrow) do |d|
        d.assign_attributes(
          year: Date.tomorrow.year, month: Date.tomorrow.month, day: Date.tomorrow.day,
          day_of_week: Date.tomorrow.wday, day_name: Date.tomorrow.strftime('%A'),
          is_weekend: false, available: true,
        )
      end
    end
    let(:schedule) { create(:schedule, group: group, date_dimension: date_dim, status: :waiting, title: 'Sessao cancelavel') }

    before { ScheduleCharacter.create!(schedule: schedule, character: char_a) }

    it 'permite jogador com personagem na sessão cancelar' do
      post "/api/v1/player/schedules/#{schedule.id}/cancel", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(schedule.reload).to be_cancelled
    end

    it 'rejeita jogador sem personagem na sessão com 403' do
      post "/api/v1/player/schedules/#{schedule.id}/cancel",
           headers: bearer_headers_for(other_user),
           as: :json

      expect(response).to have_http_status(:forbidden)
      expect(schedule.reload).to be_waiting
    end

    it 'permite DM site-wide cancelar' do
      dm_role = Role.find_or_create_by!(name: 'DM')
      dm_user = create(:user, role: dm_role)
      post "/api/v1/player/schedules/#{schedule.id}/cancel",
           headers: bearer_headers_for(dm_user),
           as: :json

      expect(response).to have_http_status(:ok)
      expect(schedule.reload).to be_cancelled
    end
  end
end
