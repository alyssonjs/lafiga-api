# frozen_string_literal: true

require 'rails_helper'

# Relatar bug (botão no header). Cobre: criação (JSON e multipart c/ anexo),
# persistência de `context`, validações (título/descrição obrigatórios, anexo
# inválido), auth (401) e isolamento (index só os próprios do usuário).
RSpec.describe 'Api::V1::Player::BugReports', type: :request do
  let(:player_role) { Role.find_by(name: 'Player') || create(:role, name: 'Player') }
  let(:dm_role)     { Role.find_by(name: 'DM') || create(:role, name: 'DM') }
  let(:user)        { create(:user, role: player_role) }
  let(:other_user)  { create(:user, role: player_role) }
  let(:dm)          { create(:user, role: dm_role) }

  let(:png) do
    Rack::Test::UploadedFile.new(
      StringIO.new("\x89PNG\r\n\x1a\nfake"), 'image/png', original_filename: 'shot.png',
    )
  end
  let(:pdf) do
    Rack::Test::UploadedFile.new(
      StringIO.new('%PDF-1.4 fake'), 'application/pdf', original_filename: 'doc.pdf',
    )
  end

  it 'cria bug report (JSON) com contrato camelCase e persiste o context' do
    post '/api/v1/player/bug_reports',
         params: { bug_report: {
           title: 'Fúria some no reload', description: 'Os pips resetam.',
           steps_to_reproduce: '1. Gastar fúria 2. F5', severity: 'high',
           context: { url: 'https://app/character/9', pathname: '/character/9', characterId: '9', role: 'player' }
         } },
         headers: bearer_headers_for(user), as: :json

    expect(response).to have_http_status(:created), -> { response.body }
    br = response.parsed_body['bug_report']
    expect(br['title']).to eq('Fúria some no reload')
    expect(br['severity']).to eq('high')
    expect(br['status']).to eq('aberto')
    expect(br['kind']).to eq('bug')
    expect(br['userId']).to eq(user.id)
    expect(br['context']).to include('pathname' => '/character/9', 'characterId' => '9')
    expect(BugReport.last.context).to include('role' => 'player')
  end

  it 'cria com anexo via multipart (context como string JSON) e devolve URL de blob' do
    post '/api/v1/player/bug_reports',
         params: { bug_report: {
           title: 'Tela branca', description: 'Ao abrir o mapa.', severity: 'critical',
           context: { url: 'https://app/dm/maps', role: 'dm' }.to_json,
           attachments: [png]
         } },
         headers: bearer_headers_for(user).except('CONTENT_TYPE')

    expect(response).to have_http_status(:created), -> { response.body }
    br = response.parsed_body['bug_report']
    expect(br['attachments'].size).to eq(1)
    expect(br['attachments'].first['url']).to include('rails/active_storage/blobs')
    expect(br['context']).to include('role' => 'dm')
    expect(BugReport.last.attachments).to be_attached
  end

  it 'rejeita sem título ou sem descrição (422)' do
    post '/api/v1/player/bug_reports',
         params: { bug_report: { description: 'Sem título', severity: 'low' } },
         headers: bearer_headers_for(user), as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    post '/api/v1/player/bug_reports',
         params: { bug_report: { title: 'Sem descrição', severity: 'low' } },
         headers: bearer_headers_for(user), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejeita anexo de tipo inválido (422)' do
    post '/api/v1/player/bug_reports',
         params: { bug_report: { title: 'X', description: 'Y', severity: 'low', attachments: [pdf] } },
         headers: bearer_headers_for(user).except('CONTENT_TYPE')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(BugReport.count).to eq(0)
  end

  it 'exige autenticação (401)' do
    post '/api/v1/player/bug_reports',
         params: { bug_report: { title: 'X', description: 'Y' } }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'DM cria uma MELHORIA (kind=improvement)' do
    post '/api/v1/player/bug_reports',
         params: { bug_report: { title: 'Filtro no calendário', description: 'Seria bom filtrar por estação.', severity: 'medium', kind: 'improvement' } },
         headers: bearer_headers_for(dm), as: :json
    expect(response).to have_http_status(:created), -> { response.body }
    expect(response.parsed_body['bug_report']['kind']).to eq('improvement')
    expect(BugReport.last.kind).to eq('improvement')
  end

  it 'jogador NÃO-DM também pode solicitar melhoria (kind=improvement)' do
    post '/api/v1/player/bug_reports',
         params: { bug_report: { title: 'Sugestão de UX', description: 'X', severity: 'low', kind: 'improvement' } },
         headers: bearer_headers_for(user), as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body['bug_report']['kind']).to eq('improvement')
    expect(BugReport.last.kind).to eq('improvement')
  end

  it 'index devolve apenas os relatos do próprio usuário' do
    mine = create(:bug_report, user: user, title: 'Meu bug')
    create(:bug_report, user: other_user, title: 'Bug alheio')

    get '/api/v1/player/bug_reports', headers: bearer_headers_for(user)
    expect(response).to have_http_status(:ok)
    ids = response.parsed_body['bug_reports'].map { |b| b['id'] }
    expect(ids).to eq([mine.id])
  end
end
