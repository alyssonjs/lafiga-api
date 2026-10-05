# frozen_string_literal: true

require 'rails_helper'

# "Onde paramos" e a timeline da campanha (05/10): `.chronological.last` dava 500 em produção — o Rails não inverte a
# ordem `NULLS LAST` sozinho (ActiveRecord::IrreversibleOrderError). A última sessão é a última da TIMELINE: a sem
# horário conta como o fim do dia.
RSpec.describe 'Api::V1::Player::GroupsController — a última sessão da campanha', type: :request do
  let(:user) { create(:user) }
  let(:headers) { bearer_headers_for(user) }
  let(:group) { create(:group) }
  let(:dias) { {} }

  def dia(data)
    dias[data] ||= DateDimension.find_by(date: Date.parse(data)) || create(:date_dimension, date: Date.parse(data))
  end

  # direto no banco: a regra de "uma sessão agendada por vez" não é o assunto aqui
  def sessao!(data, hora, status, titulo)
    s = create(:schedule, group: group, title: titulo, date_dimension: dia(data), status: :completed)
    s.update_columns(status: Schedule.statuses.fetch(status.to_s), scheduled_time: hora)
    s.reload
  end

  let!(:antiga)   { sessao!('2031-03-01', '19:00', :completed, 'Antiga') }
  let!(:tarde)    { sessao!('2031-03-15', '14:00', :completed, 'Mesma data, 14h') }
  let!(:sem_hora) { sessao!('2031-03-15', nil, :completed, 'Mesma data, sem horário') }
  let!(:futura)   { sessao!('2031-04-20', '19:00', :reserved, 'Futura') }

  describe 'GET last_session ("Onde paramos")' do
    it 'devolve a última concluída — a sem horário conta como o fim do dia, como na timeline' do
      get "/api/v1/player/groups/#{group.id}/last_session", headers: headers

      expect(response).to have_http_status(:ok), -> { response.body }
      expect(response.parsed_body.dig('last_session', 'id')).to eq(sem_hora.id)
    end

    it 'a sessão em andamento depois das concluídas é a última' do
      # uma sessão aberta por grupo (índice `idx_schedules_open_per_group`): a futura sai antes
      futura.update_columns(status: Schedule.statuses.fetch('cancelled'))
      agora = sessao!('2031-03-20', '20:00', :in_progress, 'Agora')

      get "/api/v1/player/groups/#{group.id}/last_session", headers: headers

      expect(response.parsed_body.dig('last_session', 'id')).to eq(agora.id)
    end

    it 'sem sessão concluída: null, sem erro' do
      Schedule.where(id: [antiga.id, tarde.id, sem_hora.id]).delete_all

      get "/api/v1/player/groups/#{group.id}/last_session", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['last_session']).to be_nil
    end
  end

  describe 'GET timeline' do
    it 'last_completed é a última concluída, e a lista segue cronológica' do
      get "/api/v1/player/groups/#{group.id}/timeline", headers: headers

      expect(response).to have_http_status(:ok), -> { response.body }
      json = response.parsed_body
      expect(json.dig('last_completed', 'id')).to eq(sem_hora.id)
      expect(json['schedules'].map { |s| s['id'] }).to eq([antiga.id, tarde.id, sem_hora.id, futura.id])
    end
  end
end
