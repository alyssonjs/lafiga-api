# frozen_string_literal: true

require 'rails_helper'

# Triagem de bug reports (DM/Admin site-wide). Cobre: auth (não-DM bloqueado),
# listagem de TODOS + filtro por status/severidade, e update de status + metadata.
RSpec.describe 'Api::V1::Admin::BugReports', type: :request do
  let(:dm_role)     { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:dm)          { create(:user, role: dm_role) }
  let(:player)      { create(:user, role: player_role) }

  it 'bloqueia player não-DM (401/403)' do
    get '/api/v1/admin/bug_reports', headers: bearer_headers_for(player)
    expect(response.status).to be_in([401, 403])
  end

  it 'DM lista TODOS os relatos e filtra por status/severidade' do
    b1 = create(:bug_report, user: player, severity: :critical, status: :aberto)
    b2 = create(:bug_report, user: dm, severity: :low, status: :feito)

    get '/api/v1/admin/bug_reports', headers: bearer_headers_for(dm)
    expect(response).to have_http_status(:ok)
    ids = response.parsed_body['bug_reports'].map { |b| b['id'] }
    expect(ids).to include(b1.id, b2.id)
    expect(response.parsed_body['meta']['count']).to be >= 2

    get '/api/v1/admin/bug_reports', params: { status: 'feito' }, headers: bearer_headers_for(dm)
    ids = response.parsed_body['bug_reports'].map { |b| b['id'] }
    expect(ids).to eq([b2.id])

    get '/api/v1/admin/bug_reports', params: { severity: 'critical' }, headers: bearer_headers_for(dm)
    ids = response.parsed_body['bug_reports'].map { |b| b['id'] }
    expect(ids).to eq([b1.id])
  end

  it 'DM filtra por kind (bug vs melhoria)' do
    bug = create(:bug_report, user: player, kind: :bug)
    imp = create(:bug_report, user: dm, kind: :improvement)

    get '/api/v1/admin/bug_reports', params: { kind: 'improvement' }, headers: bearer_headers_for(dm)
    ids = response.parsed_body['bug_reports'].map { |b| b['id'] }
    expect(ids).to eq([imp.id])

    get '/api/v1/admin/bug_reports', params: { kind: 'bug' }, headers: bearer_headers_for(dm)
    ids = response.parsed_body['bug_reports'].map { |b| b['id'] }
    expect(ids).to eq([bug.id])
  end

  it 'DM vê um relato e atualiza status + metadata (triagem)' do
    b = create(:bug_report, user: player, status: :aberto)

    get "/api/v1/admin/bug_reports/#{b.id}", headers: bearer_headers_for(dm)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['bug_report']['id']).to eq(b.id)

    patch "/api/v1/admin/bug_reports/#{b.id}",
          params: { bug_report: { status: 'feito', metadata: { ai_summary: 'Fix no reload', duplicate_of: nil } } },
          headers: bearer_headers_for(dm), as: :json
    expect(response).to have_http_status(:ok)
    b.reload
    expect(b.status).to eq('feito')
    expect(b.metadata).to include('ai_summary' => 'Fix no reload')
  end

  it 'DM edita o conteúdo (título/descrição/passos/tipo/severidade)' do
    b = create(:bug_report, user: player, kind: :bug, severity: :low,
                            title: 'Antigo', description: 'desc antiga')

    patch "/api/v1/admin/bug_reports/#{b.id}",
          params: { bug_report: {
            kind: 'improvement', title: 'Novo título', description: 'nova descrição',
            steps_to_reproduce: '1. abrir 2. clicar', severity: 'high'
          } },
          headers: bearer_headers_for(dm), as: :json
    expect(response).to have_http_status(:ok)
    b.reload
    expect(b.kind).to eq('improvement')
    expect(b.title).to eq('Novo título')
    expect(b.description).to eq('nova descrição')
    expect(b.steps_to_reproduce).to eq('1. abrir 2. clicar')
    expect(b.severity).to eq('high')
  end

  it 'rejeita edição que esvazia campo obrigatório (422)' do
    b = create(:bug_report, user: player, title: 'Válido')

    patch "/api/v1/admin/bug_reports/#{b.id}",
          params: { bug_report: { title: '' } },
          headers: bearer_headers_for(dm), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(b.reload.title).to eq('Válido')
  end

  it 'retorna 404 para relato inexistente' do
    get '/api/v1/admin/bug_reports/999999', headers: bearer_headers_for(dm)
    expect(response).to have_http_status(:not_found)
  end
end
