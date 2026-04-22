require 'rails_helper'

RSpec.describe 'Api::V1::Admin::Spells', type: :request do
  let(:admin_role)  { Role.find_or_create_by!(name: 'Admin') }
  let(:player_role) { Role.find_or_create_by!(name: 'Player') }
  let(:admin)       { create(:user, role: admin_role) }
  let(:player)      { create(:user, role: player_role) }
  let(:headers)     { bearer_headers_for(admin).merge('Content-Type' => 'application/json') }

  let!(:spell) do
    Spell.create!(
      api_index: 'test-fireball',
      name: 'Bola De Fogo',
      level: 3,
      school: 'Evocation',
      range: '45 metros',
      components: 'V, S, M',
      material: 'uma pequena bola de morcego',
      ritual: false,
      duration: 'Instantanea',
      concentration: false,
      casting_time: '1 acao',
      desc: 'Uma explosao de fogo brilhante salta...',
      higher_level: 'Quando voce conjura essa magia usando um espaco de magia de 4 nivel ou superior...'
    )
  end

  describe 'GET /api/v1/admin/spells' do
    it 'requires admin' do
      get '/api/v1/admin/spells', headers: bearer_headers_for(player)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'lists spells with filters' do
      get '/api/v1/admin/spells', params: { level: 3 }, headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['spells'].map { |s| s['api_index'] }).to include('test-fireball')
    end
  end

  describe 'POST /api/v1/admin/spells' do
    it 'creates a spell and derives api_index when omitted' do
      payload = { spell: { name: 'Magia De Teste Nova', level: 1, school: 'Evocation', desc: 'corpo de descricao' } }
      expect {
        post '/api/v1/admin/spells', params: payload.to_json, headers: headers
      }.to change(Spell, :count).by(1)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body['spell']['api_index']).to eq('pt-magia-de-teste-nova')
    end

    it 'returns errors when name is missing' do
      payload = { spell: { level: 1, school: 'Evocation' } }
      post '/api/v1/admin/spells', params: payload.to_json, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH /api/v1/admin/spells/:id' do
    it 'updates by api_index' do
      payload = { spell: { desc: 'novo corpo' } }
      patch "/api/v1/admin/spells/#{spell.api_index}", params: payload.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(spell.reload.desc).to eq('novo corpo')
    end

    it 'updates by numeric id' do
      payload = { spell: { range: '60 metros' } }
      patch "/api/v1/admin/spells/#{spell.id}", params: payload.to_json, headers: headers
      expect(response).to have_http_status(:ok)
      expect(spell.reload.range).to eq('60 metros')
    end

    it 'rejects non-admin (player) with 401' do
      payload = { spell: { desc: 'tentativa de hijack' } }
      patch "/api/v1/admin/spells/#{spell.api_index}",
            params: payload.to_json,
            headers: bearer_headers_for(player).merge('Content-Type' => 'application/json')
      expect(response).to have_http_status(:unauthorized)
      expect(spell.reload.desc).not_to eq('tentativa de hijack')
    end
  end

  describe 'DELETE /api/v1/admin/spells/:id' do
    it 'deletes when no SpellSource exists' do
      expect {
        delete "/api/v1/admin/spells/#{spell.api_index}", headers: headers
      }.to change(Spell, :count).by(-1)
      expect(response).to have_http_status(:no_content)
    end

    it 'returns 422 with sources when SpellSource exists' do
      klass = Klass.first || Klass.create!(name: 'Mago', api_index: 'wizard')
      SpellSource.create!(source_type: 'Klass', source_id: klass.id, spell_id: spell.id, always_prepared: false)
      delete "/api/v1/admin/spells/#{spell.api_index}", headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('spell_in_use')
      expect(body['sources'].first['source_type']).to eq('Klass')
    end

    it 'rejects non-admin (player) with 401' do
      delete "/api/v1/admin/spells/#{spell.api_index}",
             headers: bearer_headers_for(player)
      expect(response).to have_http_status(:unauthorized)
      expect(Spell.exists?(spell.id)).to be true
    end
  end

  # Pipeline integrado: garante que o que o admin cria/edita aparece imediatamente
  # via Api::V1::Public::Spells (que e o que o front consome em CompendiumSpells e
  # SpellcastingPanel). Falha aqui significa cache stale ou serializer divergente.
  describe 'integration: admin CRUD reflete em Public#show e Public#index' do
    it 'POST -> GET show retorna a magia recem-criada com desc integral' do
      payload = {
        spell: {
          name: 'Magia Pipeline Teste',
          level: 2,
          school: 'Evocation',
          range: '18 metros',
          desc: 'B' * 700,
          higher_level: 'Texto de niveis superiores'
        }
      }
      post '/api/v1/admin/spells', params: payload.to_json, headers: headers
      expect(response).to have_http_status(:created)
      created_id = JSON.parse(response.body).dig('spell', 'id')

      get "/api/v1/public/spells/#{created_id}"
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['spell']['desc'].length).to eq(700)
      expect(body['spell']['higher_level']).to eq('Texto de niveis superiores')
    end

    it 'PATCH -> GET show reflete a edicao' do
      patch "/api/v1/admin/spells/#{spell.api_index}",
            params: { spell: { desc: 'descricao editada via admin' } }.to_json,
            headers: headers
      expect(response).to have_http_status(:ok)

      get "/api/v1/public/spells/#{spell.id}"
      expect(JSON.parse(response.body).dig('spell', 'desc')).to eq('descricao editada via admin')
    end
  end
end

RSpec.describe 'Api::V1::Public::Spells view param', type: :request do
  let!(:spell) do
    Spell.create!(
      api_index: 'view-test-spell',
      name: 'View Test Spell',
      level: 1,
      school: 'Evocation',
      desc: 'A' * 600,
      higher_level: 'Em niveis superiores...'
    )
  end

  let!(:short_spell) do
    Spell.create!(
      api_index: 'short-test-spell',
      name: 'Short Test Spell',
      level: 0,
      school: 'Evocation',
      desc: 'curta',
      higher_level: ''
    )
  end

  it 'returns slim desc by default on index' do
    get '/api/v1/public/spells', params: { ids: [spell.id] }
    body = JSON.parse(response.body)
    row = body['spells'].find { |s| s['api_index'] == 'view-test-spell' }
    expect(row['desc'].length).to be < 250
    expect(row['view']).to eq('slim')
  end

  it 'returns full desc when view=full' do
    get '/api/v1/public/spells', params: { ids: [spell.id], view: 'full' }
    body = JSON.parse(response.body)
    row = body['spells'].find { |s| s['api_index'] == 'view-test-spell' }
    expect(row['desc'].length).to eq(600)
  end

  it 'show always returns full desc' do
    get "/api/v1/public/spells/#{spell.id}"
    body = JSON.parse(response.body)
    expect(body['spell']['desc'].length).to eq(600)
  end

  it 'slim view sinaliza descriptionTruncated quando trunca (front faz lazy-fetch)' do
    get '/api/v1/public/spells', params: { ids: [spell.id] }
    row = JSON.parse(response.body)['spells'].find { |s| s['api_index'] == 'view-test-spell' }
    truncated = row['description_truncated'] || row['descriptionTruncated']
    expect(truncated).to eq(true)
  end

  it 'slim view NAO trunca nem sinaliza truncated quando desc e curta' do
    get '/api/v1/public/spells', params: { ids: [short_spell.id] }
    row = JSON.parse(response.body)['spells'].find { |s| s['api_index'] == 'short-test-spell' }
    expect(row['desc']).to eq('curta')
    truncated = row['description_truncated'] || row['descriptionTruncated']
    expect(truncated).not_to eq(true)
  end

  it 'slim view omite higher_level (otimizacao de payload)' do
    get '/api/v1/public/spells', params: { ids: [spell.id] }
    row = JSON.parse(response.body)['spells'].find { |s| s['api_index'] == 'view-test-spell' }
    # higher_level deve estar ausente OU vazio no slim. O front nao depende dele
    # ate o usuario abrir o detalhe (e ai o GET show traz tudo).
    expect(row['higher_level'].to_s).to eq('')
  end

  it 'full view inclui higher_level integral' do
    get '/api/v1/public/spells', params: { ids: [spell.id], view: 'full' }
    row = JSON.parse(response.body)['spells'].find { |s| s['api_index'] == 'view-test-spell' }
    expect(row['higher_level']).to eq('Em niveis superiores...')
  end
end

RSpec.describe 'Api::V1::Public::Spells view param', type: :request do
  let!(:spell) do
    Spell.create!(
      api_index: 'view-test-spell',
      name: 'View Test Spell',
      level: 1,
      school: 'Evocation',
      desc: 'A' * 600,
      higher_level: 'Em niveis superiores...'
    )
  end

  it 'returns slim desc by default on index' do
    get '/api/v1/public/spells', params: { ids: [spell.id] }
    body = JSON.parse(response.body)
    row = body['spells'].find { |s| s['api_index'] == 'view-test-spell' }
    expect(row['desc'].length).to be < 250
    expect(row['view']).to eq('slim')
  end

  it 'returns full desc when view=full' do
    get '/api/v1/public/spells', params: { ids: [spell.id], view: 'full' }
    body = JSON.parse(response.body)
    row = body['spells'].find { |s| s['api_index'] == 'view-test-spell' }
    expect(row['desc'].length).to eq(600)
  end

  it 'show always returns full desc' do
    get "/api/v1/public/spells/#{spell.id}"
    body = JSON.parse(response.body)
    expect(body['spell']['desc'].length).to eq(600)
  end
end
